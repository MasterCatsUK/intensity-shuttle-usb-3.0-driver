// GPL-2.0-or-later. Read-only, long-lived CMIO readiness/cache diagnostic.
// Includes the exact production timelineOutputReady() function. No host/UI is
// instantiated; this executable never launches a helper or writes audio/CMIO.
// Start this BEFORE starting ShuttlePlayback externally, with the sender idle.
// Build: xcrun clang++ -std=c++14 -fobjc-arc -Wno-deprecated-declarations \
//   -mmacosx-version-min=27.0 tools/ReadinessCacheTest.mm -framework Cocoa \
//   -framework CoreAudio -framework CoreMediaIO -framework CoreMedia \
//   -framework SystemExtensions -o /private/tmp/shuttle-readiness-cache-test
// Run: shuttle-readiness-cache-test --poll 20 [--listener] [--mode 1080p25]
#define main ProductionOutputMain
#include "../src/output/OutputHost.mm"
#undef main
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static NSString* Snapshot(void) {
    CMIOObjectPropertyAddress address{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};UInt32 bytes=0;
    OSStatus rc=CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&address,0,nullptr,&bytes);
    if(rc||bytes>1024*1024||bytes%sizeof(CMIODeviceID))return [NSString stringWithFormat:@"device-size error %d/%u",int(rc),bytes];
    std::vector<CMIODeviceID> devices(bytes/sizeof(CMIODeviceID));UInt32 used=bytes;
    rc=CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&address,0,nullptr,bytes,&used,devices.data());
    if(rc||used>bytes)return [NSString stringWithFormat:@"device-list error %d/%u",int(rc),used];
    for(unsigned n=0;n<used/sizeof(CMIODeviceID);++n){
        CMIODeviceID device=devices[n];CFStringRef uid=nullptr;UInt32 size=sizeof(uid);
        address={kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,0};
        rc=CMIOObjectGetPropertyData(device,&address,0,nullptr,size,&size,&uid);
        if(rc||!uid)continue;bool match=CFEqual(uid,CFSTR("local.shuttle.output.cmio"));CFRelease(uid);if(!match)continue;
        CMIOStreamID stream=0;size=sizeof(stream);address={kCMIODevicePropertyStreams,kCMIODevicePropertyScopeOutput,0};
        rc=CMIOObjectGetPropertyData(device,&address,0,nullptr,size,&size,&stream);
        if(rc||size!=sizeof(stream))return [NSString stringWithFormat:@"device=%u stream error=%d bytes=%u",device,int(rc),size];
        CFArrayRef formats=nullptr;size=sizeof(formats);address={kCMIOStreamPropertyFormatDescriptions,kCMIOObjectPropertyScopeGlobal,0};
        rc=CMIOObjectGetPropertyData(stream,&address,0,nullptr,size,&size,&formats);
        if(rc||!formats)return [NSString stringWithFormat:@"device=%u stream=%u formats error=%d",device,stream,int(rc)];
        NSMutableArray* names=[NSMutableArray array];for(CFIndex i=0;i<CFArrayGetCount(formats);++i){
            auto format=static_cast<CMFormatDescriptionRef>(CFArrayGetValueAtIndex(formats,i));
            CFTypeRef name=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FormatName);
            [names addObject:name?[(__bridge id)name description]:@"<unnamed>"];
        }
        CFRelease(formats);return [NSString stringWithFormat:@"device=%u stream=%u formats=%@",device,stream,names];
    }
    return @"Shuttle output absent";
}
int main(int argc,char** argv){@autoreleasepool {
    unsigned seconds=0;bool listen=false;NSInteger mode=2;
    NSArray* names=@[@"576i50",@"1080i50",@"1080p25",@"480i59.94",@"1080i59.94",@"1080p29.97"];
    for(int i=1;i<argc;++i){
        if(!strcmp(argv[i],"--listener")){listen=true;continue;}
        if(!strcmp(argv[i],"--poll")&&i+1<argc){char* end=nullptr;long value=std::strtol(argv[++i],&end,10);if(end&&!*end&&value>=1&&value<=60){seconds=unsigned(value);continue;}}
        else if(!strcmp(argv[i],"--mode")&&i+1<argc){mode=[names indexOfObject:@(argv[++i])];if(mode!=NSNotFound)continue;}
        fputs("Usage: shuttle-readiness-cache-test --poll SECONDS(1..60) [--listener] [--mode 1080p25]\n",stderr);return 64;
    }
    if(!seconds){fputs("Use --poll SECONDS, starting before the helper. Optional --listener watches hardware-device notifications.\n",stderr);return 64;}
    setvbuf(stdout,nullptr,_IOLBF,0);__block unsigned notifications=0;
    CMIOObjectPropertyAddress devices{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};
    CMIOObjectPropertyListenerBlock listener=^(UInt32,const CMIOObjectPropertyAddress*){++notifications;printf("Hardware-device listener event %u\n",notifications);};
    if(listen){OSStatus rc=CMIOObjectAddPropertyListenerBlock(kCMIOObjectSystemObject,&devices,dispatch_get_main_queue(),listener);if(rc){fprintf(stderr,"Listener registration failed: %d\n",int(rc));return 2;}}
    using Clock=std::chrono::steady_clock;auto start=Clock::now();bool absentObserved=false,readyObserved=false;NSString* last=nil;
    while(std::chrono::duration<double>(Clock::now()-start).count()<seconds){
        double elapsed=std::chrono::duration<double>(Clock::now()-start).count();
        bool ready=timelineOutputReady(mode);NSString* state=Snapshot();
        NSString* detail=[NSString stringWithFormat:@"ready=%d %@",ready,state];
        if(![detail isEqual:last]){printf("t=%.3f listener=%d %s\n",elapsed,listen,detail.UTF8String);last=detail;}
        if([state isEqual:@"Shuttle output absent"])absentObserved=true;
        if(ready){readyObserved=true;break;}
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.05,true);
    }
    if(listen)CMIOObjectRemovePropertyListenerBlock(kCMIOObjectSystemObject,&devices,dispatch_get_main_queue(),listener);
    bool ok=absentObserved&&readyObserved;
    printf("%s absent-before-ready=%d ready=%d listener=%d events=%u elapsed=%.3fs\n",ok?"PASS":"FAIL",absentObserved,readyObserved,listen,notifications,std::chrono::duration<double>(Clock::now()-start).count());
    return ok?0:1;
}}
