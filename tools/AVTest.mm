// GPL-2.0-or-later. Native AVFoundation audio/video receive test.
#import <AVFoundation/AVFoundation.h>
#import <CoreMediaIO/CoreMediaIO.h>
#include <atomic>
#include <algorithm>
#include <memory>
#include <vector>
#include <cstdio>
#include <cmath>
#include <cstdint>

@interface AVReceiver : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate> {
@public std::atomic<unsigned> videoCount,audioCount;
@public uint64_t samples,nonzero;
@public double squares,peak,firstAudio,firstVideo;
@public FILE *wav;
@public double lastV,lastA,maxVGap,maxAGap,faultStart,dropSquares;
@public uint64_t lastHash,repeats,run,maxRun,dropSamples;
@public std::vector<double> videoPulses,audioPulses;
@public bool wasWhite,diagnostic;
}
@end
@implementation AVReceiver
- (instancetype)init { if((self=[super init])) { videoCount=0;audioCount=0;samples=0;nonzero=0;squares=0;peak=0;firstAudio=-1;firstVideo=-1;wav=nullptr;lastV=lastA=-1;maxVGap=maxAGap=0;faultStart=-1;dropSquares=0;lastHash=repeats=run=maxRun=dropSamples=0;wasWhite=false;diagnostic=false; }return self; }
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection {
    auto desc=CMSampleBufferGetFormatDescription(sample);
    double pts=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
    if(CMFormatDescriptionGetMediaType(desc)==kCMMediaType_Video) {
        if(++videoCount==1) { firstVideo=pts;printf("First video PTS %.6f; age %.4f s\n",pts,CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))-pts); }
        if(lastV>=0) maxVGap=std::max(maxVGap,pts-lastV);lastV=pts;
        CVPixelBufferRef pixel=CMSampleBufferGetImageBuffer(sample);
        if(pixel && !CVPixelBufferLockBaseAddress(pixel,kCVPixelBufferLock_ReadOnly)) {
            bool planar=CVPixelBufferIsPlanar(pixel);
            const uint8_t *data=static_cast<const uint8_t *>(planar?CVPixelBufferGetBaseAddressOfPlane(pixel,0):CVPixelBufferGetBaseAddress(pixel));
            size_t size=planar?CVPixelBufferGetBytesPerRowOfPlane(pixel,0)*CVPixelBufferGetHeightOfPlane(pixel,0):CVPixelBufferGetBytesPerRow(pixel)*CVPixelBufferGetHeight(pixel);
            uint64_t hash=1469598103934665603ULL;
            for(size_t n=0;n<size;n+=512) { hash^=data[n];hash*=1099511628211ULL; }
            if(videoCount>1 && hash==lastHash) { ++repeats;++run;maxRun=std::max(maxRun,run); }else run=0;
            bool white=data[(CVPixelBufferGetHeight(pixel)/2)*CVPixelBufferGetBytesPerRow(pixel)+(CVPixelBufferGetWidth(pixel)/2)*4]>200;
            if(diagnostic && white && !wasWhite) videoPulses.push_back(pts);
            wasWhite=white;
            lastHash=hash;CVPixelBufferUnlockBaseAddress(pixel,kCVPixelBufferLock_ReadOnly);
        }return;
    }
    const AudioStreamBasicDescription *format=CMAudioFormatDescriptionGetStreamBasicDescription(desc);
    if(++audioCount==1) {
        firstAudio=pts;
        printf("First audio PTS %.6f; %.0f Hz; %u channels; %u bits; flags %u\n",pts,format->mSampleRate,format->mChannelsPerFrame,format->mBitsPerChannel,format->mFormatFlags);
    }
    if(lastA>=0) maxAGap=std::max(maxAGap,pts-lastA);lastA=pts;
    if(format->mBitsPerChannel!=32 || !(format->mFormatFlags&kAudioFormatFlagIsFloat) || format->mChannelsPerFrame!=2) return;
    size_t frames=CMSampleBufferGetNumSamples(sample);
    std::vector<float> pcm(frames*2);
    AudioBufferList list{1,{{2,UInt32(frames*8),pcm.data()}}};
    OSStatus rc=CMSampleBufferCopyPCMDataIntoAudioBufferList(sample,0,int32_t(frames),&list);
    if(rc) { if(audioCount==1) printf("PCM copy error: %d\n",rc);return; }
    for(size_t i=0;i<frames;++i) for(unsigned ch=0;ch<2;++ch) {
        float value=pcm[i*2+ch];
        if(!std::isfinite(value)) value=0;
        double sourceTime=pts+double(i)/48000;
        if(diagnostic && ch==0 && std::abs(value)>0.03 && (audioPulses.empty() || sourceTime-audioPulses.back()>0.5))
            audioPulses.push_back(sourceTime);
        if(faultStart>=0 && sourceTime>=faultStart+0.3 && sourceTime<faultStart+1.7) { dropSquares+=double(value)*value;++dropSamples; }
        squares+=double(value)*value;peak=std::max(peak,double(std::abs(value)));++samples;if(std::abs(value)>1.0e-7f) ++nonzero;
        int16_t pcm=int16_t(std::lround(std::max(-1.0f,std::min(0.999969f,value))*32768));
        if(wav) fwrite(&pcm,2,1,wav);
    }
}
@end
static bool permission(AVMediaType type) {
    auto status=[AVCaptureDevice authorizationStatusForMediaType:type];
    if(status==AVAuthorizationStatusNotDetermined) {
        auto done=std::make_shared<std::atomic<bool>>(false);
        [AVCaptureDevice requestAccessForMediaType:type completionHandler:^(BOOL){ *done=true; }];
        while(!*done) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    return [AVCaptureDevice authorizationStatusForMediaType:type]==AVAuthorizationStatusAuthorized;
}
static void header(FILE *f,uint32_t bytes) {
    const char riff[]="RIFF";fwrite(riff,1,4,f);uint32_t n=bytes+36;fwrite(&n,4,1,f);fwrite("WAVEfmt ",1,8,f);n=16;fwrite(&n,4,1,f);
    uint16_t v=1;fwrite(&v,2,1,f);v=2;fwrite(&v,2,1,f);n=48000;fwrite(&n,4,1,f);n=48000*4;fwrite(&n,4,1,f);v=4;fwrite(&v,2,1,f);v=16;fwrite(&v,2,1,f);fwrite("data",1,4,f);fwrite(&bytes,4,1,f);
}
static OSStatus controlForSeconds(UInt32 selector,double seconds) {
    CMIOObjectPropertyAddress a{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,kCMIOObjectPropertyElementMain};
    UInt32 size=0;OSStatus rc=CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&a,0,nullptr,&size);if(rc) return rc;
    std::vector<CMIOObjectID> devices(size/sizeof(CMIOObjectID));
    rc=CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&a,0,nullptr,size,&size,devices.data());if(rc) return rc;
    for(auto device:devices) {
        a={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,kCMIOObjectPropertyElementMain};
        CFStringRef uid=nullptr;size=sizeof(uid);
        if(CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,&uid)) continue;
        bool match=CFEqual(uid,CFSTR("local.shuttle.camera.pal"));CFRelease(uid);if(!match) continue;
        a={kCMIODevicePropertyStreams,kCMIODevicePropertyScopeInput,kCMIOObjectPropertyElementMain};
        if(CMIOObjectGetPropertyDataSize(device,&a,0,nullptr,&size)) continue;
        std::vector<CMIOStreamID> streams(size/sizeof(CMIOStreamID));
        if(CMIOObjectGetPropertyData(device,&a,0,nullptr,size,&size,streams.data()) || streams.empty()) continue;
        a={selector,kCMIOObjectPropertyScopeGlobal,UInt32('0')};
        NSString *value=[NSString stringWithFormat:@"%.2f",seconds];CFStringRef string=(__bridge CFStringRef)value;
        return CMIOObjectSetPropertyData(streams[0],&a,0,nullptr,sizeof(string),&string);
    }return -1;
}
int main(int argc,char **argv) { @autoreleasepool {
    setvbuf(stdout,nullptr,_IOLBF,0);
    AVCaptureDevice *video=nil,*audio=nil;
    for(AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) if([d.uniqueID containsString:@"local.shuttle.camera"]) video=d;
    for(AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]) {
        printf("Audio input: %s; UID=%s\n",d.localizedName.UTF8String,d.uniqueID.UTF8String);
        if([d.uniqueID containsString:@"local.shuttle.audio"]) audio=d;
    }
    if(argc==2 && !strcmp(argv[1],"--list")) return audio?0:2;
    bool dropout=argc==3 && !strcmp(argv[2],"--dropout");
    if((argc!=2 && !dropout) || !video || !audio) { puts("Shuttle camera and stereo input must both be present.");return 2; }
    if(!permission(AVMediaTypeVideo) || !permission(AVMediaTypeAudio)) { puts("Camera/microphone permission not granted.");return 3; }
    auto *session=[AVCaptureSession new];auto *receiver=[AVReceiver new];
    receiver->wav=fopen(argv[1],"wb");if(!receiver->wav) return 4;header(receiver->wav,0);
    [session beginConfiguration];
    for(AVCaptureDevice *d in @[video,audio]) {
        NSError *error=nil;auto *input=[AVCaptureDeviceInput deviceInputWithDevice:d error:&error];
        if(!input || ![session canAddInput:input]) { NSLog(@"Input setup: %@",error);return 5; }
        [session addInput:input];
    }
    NSError *error=nil;
    if([video lockForConfiguration:&error]) { video.activeFormat=video.formats.firstObject;video.activeVideoMinFrameDuration=video.activeFormat.videoSupportedFrameRateRanges.firstObject.minFrameDuration;video.activeVideoMaxFrameDuration=video.activeVideoMinFrameDuration;[video unlockForConfiguration]; }
    auto *vout=[AVCaptureVideoDataOutput new];vout.alwaysDiscardsLateVideoFrames=YES;
    vout.videoSettings=@{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
    auto *aout=[AVCaptureAudioDataOutput new];
    aout.audioSettings=@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@48000,AVNumberOfChannelsKey:@2,AVLinearPCMBitDepthKey:@32,AVLinearPCMIsFloatKey:@YES,AVLinearPCMIsNonInterleaved:@NO};
    auto queue=dispatch_queue_create("local.shuttle.av-test",DISPATCH_QUEUE_SERIAL);
    [vout setSampleBufferDelegate:receiver queue:queue];[aout setSampleBufferDelegate:receiver queue:queue];
    if(![session canAddOutput:vout] || ![session canAddOutput:aout]) return 6;
    [session addOutput:vout];[session addOutput:aout];[session commitConfiguration];[session startRunning];
    if(dropout) {
        // Exclude the five-field-pair acquisition interval and a partial first pulse.
        puts("Warm up the camera for one second before measuring synchronized pulses.");
        [NSThread sleepForTimeInterval:1];
        OSStatus rc=controlForSeconds('sync',10);
        printf("Diagnostic flash/tone: status %d\n",rc);
        dispatch_sync(queue,^{ receiver->diagnostic=true;receiver->wasWhite=true; });
    }
    for(unsigned i=0;i<10;++i) { [NSThread sleepForTimeInterval:1];
        if(dropout && i==2) {
            OSStatus rc=controlForSeconds('drpt',2);
            printf("Two-second diagnostic video dropout: status %d\n",rc);
            double now=CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()));
            dispatch_sync(queue,^{ receiver->faultStart=now; });
        }
        printf("%us: video=%u audio buffers=%u\n",i+1,receiver->videoCount.load(),receiver->audioCount.load()); }
    [session stopRunning];dispatch_sync(queue,^{});
    uint32_t bytes=uint32_t(receiver->samples*2);fseek(receiver->wav,0,SEEK_SET);header(receiver->wav,bytes);fclose(receiver->wav);receiver->wav=nullptr;
    printf("RESULT video=%u; audio buffers=%u; samples=%llu; nonzero=%llu; RMS=%.6f; peak=%.6f\n",receiver->videoCount.load(),receiver->audioCount.load(),receiver->samples,receiver->nonzero,receiver->samples?sqrt(receiver->squares/receiver->samples):0,receiver->peak);
    printf("TIMING maximum video step %.6f s; maximum audio-buffer step %.6f s; repeated pictures=%llu; longest repeat=%llu; audio RMS during dropout=%.6f\n",receiver->maxVGap,receiver->maxAGap,receiver->repeats,receiver->maxRun,receiver->dropSamples?sqrt(receiver->dropSquares/receiver->dropSamples):0);
    double minOffset=1e9,maxOffset=-1e9;unsigned pairs=0;
    if(dropout) {
        for(double v:receiver->videoPulses) {
            if(v>=receiver->faultStart-0.1 && v<receiver->faultStart+2.3) continue;
            double nearest=1e9;
            for(double a:receiver->audioPulses) if(std::abs(a-v)<std::abs(nearest)) nearest=a-v;
            if(std::abs(nearest)<0.4) {
                minOffset=std::min(minOffset,nearest);maxOffset=std::max(maxOffset,nearest);++pairs;
                printf("SYNC pulse: video %.6f; audio offset %+.6f s\n",v,nearest);
            }
        }
        printf("SYNC matched pulses=%u; audio-minus-video range %+.6f to %+.6f s\n",pairs,minOffset,maxOffset);
    }
    bool pass=receiver->videoCount>0 && receiver->nonzero>0;
    if(dropout) pass=pass && receiver->maxRun>=60 && receiver->maxRun<180 && receiver->dropSamples>0 && receiver->dropSquares>0 && receiver->maxVGap<0.061 && pairs>=4 && maxOffset-minOffset<0.031 && std::abs(minOffset)<0.031 && std::abs(maxOffset)<0.031;
    printf("VALIDATION: %s\n",pass?"PASS":"FAIL");
    return pass?0:7;
} }
