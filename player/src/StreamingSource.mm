// GPL-2.0-or-later. A few seconds of bounded RAM buffering, no full-movie cache.
#import <Foundation/Foundation.h>
#include "StreamingSource.hpp"
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <chrono>
#include <cmath>
#include <fcntl.h>
#include <poll.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <unistd.h>
struct StreamingSource::Impl {
    shuttle_output::Profile profile;
    NSTask* task=nil;NSURL* directory=nil;NSFileHandle* log=nil;
    std::thread videoThread,audioThread,waitThread;
    std::atomic<bool> stop{false},exited{false},videoDone{false},audioDone{false};
    std::atomic<int> exitCode{0};
    std::mutex mutex;std::condition_variable changed;
    std::deque<std::vector<uint8_t>> frames;std::deque<int32_t> audio;
    double seconds=0;bool hasAudio=true,buffering=true;int videoFD=-1,audioFD=-1;
    size_t frameBytes=0,capacity=0;bool videoStarted=false,audioStarted=false;
    bool readBytes(int fd,void* target,size_t count){
        auto* bytes=static_cast<uint8_t*>(target);size_t got=0;bool& started=fd==videoFD?videoStarted:audioStarted;
        while(got<count&&!stop){ssize_t n=::read(fd,bytes+got,count-got);if(n>0){started=true;got+=size_t(n);continue;}if(n==0&&started)break;
            if(n<0&&errno!=EINTR&&errno!=EAGAIN&&errno!=EWOULDBLOCK)break;
            if(exited)break;std::this_thread::sleep_for(std::chrono::microseconds(100));
        }return got==count;
    }
    void videoReader(){@autoreleasepool{
        for(;;){std::vector<uint8_t> frame(frameBytes);if(!readBytes(videoFD,frame.data(),frame.size()))break;
            std::unique_lock<std::mutex> lock(mutex);changed.wait(lock,[&]{return stop||frames.size()<capacity;});if(stop)break;frames.push_back(std::move(frame));changed.notify_all();
        }videoDone=true;changed.notify_all();
    }}
    void audioReader(){@autoreleasepool{
        std::vector<int32_t> samples(2048*2);
        // Read smaller chunks so a final partial output frame isn't lost at EOF.
        for(;;){int32_t pair[2];if(!readBytes(audioFD,pair,sizeof(pair)))break;
            samples.clear();samples.push_back(pair[0]);samples.push_back(pair[1]);
            int available=0;if(ioctl(audioFD,FIONREAD,&available)==0){size_t extra=std::min(size_t(std::max(0,available))/8,size_t(2047));size_t old=samples.size();samples.resize(old+extra*2);if(extra&&!readBytes(audioFD,samples.data()+old,extra*8))break;}
            std::unique_lock<std::mutex> lock(mutex);changed.wait(lock,[&]{return stop||audio.size()+samples.size()<=48000*2*8;});if(stop)break;audio.insert(audio.end(),samples.begin(),samples.end());changed.notify_all();
        }audioDone=true;changed.notify_all();
    }}
    ~Impl(){
        stop=true;changed.notify_all();if(task.running)[task terminate];
        auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);while(task&& !exited&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(20));
        if(task&&!exited)kill(-task.processIdentifier,SIGKILL);if(waitThread.joinable())waitThread.join();
        if(videoThread.joinable())videoThread.join();if(audioThread.joinable())audioThread.join();
        if(videoFD>=0)close(videoFD);if(audioFD>=0)close(audioFD);[log closeFile];
        if(directory)[NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    }
};
StreamingSource::StreamingSource(const std::string& filename,shuttle_output::Mode mode,shuttle_output::Sizing sizing,double startSeconds):impl(new Impl){@autoreleasepool{
    auto& s=*impl;s.profile=shuttle_output::profile(mode);s.frameBytes=size_t(s.profile.width)*s.profile.height*2;s.capacity=size_t(std::ceil(4.*s.profile.rateNom/s.profile.rateDen));
    NSURL* file=[NSURL fileURLWithPath:@(filename.c_str())];NSData* data=[NSData dataWithContentsOfURL:file];if(data.length>1024*1024)throw std::runtime_error("Invalid streaming configuration");
    NSDictionary* config=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![config isKindOfClass:NSDictionary.class]||![config[@"version"] isEqual:@1]||![config[@"inputs"] isKindOfClass:NSArray.class])throw std::runtime_error("Invalid streaming configuration");
    if(![config[@"duration"] isKindOfClass:NSNumber.class]||![config[@"video"] isKindOfClass:NSNumber.class]||![config[@"audio"] isKindOfClass:NSNumber.class])throw std::runtime_error("Invalid stream metadata");s.seconds=[config[@"duration"] doubleValue];if(!std::isfinite(s.seconds)||s.seconds<=0)throw std::runtime_error("This stream has no usable duration. Use Download first.");
    if(!std::isfinite(startSeconds)||startSeconds<0||startSeconds>=s.seconds)throw std::runtime_error("Seek position is outside the stream");
    NSArray* inputs=config[@"inputs"];if(!inputs.count||inputs.count>2)throw std::runtime_error("No playable stream");
    NSInteger video=[config[@"video"] integerValue],audio=[config[@"audio"] integerValue];s.hasAudio=audio>=0;s.audioDone=!s.hasAudio;
    if(video<0||video>=NSInteger(inputs.count)||audio>=NSInteger(inputs.count))throw std::runtime_error("Invalid stream tracks");
    NSURL* bin=NSBundle.mainBundle.executableURL.URLByDeletingLastPathComponent;
    // Tests pass the same signed executables explicitly; production config never does.
    NSString* testBin=NSProcessInfo.processInfo.environment[@"SHUTTLE_STREAM_TEST_BIN"];
    if(testBin.length)bin=[NSURL fileURLWithPath:testBin isDirectory:YES];
    NSURL* ffmpeg=[[bin URLByAppendingPathComponent:@"WebTools"] URLByAppendingPathComponent:@"ffmpeg"],*worker=[bin URLByAppendingPathComponent:@"ShuttleWebWorker"];
    if(![NSFileManager.defaultManager isExecutableFileAtPath:ffmpeg.path]||![NSFileManager.defaultManager isExecutableFileAtPath:worker.path])throw std::runtime_error("Streaming tools missing. Reinstall Shuttle Player.");
    s.directory=[file.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@"buffer-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    if(![NSFileManager.defaultManager createDirectoryAtURL:s.directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil])throw std::runtime_error("Cannot create stream buffer");
    NSURL* videoPipe=[s.directory URLByAppendingPathComponent:@"video.pipe"],*audioPipe=[s.directory URLByAppendingPathComponent:@"audio.pipe"];
    if(mkfifo(videoPipe.fileSystemRepresentation,0600)||(s.hasAudio&&mkfifo(audioPipe.fileSystemRepresentation,0600)))throw std::runtime_error("Cannot create stream pipes");
    s.videoFD=open(videoPipe.fileSystemRepresentation,O_RDONLY|O_NONBLOCK|O_CLOEXEC);if(s.hasAudio)s.audioFD=open(audioPipe.fileSystemRepresentation,O_RDONLY|O_NONBLOCK|O_CLOEXEC);
    if(s.videoFD<0||(s.hasAudio&&s.audioFD<0))throw std::runtime_error("Cannot open stream pipes");
    NSMutableArray<NSString*>* args=[NSMutableArray arrayWithArray:@[ffmpeg.path,@"-hide_banner",@"-nostdin",@"-y",@"-loglevel",@"error",@"-filter_threads",@"2"]];
    for(id value in inputs){
        if(![value isKindOfClass:NSDictionary.class])throw std::runtime_error("Invalid stream input");NSDictionary* input=value;NSString* address=input[@"url"];NSURL* url=[address isKindOfClass:NSString.class]?[NSURL URLWithString:address]:nil;
        BOOL testFile=testBin.length&&[url.scheme isEqual:@"file"];
        if(!url||(!testFile&&![@[@"https",@"http"] containsObject:url.scheme.lowercaseString])||url.user||url.password)throw std::runtime_error("Unsupported stream address");
        [args addObjectsFromArray:@[@"-protocol_whitelist",testFile?@"file":@"http,https,tcp,tls,crypto",@"-threads",@"2"]];
        if(!testFile)[args addObjectsFromArray:@[@"-tls_verify",@"1",@"-rw_timeout",@"15000000",@"-reconnect",@"1",@"-reconnect_streamed",@"1",@"-reconnect_delay_max",@"3"]];
        // Google video delivery throttles open-ended requests; keep each range small.
        NSString* host=url.host.lowercaseString;if([host isEqual:@"googlevideo.com"]||[host hasSuffix:@".googlevideo.com"])[args addObjectsFromArray:@[@"-request_size",@"1048576",@"-short_seek_size",@"1048576",@"-multiple_requests",@"1"]];
        NSDictionary* headers=input[@"headers"];NSMutableString* fields=[NSMutableString string];
        if([headers isKindOfClass:NSDictionary.class])for(NSString* key in @[@"User-Agent",@"Referer",@"Origin",@"Accept"]){NSString* header=headers[key];if([header isKindOfClass:NSString.class]&&header.length<4096&&[header rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound)[fields appendFormat:@"%@: %@\r\n",key,header];}
        if(fields.length)[args addObjectsFromArray:@[@"-headers",fields]];
        if(startSeconds>0)[args addObjectsFromArray:@[@"-ss",[NSString stringWithFormat:@"%.9f",startSeconds]]];
        [args addObjectsFromArray:@[@"-i",testFile?url.path:address]];
    }
    unsigned displayWidth=unsigned(std::lround(s.profile.width*s.profile.pixelAspect()));NSString* scale;
    if(sizing==shuttle_output::Sizing::Stretch)scale=[NSString stringWithFormat:@"scale=%u:%u",s.profile.width,s.profile.height];
    else {
        NSString* fit=sizing==shuttle_output::Sizing::Fit?@"decrease":@"increase";
        NSString* bounds=sizing==shuttle_output::Sizing::Fit?[NSString stringWithFormat:@"pad=%u:%u:(ow-iw)/2:(oh-ih)/2:black",displayWidth,s.profile.height]:[NSString stringWithFormat:@"crop=%u:%u",displayWidth,s.profile.height];
        scale=[NSString stringWithFormat:@"scale=%u:%u:force_original_aspect_ratio=%@:force_divisible_by=2:reset_sar=1,%@,scale=%u:%u",displayWidth,s.profile.height,fit,bounds,s.profile.width,s.profile.height];
    }
    NSString* filter=[NSString stringWithFormat:@"fps=%u/%u:start_time=0,%@:out_color_matrix=%@:out_range=tv,setsar=1,format=uyvy422",s.profile.rateNom,s.profile.rateDen,scale,s.profile.width==720?@"bt601":@"bt709"];
    [args addObjectsFromArray:@[@"-map",[NSString stringWithFormat:@"%ld:v:0",long(video)],@"-an",@"-sn",@"-dn",@"-vf",filter,@"-c:v",@"rawvideo",@"-threads:v",@"1",@"-pix_fmt",@"uyvy422",@"-f",@"rawvideo",videoPipe.path]];
    if(s.hasAudio)[args addObjectsFromArray:@[@"-map",[NSString stringWithFormat:@"%ld:a:0",long(audio)],@"-vn",@"-sn",@"-dn",@"-af",@"aresample=48000:async=1:first_pts=0",@"-ar",@"48000",@"-ac",@"2",@"-c:a",@"pcm_s32le",@"-f",@"s32le",audioPipe.path]];
    NSURL* log=[s.directory URLByAppendingPathComponent:@"decoder.log"];[NSFileManager.defaultManager createFileAtPath:log.path contents:nil attributes:@{NSFilePosixPermissions:@0600}];s.log=[NSFileHandle fileHandleForWritingAtPath:log.path];
    s.task=[NSTask new];s.task.executableURL=worker;s.task.arguments=args;s.task.standardInput=NSFileHandle.fileHandleWithNullDevice;s.task.standardOutput=NSFileHandle.fileHandleWithNullDevice;s.task.standardError=s.log;
    NSError* error=nil;if(![s.task launchAndReturnError:&error]){s.exited=true;throw std::runtime_error("Cannot start stream decoder");}
    fcntl(s.videoFD,F_SETFL,fcntl(s.videoFD,F_GETFL,0)&~O_NONBLOCK);if(s.hasAudio)fcntl(s.audioFD,F_SETFL,fcntl(s.audioFD,F_GETFL,0)&~O_NONBLOCK);
    auto* state=&s;s.waitThread=std::thread([state]{@autoreleasepool{[state->task waitUntilExit];state->exitCode=state->task.terminationStatus;state->exited=true;state->changed.notify_all();}});
    s.videoThread=std::thread([state]{state->videoReader();});if(s.hasAudio)s.audioThread=std::thread([state]{state->audioReader();});
}}
StreamingSource::~StreamingSource()=default;
double StreamingSource::duration()const{return impl->seconds;}
StreamingSource::State StreamingSource::read(bool paused,uint64_t frame,std::vector<uint8_t>& picture,std::vector<int32_t>& pcm){
    auto& s=*impl;State result;std::unique_lock<std::mutex> lock(s.mutex);double rate=double(s.profile.rateNom)/s.profile.rateDen;
    bool done=s.videoDone;size_t need=size_t(s.profile.audioFrames(frame))*2;
    result.videoSeconds=double(s.frames.size())/rate;result.audioSeconds=s.hasAudio&&!s.audioDone?double(s.audio.size())/(48000*2):1000.;result.buffered=std::min(result.videoSeconds,result.audioSeconds);
    double target=done?std::min(3.,result.videoSeconds):3.;
    if(s.buffering&&result.buffered>=target)s.buffering=false;
    if(!paused&&!s.buffering&&!s.frames.empty()&&(!s.hasAudio||s.audio.size()>=need||s.audioDone)){
        picture=std::move(s.frames.front());s.frames.pop_front();pcm.assign(need*4,0);
        if(s.hasAudio)for(size_t n=0;n<need;++n){if(s.audio.empty())break;pcm[(n/2)*8+n%2]=s.audio.front()/256;s.audio.pop_front();}
        result.advanced=true;
    }else {
        pcm.clear();if(!paused&&!(done&&s.frames.empty())&&(s.frames.empty()||(s.hasAudio&&!s.audioDone&&s.audio.size()<need)))s.buffering=true;
    }
    result.buffering=s.buffering&&!paused;result.ended=done&&s.frames.empty();s.changed.notify_all();
    if(result.ended&&s.exitCode!=0&&!s.stop)throw std::runtime_error("Streaming stopped. Check your internet connection or try Download first.");
    return result;
}
