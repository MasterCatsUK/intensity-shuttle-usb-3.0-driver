// GPL-2.0-or-later. Native CMIO sink stop/restart lifecycle regression.
// LIVE test: requires an already-running ShuttlePlayback --sink 1080p25 live.
// Reuses the SAME cached device, stream and buffer queue through every cycle.
// Never launches helpers, touches Core Audio, controls user apps or installs.
// Build: xcrun clang++ -std=c++14 -fobjc-arc -Wno-deprecated-declarations \
//   -mmacosx-version-min=27.0 tools/RestartTest.mm -framework Foundation \
//   -framework CoreMediaIO -framework CoreMedia -framework CoreVideo \
//   -o /private/tmp/shuttle-restart-test
// Run explicitly, only with other A/V clients stopped:
//   /private/tmp/shuttle-restart-test --run 1080p25 [cycles=5]
// No arguments/--help do not enumerate or change devices.
#import <Foundation/Foundation.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMediaIO/CMIOSampleBuffer.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

using Clock=std::chrono::steady_clock;
using Milliseconds=std::chrono::milliseconds;
static const CFStringRef TargetUID=CFSTR("local.shuttle.output.cmio");
struct Notification {uint64_t sequence,host;};
struct CallbackState {
    std::mutex mutex;std::vector<Notification> notifications;
    std::atomic<unsigned> queueChanges{0},deviceChanges{0};
};
// Static storage keeps the callback refcon valid even during process teardown.
static CallbackState callbacks;
static void ScheduledOutput(UInt64 sequence,UInt64 host,void* context) {
    auto* state=static_cast<CallbackState*>(context);
    std::lock_guard<std::mutex> lock(state->mutex);
    state->notifications.push_back({sequence,host});
}
static void QueueChanged(CMIOStreamID,void*,void* context) {
    static_cast<CallbackState*>(context)->queueChanges.fetch_add(1);
}
static std::vector<Notification> NotificationsFrom(size_t offset) {
    std::lock_guard<std::mutex> lock(callbacks.mutex);
    return std::vector<Notification>(callbacks.notifications.begin()+offset,callbacks.notifications.end());
}
static size_t NotificationCount() {
    std::lock_guard<std::mutex> lock(callbacks.mutex);return callbacks.notifications.size();
}
static bool ReadBytes(CMIOObjectID object,CMIOObjectPropertySelector selector,
    CMIOObjectPropertyScope scope,std::vector<uint8_t>& bytes,bool quiet=false) {
    CMIOObjectPropertyAddress address{selector,scope,kCMIOObjectPropertyElementMain};UInt32 size=0;
    OSStatus rc=CMIOObjectGetPropertyDataSize(object,&address,0,nullptr,&size);
    if(rc||size>1024*1024){if(!quiet)fprintf(stderr,"FAIL property %08x size: %d (%u bytes)\n",unsigned(selector),int(rc),size);return false;}
    bytes.resize(size);UInt32 used=size;
    rc=CMIOObjectGetPropertyData(object,&address,0,nullptr,size,&used,bytes.data());
    if(rc||used>size){if(!quiet)fprintf(stderr,"FAIL property %08x read: %d (%u/%u bytes)\n",unsigned(selector),int(rc),used,size);return false;}
    bytes.resize(used);return true;
}
template<class T> static bool ReadValue(CMIOObjectID object,CMIOObjectPropertySelector selector,
    CMIOObjectPropertyScope scope,T& value,bool quiet=false) {
    std::vector<uint8_t> bytes;if(!ReadBytes(object,selector,scope,bytes,quiet)||bytes.size()!=sizeof(T))return false;
    std::memcpy(&value,bytes.data(),sizeof(value));return true;
}
struct Identity {CMIODeviceID device=0;CMIOStreamID stream=0;};
static bool FindIdentity(Identity& result,bool quiet=false) {
    result={};std::vector<uint8_t> devices;
    if(!ReadBytes(kCMIOObjectSystemObject,kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,devices,quiet)||devices.size()%sizeof(CMIODeviceID))return false;
    unsigned matches=0;
    for(size_t offset=0;offset<devices.size();offset+=sizeof(CMIODeviceID)){
        CMIODeviceID candidate=0;std::memcpy(&candidate,devices.data()+offset,sizeof(candidate));CFStringRef uid=nullptr;
        if(!ReadValue(candidate,kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,uid,true)||!uid)continue;
        bool match=CFEqual(uid,TargetUID);CFRelease(uid);if(!match)continue;
        ++matches;result.device=candidate;std::vector<uint8_t> streams;
        if(!ReadBytes(candidate,kCMIODevicePropertyStreams,kCMIODevicePropertyScopeOutput,streams,quiet)||streams.size()!=sizeof(CMIOStreamID))return false;
        std::memcpy(&result.stream,streams.data(),sizeof(result.stream));
    }
    return matches==1&&result.device&&result.stream;
}
static bool CheckIdentity(const Identity& cached,const char* phase,unsigned cycle) {
    Identity current;bool present=FindIdentity(current,true);
    if(!present||cached.device!=current.device||cached.stream!=current.stream){
        fprintf(stderr,"FAIL cycle %u %s: cached device/stream %u/%u; current %u/%u; present=%d; system device-change events=%u\n",
            cycle,phase,cached.device,cached.stream,current.device,current.stream,present,callbacks.deviceChanges.load());return false;
    }
    return true;
}
static void Pump(double seconds=0.002) {CFRunLoopRunInMode(kCFRunLoopDefaultMode,seconds,true);}
static bool ObserveStable(const Identity& cached,unsigned cycle,const char* phase,Milliseconds duration) {
    auto deadline=Clock::now()+duration;
    do{if(!CheckIdentity(cached,phase,cycle))return false;Pump(0.01);}while(Clock::now()<deadline);
    return true;
}
static bool ValidateFormat(CMIOStreamID stream,CMVideoFormatDescriptionRef& format) {
    CFArrayRef formats=nullptr;
    if(!ReadValue(stream,kCMIOStreamPropertyFormatDescriptions,kCMIOObjectPropertyScopeGlobal,formats)||!formats)return false;
    bool ok=CFArrayGetCount(formats)==1;
    if(ok){
        auto candidate=static_cast<CMVideoFormatDescriptionRef>(CFArrayGetValueAtIndex(formats,0));
        CFTypeRef name=CMFormatDescriptionGetExtension(candidate,kCMFormatDescriptionExtension_FormatName);
        auto size=CMVideoFormatDescriptionGetDimensions(candidate);
        ok=name&&CFGetTypeID(name)==CFStringGetTypeID()&&CFEqual(name,CFSTR("1080p25"))&&
            size.width==1920&&size.height==1080&&CMFormatDescriptionGetMediaSubType(candidate)==kCVPixelFormatType_422YpCbCr8;
        if(ok)format=(CMVideoFormatDescriptionRef)CFRetain(candidate);
    }
    CFRelease(formats);Float64 rate=0;
    ok=ok&&ReadValue(stream,kCMIOStreamPropertyFrameRate,kCMIOObjectPropertyScopeGlobal,rate)&&std::isfinite(rate)&&std::fabs(rate-25)<0.0001;
    if(!ok)fputs("FAIL: sender must publish exactly one 1920x1080 UYVY 1080p25 format at 25fps\n",stderr);
    return ok;
}
static OSStatus Enqueue(CMSimpleQueueRef queue,CMVideoFormatDescriptionRef format,uint64_t sequence,unsigned frame,CMTime first) {
    CVPixelBufferRef image=nullptr;
    OSStatus rc=CVPixelBufferCreate(kCFAllocatorDefault,1920,1080,kCVPixelFormatType_422YpCbCr8,
        (__bridge CFDictionaryRef)@{(__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey:@{}},&image);
    if(rc||!image)return rc?rc:-1;
    CVPixelBufferLockBaseAddress(image,0);unsigned left=(frame*24)%1760;
    for(unsigned y=0;y<1080;++y){auto* row=static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(image))+y*CVPixelBufferGetBytesPerRow(image);
        for(unsigned x=0;x<1920;x+=2){bool block=y>=400&&y<500&&x>=left&&x<left+160;
            row[2*x]=block?128:240;row[2*x+1]=block?235:41;row[2*x+2]=block?128:110;row[2*x+3]=block?235:41;}}
    CVPixelBufferUnlockBaseAddress(image,0);CVBufferSetAttachments(image,CMFormatDescriptionGetExtensions(format),kCVAttachmentMode_ShouldPropagate);
    CMVideoFormatDescriptionRef sampleFormat=nullptr;rc=CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,image,&sampleFormat);
    CMSampleBufferRef sample=nullptr;CMSampleTimingInfo timing{CMTimeMake(1,25),CMTimeAdd(first,CMTimeMake(frame,25)),kCMTimeInvalid};
    if(!rc)rc=CMIOSampleBufferCreateForImageBuffer(kCFAllocatorDefault,image,sampleFormat,&timing,sequence,0,&sample);
    if(sampleFormat)CFRelease(sampleFormat);CFRelease(image);if(rc)return rc;
    rc=CMSimpleQueueEnqueue(queue,sample);if(rc)CFRelease(sample);return rc;
}
static void DrainQueue(CMSimpleQueueRef queue) {
    while(CMSimpleQueueGetCount(queue)){auto sample=CMSimpleQueueDequeue(queue);if(sample)CFRelease(sample);}
}
struct NativeSession {
    Identity identity;CMSimpleQueueRef queue=nullptr;CMVideoFormatDescriptionRef format=nullptr;
    bool running=false,registered=false,listening=false;
    CMIOObjectPropertyListenerBlock listener=nil;
    CMIOObjectPropertyAddress notificationAddress{kCMIOStreamPropertyScheduledOutputNotificationProc,kCMIOObjectPropertyScopeGlobal,0};
    CMIOObjectPropertyAddress devicesAddress{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};
    ~NativeSession(){
        if(running){OSStatus rc=CMIODeviceStopStream(identity.device,identity.stream);printf("Cleanup StopStream status %d\n",int(rc));}
        if(registered){CMIOStreamScheduledOutputNotificationProcAndRefCon clear{nullptr,nullptr};
            OSStatus rc=CMIOObjectSetPropertyData(identity.stream,&notificationAddress,0,nullptr,sizeof(clear),&clear);
            printf("Cleanup scheduled callback status %d\n",int(rc));}
        if(listening)CMIOObjectRemovePropertyListenerBlock(kCMIOObjectSystemObject,&devicesAddress,dispatch_get_main_queue(),listener);
        if(queue){DrainQueue(queue);CFRelease(queue);}if(format)CFRelease(format);
    }
};
static bool Run(unsigned cycles) {
    NativeSession session;auto& cached=session.identity;auto initialDeadline=Clock::now()+std::chrono::seconds(4);
    while(!FindIdentity(cached,true)&&Clock::now()<initialDeadline)Pump(0.02);
    if(!cached.device||!cached.stream){fputs("FAIL: ready Shuttle output was not found within four seconds; start the matching sender first\n",stderr);return false;}
    if(!ValidateFormat(cached.stream,session.format))return false;
    printf("Cached device %u; stream %u; cycles %u; 1080p25. No audio route changes.\n",cached.device,cached.stream,cycles);
    session.listener=^(UInt32,const CMIOObjectPropertyAddress*){callbacks.deviceChanges.fetch_add(1);};
    OSStatus rc=CMIOObjectAddPropertyListenerBlock(kCMIOObjectSystemObject,&session.devicesAddress,dispatch_get_main_queue(),session.listener);
    if(rc){fprintf(stderr,"FAIL register device-list listener: %d\n",int(rc));return false;}session.listening=true;
    CMIOStreamScheduledOutputNotificationProcAndRefCon notification{ScheduledOutput,&callbacks};
    rc=CMIOObjectSetPropertyData(cached.stream,&session.notificationAddress,0,nullptr,sizeof(notification),&notification);
    if(rc){fprintf(stderr,"FAIL register scheduled-output callback: %d\n",int(rc));return false;}session.registered=true;
    rc=CMIOStreamCopyBufferQueue(cached.stream,QueueChanged,&callbacks,&session.queue);
    if(rc||!session.queue){fprintf(stderr,"FAIL CopyBufferQueue: %d\n",int(rc));return false;}
    printf("Cached buffer queue %p; capacity %d. It will not be copied again.\n",session.queue,int(CMSimpleQueueGetCapacity(session.queue)));
    if(CMSimpleQueueGetCapacity(session.queue)<2){fputs("FAIL output queue must support the two-frame startup preroll\n",stderr);return false;}
    for(unsigned cycle=1;cycle<=cycles;++cycle){
        if(!CheckIdentity(cached,"before start",cycle))return false;DrainQueue(session.queue);
        const size_t notificationOffset=NotificationCount();const uint64_t base=uint64_t(cycle)*1000000;
        auto startCall=Clock::now();rc=CMIODeviceStartStream(cached.device,cached.stream);
        double startMs=std::chrono::duration<double,std::milli>(Clock::now()-startCall).count();
        printf("Cycle %u StartStream status %d (%.1f ms); same IDs %u/%u, queue %p\n",cycle,int(rc),startMs,cached.device,cached.stream,session.queue);
        if(rc)return false;session.running=true;
        if(!CheckIdentity(cached,"after start",cycle))return false;
        const CMTime first=CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),CMTimeMake(1,10));
        for(unsigned frame=0;frame<2;++frame){rc=Enqueue(session.queue,session.format,base+frame,frame,first);if(rc){fprintf(stderr,"FAIL cycle %u enqueue preroll: %d\n",cycle,int(rc));return false;}}
        // Only two startup frames exist at this point. An acknowledgement in
        // this range proves this restart has physically presented initial
        // output, rather than accepting a late notification from an old run.
        auto firstAckDeadline=Clock::now()+std::chrono::seconds(2);bool firstAck=false;Notification firstNotification{};
        while(Clock::now()<firstAckDeadline&&!firstAck){
            if(!CheckIdentity(cached,"waiting for first restarted output",cycle))return false;
            for(auto item:NotificationsFrom(notificationOffset))if(item.sequence>=base&&item.sequence<base+2&&item.host){firstAck=true;firstNotification=item;break;}
            if(!firstAck)Pump(0.005);
        }
        if(!firstAck){fprintf(stderr,"FAIL cycle %u: no scheduled-output notification for either initial preroll frame within two seconds; callback notifications since start=%zu\n",cycle,NotificationsFrom(notificationOffset).size());return false;}
        printf("Cycle %u first restarted output: sequence %llu; output host ticks %llu\n",cycle,(unsigned long long)firstNotification.sequence,(unsigned long long)firstNotification.host);
        // Continue for one second after initial proof, still through the same
        // queue. Shift PTS after preroll delay to avoid testing stale playback.
        const CMTime continuation=CMClockGetTime(CMClockGetHostTimeClock());unsigned frame=2;
        auto feedStart=Clock::now();auto feedDeadline=feedStart+std::chrono::seconds(2);constexpr unsigned frames=27;
        while(frame<frames&&Clock::now()<feedDeadline){
            if(!CheckIdentity(cached,"playing",cycle))return false;
            double elapsed=std::chrono::duration<double>(Clock::now()-feedStart).count();
            if(CMSimpleQueueGetCount(session.queue)<CMSimpleQueueGetCapacity(session.queue)&&double(frame-2)/25<=elapsed){
                rc=Enqueue(session.queue,session.format,base+frame,frame,CMTimeSubtract(continuation,CMTimeMake(2,25)));
                if(rc){fprintf(stderr,"FAIL cycle %u enqueue frame %u: %d\n",cycle,frame,int(rc));return false;}++frame;
            }else Pump(0.002);
        }
        if(frame!=frames){fprintf(stderr,"FAIL cycle %u queue stopped draining; sent %u/%u\n",cycle,frame,frames);return false;}
        if(!ObserveStable(cached,cycle,"final output drain",Milliseconds(350)))return false;
        unsigned acknowledged=0;uint64_t last=0,lastHost=0;
        for(auto item:NotificationsFrom(notificationOffset))if(item.sequence>=base&&item.sequence<base+frames){
            if(item.host==0){fputs("FAIL scheduled-output host time was zero\n",stderr);return false;}
            if(lastHost&&item.host<lastHost){fprintf(stderr,"FAIL cycle %u scheduled output host time went backwards\n",cycle);return false;}
            ++acknowledged;last=item.sequence;lastHost=item.host;
        }
        printf("Cycle %u: enqueued %u; current-cycle scheduled callbacks %u; last sequence %llu; queue notifications %u\n",cycle,frame,acknowledged,(unsigned long long)last,callbacks.queueChanges.load());
        if(acknowledged<2||last<base+frames-3){fprintf(stderr,"FAIL cycle %u output notifications did not progress through the restarted frames\n",cycle);return false;}
        rc=CMIODeviceStopStream(cached.device,cached.stream);session.running=false;
        printf("Cycle %u StopStream status %d; observing idle identity for 500ms\n",cycle,int(rc));if(rc)return false;
        DrainQueue(session.queue);
        if(!ObserveStable(cached,cycle,"stopped/reconnecting",Milliseconds(500)))return false;
    }
    printf("PASS: %u stop/start cycles reused device %u, stream %u and queue %p; every restart presented initial frames and progressed; device-list change events %u.\n",
        cycles,cached.device,cached.stream,session.queue,callbacks.deviceChanges.load());return true;
}
int main(int argc,char** argv) {
    if(argc<3||strcmp(argv[1],"--run")||strcmp(argv[2],"1080p25")||argc>4){
        fputs("Usage: shuttle-restart-test --run 1080p25 [cycles=5]\nRequires an already-running matching sender; close other A/V clients first.\nNo device access occurs without --run.\n",stderr);return argc==2&&!strcmp(argv[1],"--help")?0:64;
    }
    char* end=nullptr;long requested=argc==4?std::strtol(argv[3],&end,10):5;
    if(requested<1||requested>10||(argc==4&&(!end||*end))){fputs("cycles must be an integer from 1 to 10\n",stderr);return 64;}
    setvbuf(stdout,nullptr,_IOLBF,0);std::atomic<bool> done{false};
    // Also bounds a synchronous DAL call that unexpectedly hangs. Process
    // death releases this test's own client; it never force-quits another app.
    std::thread watchdog([&]{auto deadline=Clock::now()+std::chrono::seconds(60);
        while(!done.load()){if(Clock::now()>=deadline){fputs("FAIL global 60-second CMIO watchdog expired\n",stderr);std::_Exit(124);}std::this_thread::sleep_for(Milliseconds(10));}});
    bool ok=false;@autoreleasepool {ok=Run(unsigned(requested));}
    done=true;watchdog.join();return ok?0:1;
}
