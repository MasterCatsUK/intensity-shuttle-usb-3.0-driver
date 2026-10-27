// Explicit public-site streaming probe. No USB, sound routing or login/cookies.
#import <Foundation/Foundation.h>
#include "../src/WebVideo.mm"
#include "../src/StreamingSource.hpp"
#include <chrono>
#include <thread>
#include <cstdio>
int main(int argc,char**argv){@autoreleasepool{
 if(argc<3||argc>5)return 64;unsigned wanted=argc>3?unsigned(std::max(1.,atof(argv[3]))*25):150;bool realtime=argc>4;NSURL* app=[NSURL fileURLWithPath:@(argv[1])];NSURL* bin=[app URLByAppendingPathComponent:@"Contents/MacOS" isDirectory:YES];setenv("SHUTTLE_STREAM_TEST_BIN",bin.path.UTF8String,1);
 NSURL* cache=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"shuttle-stream-live"] isDirectory:YES];__block BOOL done=NO;__block NSURL* config=nil;PlayerWebVideo* job=[PlayerWebVideo new];job.streaming=YES;job.completion=^(NSURL* file,NSString* title,NSString* error){config=file;printf("Resolved title=%s result=%s\n",title.UTF8String?:"",file?"stream configuration":error.UTF8String?:"cancelled");fflush(stdout);done=YES;};
 auto start=std::chrono::steady_clock::now();[job startURL:playerWebURL(@(argv[2])) tools:[bin URLByAppendingPathComponent:@"WebTools"] worker:[bin URLByAppendingPathComponent:@"ShuttleWebWorker"] cache:cache];NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:100];while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 if(!done){[job cancel];while(!done)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}if(!config)return 1;
 int result=1;try{
  StreamingSource source(config.path.UTF8String,shuttle_output::Mode::HD1080p25,shuttle_output::Sizing::Stretch);std::vector<uint8_t> video;std::vector<int32_t> audio;unsigned frames=0;double peak=0;auto until=std::chrono::steady_clock::now()+std::chrono::seconds(wanted/25+80);auto nextTick=std::chrono::steady_clock::now();unsigned rebuffers=0;bool buffering=false;
  while(frames<wanted&&std::chrono::steady_clock::now()<until){auto state=source.read(false,frames,video,audio);if(frames&&state.buffering&&!buffering)++rebuffers;buffering=state.buffering;if(state.advanced){if(!frames)printf("First frame with 3-second buffer after %.2f seconds including site lookup\n",std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());++frames;for(auto sample:audio)peak=std::max(peak,std::abs(double(sample)));}else if(!realtime)std::this_thread::sleep_for(std::chrono::milliseconds(5));if(realtime){if(frames&&frames%125==0&&state.advanced){printf("At %.1fs: video buffer %.2fs, audio buffer %.2fs, rebuffer events %u\n",frames/25.,state.videoSeconds,state.audioSeconds,rebuffers);fflush(stdout);}nextTick+=std::chrono::milliseconds(40);std::this_thread::sleep_until(nextTick);}if(state.ended)break;}
  printf("Streamed %u whole 1080p frames, peak stereo PCM %.0f; no complete movie file\n",frames,peak);fflush(stdout);printf("Rebuffer events after startup: %u\n",rebuffers);result=frames>=std::min(100u,wanted)&&peak>0&&(!realtime||(!rebuffers&&frames==wanted))?0:2;
 }catch(const std::exception& e){printf("Decoder: %s\n",e.what());}
 // Keep failed diagnostics only in the private test cache for local inspection.
 if(!result)[NSFileManager.defaultManager removeItemAtURL:job.directory error:nil];return result;
}}
