// GPL-2.0-or-later. Input meters and optional local listening; no device level/route writes.
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include "MonitorAudio.hpp"
#include <memory>
@interface CaptureMeters : NSView
@property float leftDB,rightDB;
@end
@implementation CaptureMeters
- (instancetype)initWithFrame:(NSRect)frame{if((self=[super initWithFrame:frame])){_leftDB=_rightDB=-60;self.accessibilityLabel=@"Input audio meters, left and right";}return self;}
- (void)drawRect:(NSRect)rect {
 [NSColor.windowBackgroundColor setFill];NSRectFill(self.bounds);
 NSDictionary *style=@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular],NSForegroundColorAttributeName:NSColor.secondaryLabelColor};
 CGFloat height=self.bounds.size.height-26;
 for(int ch=0;ch<2;ch++){
  CGFloat x=ch*24+2;[NSColor.controlBackgroundColor setFill];NSRectFill(NSMakeRect(x,20,16,height));float value=ch?self.rightDB:self.leftDB;
  for(int n=0;n<30;n++){float threshold=-60+n*2;NSColor *c=threshold>=-6?NSColor.systemRedColor:threshold>=-18?NSColor.systemYellowColor:NSColor.systemGreenColor;[(value>threshold?c:[c blendedColorWithFraction:.88 ofColor:NSColor.windowBackgroundColor]) setFill];NSRectFill(NSMakeRect(x,20+n*height/30,16,height/30-1));}
  [(ch?@"R":@"L") drawAtPoint:NSMakePoint(x+4,4) withAttributes:style];
 }
 for(NSNumber *level in @[@0,@(-12),@(-24),@(-48)]){CGFloat y=20+(level.floatValue+60)/60*height-5;[level.stringValue drawAtPoint:NSMakePoint(50,y) withAttributes:style];}
}
@end
static AudioDeviceID monitorInputDevice(){AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,0};UInt32 size=0;if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&size))return 0;std::vector<AudioDeviceID> devices(size/sizeof(AudioDeviceID));if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&size,devices.data()))return 0;for(auto d:devices){CFStringRef uid=nullptr;UInt32 bytes=sizeof(uid);a={kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,0};if(!AudioObjectGetPropertyData(d,&a,0,nullptr,&bytes,&uid)){bool yes=uid&&CFEqual(uid,CFSTR("local.shuttle.audio.stereo"));if(uid)CFRelease(uid);if(yes)return d;}}return 0;}
static AudioDeviceID monitorDefaultDevice(CFStringRef *uid){AudioDeviceID device=0;UInt32 size=sizeof(device);AudioObjectPropertyAddress a{kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,0};if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&size,&device))return 0;a={kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,0};size=sizeof(*uid);if(AudioObjectGetPropertyData(device,&a,0,nullptr,&size,uid))return 0;return device;}
static OSStatus monitorReceive(AudioDeviceID,const AudioTimeStamp*,const AudioBufferList *data,const AudioTimeStamp*,AudioBufferList*,const AudioTimeStamp*,void *context){auto &ring=*(shuttle_monitor::StereoRing*)context;if(data->mNumberBuffers==1&&data->mBuffers[0].mNumberChannels==2&&data->mBuffers[0].mData)ring.push((const float*)data->mBuffers[0].mData,nullptr,data->mBuffers[0].mDataByteSize/8,true);else if(data->mNumberBuffers==2&&data->mBuffers[0].mNumberChannels==1&&data->mBuffers[1].mNumberChannels==1&&data->mBuffers[0].mData&&data->mBuffers[1].mData&&data->mBuffers[0].mDataByteSize==data->mBuffers[1].mDataByteSize)ring.push((const float*)data->mBuffers[0].mData,(const float*)data->mBuffers[1].mData,data->mBuffers[0].mDataByteSize/4,false);return noErr;}
static void monitorRender(void *context,AudioQueueRef queue,AudioQueueBufferRef buffer){auto &ring=*(shuttle_monitor::StereoRing*)context;ring.render((float*)buffer->mAudioData,buffer->mAudioDataBytesCapacity/8);buffer->mAudioDataByteSize=buffer->mAudioDataBytesCapacity;AudioQueueEnqueueBuffer(queue,buffer,0,nullptr);}
@interface CaptureAudioMonitor : NSObject {
 std::unique_ptr<shuttle_monitor::StereoRing> _ring;AudioDeviceID _device,_outputDevice;AudioDeviceIOProcID _proc;AudioQueueRef _output;
}
@property CaptureMeters *meters;
@property NSButton *listen;
@property NSSlider *volume;
@property NSTextField *status;
@property NSTimer *timer;
@property BOOL active,permissionPending;
- (void)start;
- (void)stop;
- (void)stopListening;
@end
@implementation CaptureAudioMonitor
- (instancetype)init {if((self=[super init])){
 _ring.reset(new shuttle_monitor::StereoRing);
 self.meters=[[CaptureMeters alloc] initWithFrame:NSMakeRect(566,286,72,200)];
 self.listen=[NSButton checkboxWithTitle:@"Monitor audio" target:self action:@selector(listenChanged:)];self.listen.frame=NSMakeRect(24,254,150,28);self.listen.toolTip=@"Listen through the current Mac sound output. This does not change recording levels.";
 self.volume=[NSSlider sliderWithValue:[NSUserDefaults.standardUserDefaults objectForKey:@"MonitorVolume"]?[NSUserDefaults.standardUserDefaults doubleForKey:@"MonitorVolume"]:.5 minValue:0 maxValue:1 target:self action:@selector(volumeChanged:)];self.volume.frame=NSMakeRect(178,255,154,26);self.volume.accessibilityLabel=@"Listening volume";self.volume.toolTip=@"Listening volume only. The input and recorded sound stay unchanged.";_ring->gain.store(self.volume.floatValue);
 self.status=[NSTextField labelWithString:@"Input levels"];self.status.frame=NSMakeRect(342,258,146,20);self.status.font=[NSFont systemFontOfSize:11];self.status.textColor=NSColor.secondaryLabelColor;self.status.lineBreakMode=NSLineBreakByTruncatingTail;
 }return self;}
- (void)start {
 self.active=YES;if(_proc||self.permissionPending)return;
 auto auth=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
 if(auth==AVAuthorizationStatusNotDetermined){self.permissionPending=YES;self.status.stringValue=@"Allow Microphone for meters";__weak CaptureAudioMonitor *weak=self;[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL allowed){dispatch_async(dispatch_get_main_queue(),^{auto strong=weak;if(!strong)return;strong.permissionPending=NO;if(strong.active)[strong start];});}];return;}
 if(auth!=AVAuthorizationStatusAuthorized){self.status.stringValue=@"Allow Microphone in Privacy";return;}
 _device=monitorInputDevice();if(!_device){self.status.stringValue=@"Stereo input unavailable";return;}
 AudioObjectPropertyAddress a{kAudioDevicePropertyStreamFormat,kAudioDevicePropertyScopeInput,0};AudioStreamBasicDescription format{};UInt32 size=sizeof(format);OSStatus rc=AudioObjectGetPropertyData(_device,&a,0,nullptr,&size,&format);
 if(rc||format.mFormatID!=kAudioFormatLinearPCM||format.mSampleRate!=48000||format.mChannelsPerFrame!=2||format.mBitsPerChannel!=32||!(format.mFormatFlags&kAudioFormatFlagIsFloat)){self.status.stringValue=@"Unsupported input audio";return;}
 rc=AudioDeviceCreateIOProcID(_device,monitorReceive,_ring.get(),&_proc);if(!rc)rc=AudioDeviceStart(_device,_proc);
 if(rc){if(_proc)AudioDeviceDestroyIOProcID(_device,_proc);_proc=nullptr;self.status.stringValue=@"Audio meters unavailable";return;}
 self.status.stringValue=@"Input levels";__weak CaptureAudioMonitor *weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:.05 repeats:YES block:^(NSTimer*){[weak update];}];if(self.listen.state==NSControlStateValueOn)[self startListening];
}
- (void)startListening {
 if(_output||!_proc)return;
 CFStringRef uid=nullptr;_outputDevice=monitorDefaultDevice(&uid);
 if(!uid||CFEqual(uid,CFSTR("local.shuttle.audio.hdmi"))){if(uid)CFRelease(uid);self.status.stringValue=@"Choose Mac speakers in Sound";self.listen.state=NSControlStateValueOff;return;}
 AudioStreamBasicDescription f{};f.mSampleRate=48000;f.mFormatID=kAudioFormatLinearPCM;f.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;f.mBytesPerPacket=f.mBytesPerFrame=8;f.mFramesPerPacket=1;f.mChannelsPerFrame=2;f.mBitsPerChannel=32;
 OSStatus rc=AudioQueueNewOutput(&f,monitorRender,_ring.get(),nullptr,nullptr,0,&_output);
 if(!rc)rc=AudioQueueSetProperty(_output,kAudioQueueProperty_CurrentDevice,&uid,sizeof(uid));CFRelease(uid);
 if(!rc){_ring->read.store(_ring->write.load());_ring->listening=true;for(int n=0;n<3&&!rc;n++){AudioQueueBufferRef b=nullptr;rc=AudioQueueAllocateBuffer(_output,512*8,&b);if(!rc)monitorRender(_ring.get(),_output,b);}if(!rc)rc=AudioQueueStart(_output,nullptr);}
 if(rc){[self stopListening];self.listen.state=NSControlStateValueOff;self.status.stringValue=@"Listening output unavailable";}else self.status.stringValue=@"Listening · local output";
}
- (void)stopListening {_ring->listening=false;if(_output){AudioQueueStop(_output,true);AudioQueueDispose(_output,true);_output=nullptr;}_outputDevice=0;}
- (void)listenChanged:(id)sender{if(self.listen.state==NSControlStateValueOn){[self start];[self startListening];}else{[self stopListening];self.status.stringValue=@"Input levels";}}
- (void)volumeChanged:(id)sender{_ring->gain.store(self.volume.floatValue);[NSUserDefaults.standardUserDefaults setDouble:self.volume.doubleValue forKey:@"MonitorVolume"];}
- (void)update {self.meters.leftDB=std::max(shuttle_monitor::db(_ring->left.exchange(0)),self.meters.leftDB-1.0f);self.meters.rightDB=std::max(shuttle_monitor::db(_ring->right.exchange(0)),self.meters.rightDB-1.0f);self.meters.needsDisplay=YES;
 if(_output){CFStringRef uid=nullptr;auto device=monitorDefaultDevice(&uid);if(uid)CFRelease(uid);if(device!=_outputDevice){[self stopListening];[self startListening];}}
}
- (void)stop {self.active=NO;[self.timer invalidate];self.timer=nil;[self stopListening];if(_proc){AudioDeviceStop(_device,_proc);AudioDeviceDestroyIOProcID(_device,_proc);_proc=nullptr;}_ring->left=0;_ring->right=0;_ring->read=_ring->write.load();self.meters.leftDB=self.meters.rightDB=-60;self.meters.needsDisplay=YES;self.status.stringValue=@"Input levels";}
- (void)dealloc {[self stop];}
@end
