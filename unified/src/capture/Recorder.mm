// GPL-2.0-or-later. Direct CMIO capture with explicit field-preserving software ProRes.
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include <memory>
#include "RecordingCodec.hpp"
#include <algorithm>
#include <atomic>
#include <array>
#include <vector>
#include <deque>
#include <chrono>
#include <csignal>
#include <fcntl.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <cmath>
namespace {
volatile sig_atomic_t interrupted=0;
void interrupt(int){interrupted=1;}
OSStatus property(AudioObjectID obj,AudioObjectPropertySelector key,AudioObjectPropertyScope scope,void *p,UInt32 size){AudioObjectPropertyAddress a{key,scope,0};return AudioObjectGetPropertyData(obj,&a,0,nullptr,&size,p);}
CMIODeviceID videoDevice(){CMIOObjectPropertyAddress a{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};UInt32 size=0;if(CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&a,0,nullptr,&size))return 0;std::vector<CMIODeviceID> ds(size/4);if(CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&a,0,nullptr,size,&size,ds.data()))return 0;for(auto d:ds){CFStringRef uid=nullptr;a={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,0};size=sizeof(uid);if(!CMIOObjectGetPropertyData(d,&a,0,nullptr,size,&size,&uid)){bool yes=uid&&CFEqual(uid,CFSTR("local.shuttle.camera.pal"));if(uid)CFRelease(uid);if(yes)return d;}}return 0;}
AudioDeviceID audioDevice(){AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,0};UInt32 size=0;if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&size))return 0;std::vector<AudioDeviceID> ds(size/4);if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&size,ds.data()))return 0;for(auto d:ds){CFStringRef uid=nullptr;if(!property(d,kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,&uid,sizeof(uid))){bool yes=uid&&CFEqual(uid,CFSTR("local.shuttle.audio.stereo"));if(uid)CFRelease(uid);if(yes)return d;}}return 0;}
struct AudioChunk{uint64_t ns=0;UInt32 frames=0;std::array<float,8192> pcm{};};
struct AudioRing {
 std::array<AudioChunk,128> chunks;std::atomic<unsigned> write{0},read{0};std::atomic<bool> overflow{false},badFormat{false};
 static OSStatus receive(AudioDeviceID,const AudioTimeStamp*,const AudioBufferList *data,const AudioTimeStamp *time,AudioBufferList*,const AudioTimeStamp*,void *ctx){
  auto &r=*(AudioRing*)ctx;unsigned w=r.write.load(std::memory_order_relaxed);if(w-r.read.load(std::memory_order_acquire)>=r.chunks.size()){r.overflow=true;return noErr;}
  if(!(time->mFlags&kAudioTimeStampHostTimeValid)||!data->mNumberBuffers){r.badFormat=true;return noErr;}
  auto &c=r.chunks[w%r.chunks.size()];c.ns=AudioConvertHostTimeToNanos(time->mHostTime);
  if(data->mNumberBuffers==1&&data->mBuffers[0].mNumberChannels==2){c.frames=data->mBuffers[0].mDataByteSize/8;if(c.frames>4096||!data->mBuffers[0].mData){r.badFormat=true;return noErr;}memcpy(c.pcm.data(),data->mBuffers[0].mData,c.frames*8);}
  else if(data->mNumberBuffers==2&&data->mBuffers[0].mNumberChannels==1&&data->mBuffers[1].mNumberChannels==1){c.frames=data->mBuffers[0].mDataByteSize/4;if(c.frames>4096||data->mBuffers[1].mDataByteSize!=c.frames*4||!data->mBuffers[0].mData||!data->mBuffers[1].mData){r.badFormat=true;return noErr;}for(unsigned i=0;i<c.frames;i++)for(unsigned ch=0;ch<2;ch++)c.pcm[2*i+ch]=((const float*)data->mBuffers[ch].mData)[i];}
  else {r.badFormat=true;return noErr;}r.write.store(w+1,std::memory_order_release);return noErr;
 }
};
struct Recorder {
 AVAssetWriter *writer=nil;AVAssetWriterInput *video=nil,*audio=nil;VTCompressionSessionRef encoder=nullptr;CMAudioFormatDescriptionRef audioFormat=nullptr;
 shuttle_recording::Codec codec=shuttle_recording::Codec::ProRes422;bool configured=false;
 CMTime epoch=kCMTimeInvalid,end=kCMTimeZero;CMVideoDimensions dimensions{};CFTypeRef fields=nullptr,detail=nullptr;uint64_t frames=0,audioFrames=0;NSString *failure=nil;std::deque<AudioChunk> pending;
 void fail(NSString *s){if(!failure){failure=[s copy];fprintf(stderr,"ERROR %s\n",s.UTF8String);}}
 bool ready(AVAssetWriterInput *input){auto start=std::chrono::steady_clock::now();while(!input.readyForMoreMediaData){if(writer.status!=AVAssetWriterStatusWriting){fail(writer.error.localizedDescription?:@"Recording writer stopped.");return false;}if(std::chrono::steady_clock::now()-start>std::chrono::seconds(2)){fail(@"Storage cannot keep up with recording.");return false;}usleep(1000);}return true;}
 static void encoded(void *ctx,void*,OSStatus status,VTEncodeInfoFlags,CMSampleBufferRef sample){auto &r=*(Recorder*)ctx;if(status||!sample){r.fail([NSString stringWithFormat:@"%@ encoding failed (%d).",@(shuttle_recording::info(r.codec).title),int(status)]);return;}if(r.failure)return;
  if(!r.video){r.video=[[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:CMSampleBufferGetFormatDescription(sample)];r.video.expectsMediaDataInRealTime=YES;r.video.mediaTimeScale=60000;if(![r.writer canAddInput:r.video]){r.fail(@"Cannot create the video track.");return;}[r.writer addInput:r.video];if(![r.writer startWriting]){r.fail(r.writer.error.localizedDescription);return;}[r.writer startSessionAtSourceTime:kCMTimeZero];}
  if(r.ready(r.video)){if(![r.video appendSampleBuffer:sample])r.fail(r.writer.error.localizedDescription);else r.frames++;}
 }
 bool begin(NSURL *url){if([NSFileManager.defaultManager fileExistsAtPath:url.path]){fail(@"A recording already exists at this path. Choose a new filename.");return false;}NSError *error=nil;writer=[[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];if(!writer){fail(error.localizedDescription);return false;}writer.movieTimeScale=60000;
  AudioStreamBasicDescription asbd{};asbd.mSampleRate=48000;asbd.mFormatID=kAudioFormatLinearPCM;asbd.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;asbd.mBitsPerChannel=32;asbd.mChannelsPerFrame=2;asbd.mBytesPerFrame=asbd.mBytesPerPacket=8;asbd.mFramesPerPacket=1;
  if(CMAudioFormatDescriptionCreate(nullptr,&asbd,0,nullptr,0,nullptr,nullptr,&audioFormat)){fail(@"Cannot create the stereo audio format.");return false;}
  audio=[[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:nil sourceFormatHint:audioFormat];audio.expectsMediaDataInRealTime=YES;if(![writer canAddInput:audio]){fail(@"Cannot create the audio track.");return false;}[writer addInput:audio];return true;
 }
 bool setup(CMFormatDescriptionRef format){dimensions=CMVideoFormatDescriptionGetDimensions(format);fields=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FieldCount);detail=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FieldDetail);if(fields)CFRetain(fields);if(detail)CFRetain(detail);
  if(!shuttle_recording::compatible(codec,fields&&CFEqual(fields,(__bridge CFNumberRef)@2))){fail(@"This codec needs progressive capture. Choose a progressive resolution or an interlaced-compatible codec.");return false;}
  if(codec==shuttle_recording::Codec::Uncompressed){configured=true;return true;}
  OSStatus rc=VTCompressionSessionCreate(nullptr,dimensions.width,dimensions.height,shuttle_recording::info(codec).type,(__bridge CFDictionaryRef)@{(id)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder:@(!shuttle_recording::prores(codec))},nullptr,nullptr,encoded,this,&encoder);
  if(rc){fail([NSString stringWithFormat:@"Cannot start %@ (%d).",@(shuttle_recording::info(codec).title),int(rc)]);return false;}
  for(NSString *key in @[(id)kVTCompressionPropertyKey_FieldCount,(id)kVTCompressionPropertyKey_FieldDetail,(id)kVTCompressionPropertyKey_PixelAspectRatio,(id)kVTCompressionPropertyKey_ColorPrimaries,(id)kVTCompressionPropertyKey_TransferFunction,(id)kVTCompressionPropertyKey_YCbCrMatrix]){
   CFTypeRef value=CMFormatDescriptionGetExtension(format,(__bridge CFStringRef)key); // FieldCount uses a different public extension key.
   if([key isEqual:(id)kVTCompressionPropertyKey_FieldCount])value=fields?: (__bridge CFNumberRef)@1;
   if([key isEqual:(id)kVTCompressionPropertyKey_FieldDetail])value=detail;
   if([key isEqual:(id)kVTCompressionPropertyKey_PixelAspectRatio])value=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_PixelAspectRatio);
   if([key isEqual:(id)kVTCompressionPropertyKey_ColorPrimaries])value=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_ColorPrimaries);
   if([key isEqual:(id)kVTCompressionPropertyKey_TransferFunction])value=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_TransferFunction);
   if([key isEqual:(id)kVTCompressionPropertyKey_YCbCrMatrix])value=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_YCbCrMatrix);
   if(!shuttle_recording::prores(codec)&&([key isEqual:(id)kVTCompressionPropertyKey_FieldCount]||[key isEqual:(id)kVTCompressionPropertyKey_FieldDetail]))continue;
   if(value&&(rc=VTSessionSetProperty(encoder,(__bridge CFStringRef)key,value))){fail([NSString stringWithFormat:@"Cannot preserve video metadata %@ (%d).",key,int(rc)]);return false;}
  }
  if(!shuttle_recording::prores(codec)){
   BOOL hd=dimensions.width>=1280;int bitrate=codec==shuttle_recording::Codec::H264?(hd?24000000:8000000):(hd?16000000:5000000);
   NSDictionary *options=@{(id)kVTCompressionPropertyKey_RealTime:@YES,(id)kVTCompressionPropertyKey_AllowFrameReordering:@NO,(id)kVTCompressionPropertyKey_AverageBitRate:@(bitrate),(id)kVTCompressionPropertyKey_ProfileLevel:codec==shuttle_recording::Codec::H264?(id)kVTProfileLevel_H264_High_AutoLevel:(id)kVTProfileLevel_HEVC_Main_AutoLevel};
   for(NSString *key in options)if((rc=VTSessionSetProperty(encoder,(__bridge CFStringRef)key,(__bridge CFTypeRef)options[key]))){fail([NSString stringWithFormat:@"Cannot configure %@ (%d).",@(shuttle_recording::info(codec).title),int(rc)]);return false;}
  }
  rc=VTCompressionSessionPrepareToEncodeFrames(encoder);if(rc){fail(@"Cannot prepare the selected video encoder.");return false;}configured=true;return true;
 }
 void accept(CMSampleBufferRef sample){if(failure)return;auto format=CMSampleBufferGetFormatDescription(sample);auto pixel=CMSampleBufferGetImageBuffer(sample);if(!pixel||!format){fail(@"Camera supplied an invalid frame.");return;}
  if(!configured&&!setup(format))return;
  auto size=CMVideoFormatDescriptionGetDimensions(format);auto f=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FieldCount);auto d=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FieldDetail);
  if(size.width!=dimensions.width||size.height!=dimensions.height||(f&&!fields)||(!f&&fields)||(f&&fields&&!CFEqual(f,fields))||(d&&!detail)||(!d&&detail)||(d&&detail&&!CFEqual(d,detail))){fail(@"Camera format changed. Recording stopped to protect the file.");return;}
  auto pts=CMSampleBufferGetPresentationTimeStamp(sample);auto duration=CMSampleBufferGetDuration(sample);if(!CMTIME_IS_NUMERIC(pts)||!CMTIME_IS_NUMERIC(duration)||CMTimeCompare(duration,kCMTimeZero)<=0){fail(@"Camera supplied invalid timing.");return;}
  if(!CMTIME_IS_VALID(epoch))epoch=pts;auto relative=CMTimeSubtract(pts,epoch);if(CMTimeCompare(CMTimeAdd(relative,CMTimeMake(2,1000000000)),end)<0){fail(@"Camera timestamps moved backwards.");return;}
  if(codec==shuttle_recording::Codec::Uncompressed){CMSampleBufferRef raw=nullptr;CMSampleTimingInfo timing{duration,relative,kCMTimeInvalid};OSStatus rc=CMSampleBufferCreateCopyWithNewTiming(nullptr,sample,1,&timing,&raw);if(rc||!raw){fail(@"Cannot prepare an uncompressed video frame.");return;}encoded(this,nullptr,noErr,VTEncodeInfoFlags(0),raw);CFRelease(raw);end=CMTimeAdd(relative,duration);return;}
  auto rc=VTCompressionSessionEncodeFrame(encoder,pixel,relative,duration,nullptr,nullptr,nullptr);if(rc){fail(@"Cannot encode a camera frame.");return;}
  // Complete on this worker so writer operations remain serial and memory stays bounded.
  rc=VTCompressionSessionCompleteFrames(encoder,kCMTimeInvalid);if(rc)fail(@"Cannot complete video encoding.");end=CMTimeAdd(relative,duration);
 }
 void flushAudio(bool finishing=false){if(!video||failure)return;int64_t base=CMTimeConvertScale(epoch,48000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;int64_t horizon=base+CMTimeConvertScale(end,48000,kCMTimeRoundingMethod_RoundTowardZero).value;
  while(!pending.empty()){
   auto &c=pending.front();int64_t first=CMTimeConvertScale(CMTimeMake(c.ns,1000000000),48000,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
   if(first+(int64_t)c.frames<=base){pending.pop_front();continue;}
   if(first+(int64_t)c.frames>horizon&&!finishing)break;
   int64_t skip=std::max<int64_t>(0,base-first);int64_t count=std::min<int64_t>(c.frames,horizon-first)-skip;
   if(count>0){CMBlockBufferRef block=nullptr;CMSampleBufferRef sample=nullptr;OSStatus rc=CMBlockBufferCreateWithMemoryBlock(nullptr,nullptr,count*8,nullptr,nullptr,0,count*8,0,&block);if(!rc)rc=CMBlockBufferReplaceDataBytes(c.pcm.data()+skip*2,block,0,count*8);
    CMSampleTimingInfo timing{CMTimeMake(1,48000),CMTimeMake(first+skip-base,48000),kCMTimeInvalid};size_t bytes=8;if(!rc)rc=CMSampleBufferCreateReady(nullptr,block,audioFormat,count,1,&timing,1,&bytes,&sample);if(block)CFRelease(block);
    if(rc)fail(@"Cannot prepare captured audio.");else {if(ready(audio)){if(![audio appendSampleBuffer:sample])fail(writer.error.localizedDescription);else audioFrames+=count;}CFRelease(sample);}
   }pending.pop_front();if(failure)break;
  }
 }
 bool finish(){if(encoder){VTCompressionSessionCompleteFrames(encoder,kCMTimeInvalid);VTCompressionSessionInvalidate(encoder);CFRelease(encoder);encoder=nullptr;}flushAudio(true);
  if(writer.status==AVAssetWriterStatusWriting){[video markAsFinished];[audio markAsFinished];[writer endSessionAtSourceTime:end];dispatch_semaphore_t done=dispatch_semaphore_create(0);[writer finishWritingWithCompletionHandler:^{dispatch_semaphore_signal(done);}];if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC)))fail(@"Recording finalization timed out.");if(writer.status!=AVAssetWriterStatusCompleted)fail(writer.error.localizedDescription?:@"Cannot finish recording.");}
  else { [writer cancelWriting];if(!failure)fail(@"No video frames received.");}
  if(!audioFrames&&!failure)fail(@"No audio samples received. Check the Shuttle stereo audio driver.");return !failure;
 }
 ~Recorder(){if(encoder){VTCompressionSessionInvalidate(encoder);CFRelease(encoder);}if(audioFormat)CFRelease(audioFormat);if(fields)CFRelease(fields);if(detail)CFRelease(detail);}
};
}
int main(int argc,char **argv){@autoreleasepool{
 setvbuf(stdout,nullptr,_IOLBF,0);if(argc<2){fprintf(stderr,"Usage: ShuttleRecorder output.mov [--seconds duration] [--codec key]\n");return 64;}
 double seconds=0;shuttle_recording::Codec codec=shuttle_recording::Codec::ProRes422;bool durationSeen=false,codecSeen=false;
 for(int n=2;n<argc;n+=2){if(n+1>=argc)return 64;if(!strcmp(argv[n],"--seconds")&&!durationSeen){char *end=nullptr;seconds=strtod(argv[n+1],&end);if(!end||*end||!std::isfinite(seconds)||seconds<=0)return 64;durationSeen=true;}else if(!strcmp(argv[n],"--codec")&&!codecSeen&&shuttle_recording::parse(argv[n+1],codec)){codecSeen=true;}else{fprintf(stderr,"ERROR Unknown recording option or codec.\n");return 64;}}
 signal(SIGINT,interrupt);signal(SIGTERM,interrupt);fcntl(STDIN_FILENO,F_SETFL,fcntl(STDIN_FILENO,F_GETFL)|O_NONBLOCK);
 auto dev=videoDevice();auto mic=audioDevice();if(!dev||!mic){fprintf(stderr,"ERROR Enable the Shuttle camera and stereo audio drivers first.\n");return 2;}
 AudioStreamBasicDescription asbd{};auto rc=property(mic,kAudioDevicePropertyStreamFormat,kAudioDevicePropertyScopeInput,&asbd,sizeof(asbd));if(rc||asbd.mFormatID!=kAudioFormatLinearPCM||asbd.mSampleRate!=48000||asbd.mChannelsPerFrame!=2||asbd.mBitsPerChannel!=32||!(asbd.mFormatFlags&kAudioFormatFlagIsFloat)){fprintf(stderr,"ERROR Unsupported Shuttle stereo input format.\n");return 3;}
 auto ring=std::make_unique<AudioRing>();AudioDeviceIOProcID proc=nullptr;rc=AudioDeviceCreateIOProcID(mic,AudioRing::receive,ring.get(),&proc);if(rc){fprintf(stderr,"ERROR Cannot open Shuttle audio (%d).\n",int(rc));return 4;}
 CMIOObjectPropertyAddress address{kCMIODevicePropertyStreams,kCMIODevicePropertyScopeInput,0};UInt32 size=0;rc=CMIOObjectGetPropertyDataSize(dev,&address,0,nullptr,&size);std::vector<CMIOStreamID> streams(size/4);if(!rc&&size)rc=CMIOObjectGetPropertyData(dev,&address,0,nullptr,size,&size,streams.data());CMSimpleQueueRef queue=nullptr;CMIOStreamID stream=streams.empty()?0:streams.front();if(!rc&&stream)rc=CMIOStreamCopyBufferQueue(stream,[](CMIOStreamID,void*,void*){},nullptr,&queue);
 if(rc||!queue){AudioDeviceDestroyIOProcID(mic,proc);fprintf(stderr,"ERROR Cannot open Shuttle camera.\n");return 5;}
 Recorder recorder;recorder.codec=codec;bool audioStarted=false,videoStarted=false;
 if(recorder.begin([NSURL fileURLWithPath:@(argv[1])])){rc=AudioDeviceStart(mic,proc);audioStarted=!rc;if(!rc){rc=CMIODeviceStartStream(dev,stream);videoStarted=!rc;}if(rc)recorder.fail([NSString stringWithFormat:@"Cannot start capture (%d).",int(rc)]);}
 auto started=std::chrono::steady_clock::now();bool announced=false;
 while(videoStarted&&!recorder.failure&&!interrupted){@autoreleasepool{
  char command[64];ssize_t got=read(STDIN_FILENO,command,sizeof(command));if(got>0||(!seconds&&got==0))break;
  double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count();if(seconds&&elapsed>=seconds)break;if(!announced&&elapsed>10){recorder.fail(@"No video frames received within ten seconds.");break;}
  unsigned r=ring->read.load(std::memory_order_relaxed),w=ring->write.load(std::memory_order_acquire);while(r!=w){recorder.pending.push_back(ring->chunks[r%ring->chunks.size()]);r++;}ring->read.store(r,std::memory_order_release);
  if(!recorder.frames)while(recorder.pending.size()>200)recorder.pending.pop_front();
  if(ring->overflow||ring->badFormat||recorder.pending.size()>400){recorder.fail(@"Audio capture could not keep up. The partial recording will be saved.");break;}
  auto sample=(CMSampleBufferRef)CMSimpleQueueDequeue(queue);if(sample){recorder.accept(sample);CFRelease(sample);recorder.flushAudio();if(!announced&&recorder.frames){printf("RECORDING %dx%d %s\n",recorder.dimensions.width,recorder.dimensions.height,shuttle_recording::info(codec).key);announced=true;}}else CFRunLoopRunInMode(kCFRunLoopDefaultMode,.002,true);
 }}
 if(videoStarted)CMIODeviceStopStream(dev,stream);if(audioStarted)AudioDeviceStop(mic,proc);AudioDeviceDestroyIOProcID(mic,proc);while(CMSimpleQueueGetCount(queue)){auto sample=CMSimpleQueueDequeue(queue);if(sample)CFRelease(sample);}CFRelease(queue);
 unsigned finalRead=ring->read.load(),finalWrite=ring->write.load();while(finalRead!=finalWrite){recorder.pending.push_back(ring->chunks[finalRead%ring->chunks.size()]);++finalRead;}
 bool ok=recorder.finish();printf("%s video=%llu audio=%llu seconds=%.3f\n",ok?"SAVED":"FAILED",recorder.frames,recorder.audioFrames,CMTimeGetSeconds(recorder.end));return ok?0:6;
}}
