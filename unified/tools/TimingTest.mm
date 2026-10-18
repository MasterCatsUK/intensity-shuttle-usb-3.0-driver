// GPL-2.0-or-later. Explicit live queue-saturation timing measurement.
// Requires matching app-owned sender, with Final Cut A/V Output OFF.
// No installation, audio route change, helper or other-app control.
#define main RestartRegressionMain
#include "RestartTest.mm"
#undef main
#include <algorithm>

static uint64_t NowNS() {
    return CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()),1000000000,kCMTimeRoundingMethod_Default).value;
}
static bool Measure() {
    NativeSession session;
    if(!FindIdentity(session.identity)||!ValidateFormat(session.identity.stream,session.format))return false;
    UInt32 running=1;
    if(!ReadValue(session.identity.device,kCMIODevicePropertyDeviceIsRunningSomewhere,kCMIOObjectPropertyScopeGlobal,running)||running){
        fputs("REFUSED: output is in use or idle state could not be verified. Turn Final Cut A/V Output off first.\n",stderr);return false;
    }
    UInt32 latency=0,queueSize=0;
    ReadValue(session.identity.stream,kCMIOStreamPropertyLatency,kCMIOObjectPropertyScopeGlobal,latency);
    ReadValue(session.identity.stream,kCMIOStreamPropertyOutputBufferQueueSize,kCMIOObjectPropertyScopeGlobal,queueSize);
    CMIOStreamScheduledOutputNotificationProcAndRefCon notification{ScheduledOutput,&callbacks};
    OSStatus rc=CMIOObjectSetPropertyData(session.identity.stream,&session.notificationAddress,0,nullptr,sizeof(notification),&notification);
    if(rc)return false;session.registered=true;
    rc=CMIOStreamCopyBufferQueue(session.identity.stream,QueueChanged,&callbacks,&session.queue);
    if(rc||!session.queue)return false;
    printf("Advertised video latency %u frames; queue %u frames; native queue capacity %d\n",latency,queueSize,int(CMSimpleQueueGetCapacity(session.queue)));
    rc=CMIODeviceStartStream(session.identity.device,session.identity.stream);if(rc)return false;session.running=true;
    constexpr unsigned count=125;constexpr uint64_t base=9000000;
    std::vector<uint64_t> enqueued(count);unsigned sent=0;
    auto deadline=Clock::now()+std::chrono::seconds(12);
    const CMTime first=CMClockGetTime(CMClockGetHostTimeClock());
    // Fill whenever the queue permits, like a prerendering editor, rather than
    // pacing one enqueue per physical frame as the restart regression does.
    while(Clock::now()<deadline){
        if(sent<count&&CMSimpleQueueGetCount(session.queue)<CMSimpleQueueGetCapacity(session.queue)){
            uint64_t before=NowNS();rc=Enqueue(session.queue,session.format,base+sent,sent,first);
            if(rc){fprintf(stderr,"Enqueue error %d\n",int(rc));return false;}enqueued[sent++]=before;
        }else Pump(0.001);
        if(sent==count&&NotificationCount()>=count)break;
    }
    std::vector<double> age;uint64_t previous=0;unsigned ordered=0;
    for(auto event:NotificationsFrom(0)){
        if(event.sequence<base||event.sequence>=base+count)continue;
        uint64_t ns=CMTimeConvertScale(CMClockMakeHostTimeFromSystemUnits(event.host),1000000000,kCMTimeRoundingMethod_Default).value;
        auto index=unsigned(event.sequence-base);
        double delay=(double(ns)-double(enqueued[index]))/1e6;
        printf("Frame %u: enqueue-to-reported-presentation %.3f ms; scheduled host ns %llu\n",index,delay,(unsigned long long)ns);
        if(index!=ordered++||(previous&&ns<=previous))return false;previous=ns;
        if(index>=40&&index<100)age.push_back(delay);
    }
    bool complete=sent==count&&ordered==count;
    if(!age.empty()){
        std::sort(age.begin(),age.end());printf("Steady queued delay: min %.3f median %.3f max %.3f ms (25fps frames median %.2f)\n",age.front(),age[age.size()/2],age.back(),age[age.size()/2]/40);
    }
    printf("%s: sent %u; ordered scheduled completions %u. Blue moving block, video only; no audio route changes.\n",complete?"MEASURED":"INCOMPLETE",sent,ordered);
    return complete;
}
int main(int argc,char**argv){
    if(argc!=2||strcmp(argv[1],"--run")){puts("Usage: shuttle-timing-test --run\nRequires 1080p25 sender and Final Cut A/V Output OFF. No device access without --run.");return 64;}
    setvbuf(stdout,nullptr,_IOLBF,0);std::atomic<bool> done{false};
    std::thread watchdog([&]{auto end=Clock::now()+std::chrono::seconds(20);while(!done){if(Clock::now()>=end)std::_Exit(124);std::this_thread::sleep_for(Milliseconds(20));}});
    bool ok=false;@autoreleasepool{ok=Measure();}done=true;watchdog.join();return ok?0:1;
}
