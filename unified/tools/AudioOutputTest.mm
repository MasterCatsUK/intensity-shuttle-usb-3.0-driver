// GPL-2.0-or-later. Explicit-device audio output diagnostic; no default-device changes.
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#include <vector>
#include <atomic>
#include <cmath>
#include <unistd.h>
struct Tone {uint64_t frames=0;std::atomic<uint64_t> count{0};};
static OSStatus render(AudioDeviceID,const AudioTimeStamp*,const AudioBufferList*,const AudioTimeStamp*,AudioBufferList* output,const AudioTimeStamp*,void* user){auto& tone=*static_cast<Tone*>(user);unsigned frames=0;for(unsigned b=0;b<output->mNumberBuffers;++b){auto& buffer=output->mBuffers[b];unsigned channels=buffer.mNumberChannels;if(!channels||!buffer.mData)continue;unsigned count=buffer.mDataByteSize/(4*channels);auto* samples=static_cast<float*>(buffer.mData);for(unsigned n=0;n<count;++n){float x=0.1f*std::sin(2*3.141592653589793*1000*(tone.frames+n)/48000.0);for(unsigned c=0;c<channels;++c)samples[n*channels+c]=x;}frames=count;}tone.frames+=frames;tone.count.fetch_add(frames);return noErr;}
int main(int argc,char** argv){@autoreleasepool{AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,0};UInt32 bytes=0;AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&bytes);std::vector<AudioDeviceID> devices(bytes/4);AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&bytes,devices.data());AudioDeviceID target=0;
    for(auto d:devices){CFStringRef uid=nullptr;UInt32 n=sizeof(uid);a={kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,0};if(AudioObjectGetPropertyData(d,&a,0,nullptr,&n,&uid)||!uid)continue;NSString* value=CFBridgingRelease(uid);if([value hasPrefix:@"local.shuttle.audio"]){printf("Audio device %u: %s\n",d,value.UTF8String);if([value isEqual:@"local.shuttle.audio.hdmi"])target=d;}}
    for(auto selector:{kAudioHardwarePropertyDefaultOutputDevice,kAudioHardwarePropertyDefaultSystemOutputDevice}){AudioDeviceID d=0;UInt32 n=sizeof(d);a={selector,kAudioObjectPropertyScopeGlobal,0};OSStatus rc=AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&n,&d);CFStringRef uid=nullptr;n=sizeof(uid);a={kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,0};if(!rc)rc=AudioObjectGetPropertyData(d,&a,0,nullptr,&n,&uid);printf("Default audio %08x: device %u; status %d; UID %s\n",selector,d,int(rc),uid?[(__bridge NSString*)uid UTF8String]:"(none)");if(uid)CFRelease(uid);}
    if(target){UInt32 running=0,n=sizeof(running);a={kAudioDevicePropertyDeviceIsRunningSomewhere,kAudioObjectPropertyScopeGlobal,0};OSStatus status=AudioObjectGetPropertyData(target,&a,0,nullptr,&n,&running);printf("HDMI audio running: %u (status %d)\n",running,int(status));}
    if(argc==1||!strcmp(argv[1],"--list"))return target?0:2;
    if(!target)return 2;unsigned seconds=unsigned(atoi(argv[1]));if(!seconds||seconds>60)return 64;
    Tone tone;AudioDeviceIOProcID proc=nullptr;OSStatus rc=AudioDeviceCreateIOProcID(target,render,&tone,&proc);if(rc){printf("Create output callback: %d\n",int(rc));return 3;}
    rc=AudioDeviceStart(target,proc);if(!rc){sleep(seconds);AudioDeviceStop(target,proc);}AudioDeviceDestroyIOProcID(target,proc);printf("Output status %d; rendered %llu stereo frames\n",int(rc),(unsigned long long)tone.count.load());return rc||tone.count<seconds*40000?4:0;
}}
