// Offline Mercury Transmit callback and private transport qualification.
#include "ShuttleTransmit.mm"
#include <cassert>
#include <set>
static int released=0;static PrSDKPPixSuite pix{};static PrSDKTimeSuite timing{};static SPBasicSuite basic{};
static prSuiteError releasePix(PPixHand){++released;return 0;}
static prSuiteError ticks(PrTime* n){*n=254016000000LL;return 0;}
static SPErr acquireSuite(const char* name,int,const void** suite){if(!strcmp(name,kPrSDKPPixSuite))*suite=&pix;else if(!strcmp(name,kPrSDKTimeSuite))*suite=&timing;else {*suite=nullptr;return -1;}return 0;}
static SPErr releaseSuite(const char*,int){return 0;}
static SPBasicSuite* getBasic(){return &basic;}
static uint16_t privatePort(){int fd=socket(AF_INET,SOCK_STREAM,0);assert(fd>=0);auto a=shuttle_sink::endpoint(0);assert(!bind(fd,(sockaddr*)&a,sizeof(a)));socklen_t n=sizeof(a);assert(!getsockname(fd,(sockaddr*)&a,&n));uint16_t port=ntohs(a.sin_port);close(fd);return port;}
int main(){@autoreleasepool{
    // Adobe ABI loading, suite lifetimes and PPix release, including inactive/malformed frames.
    pix.Dispose=releasePix;timing.GetTicksPerSecond=ticks;basic.AcquireSuite=acquireSuite;basic.ReleaseSuite=releaseSuite;
    PlugUtilFuncs util{};util.getSPBasicSuite=getBasic;piSuites suites{};suites.utilFuncs=&util;
    tmStdParms std{};std.piSuites=&suites;tmModule module{};assert(xTransmitEntry(4,true,&suites,&module)==0);
    assert(!module.StartPlaybackClock&&!module.QueryAudioMode&&!module.PushAudio);
    tmPluginInfo info{};assert(!module.Startup(&std,&info));assert(info.outVideoAvailable&&!info.outAudioAvailable&&!info.outClockAvailable);
    tmInstance i{};assert(!module.CreateInstance(&std,&i));tmVideoMode mode{};assert(!module.QueryVideoMode(&std,&i,0,&mode));assert(mode.outLatency>0&&mode.outWidth>0);
    tmLabeledFrame frames[3]{};tmPushVideo pushInfo{};pushInfo.inFrames=frames;pushInfo.inFrameCount=3;
    assert(!module.PushVideo(&std,&i,&pushInfo));assert(released==3);
    assert(!module.DisposeInstance(&std,&i));assert(!i.ioPrivateInstanceData);assert(!module.Shutdown(&std));assert(!std.ioPrivatePluginData);
    // UYVY positive, padded, negative strides and invalid formats.
    uint8_t src[24];for(unsigned n=0;n<24;++n)src[n]=n;uint8_t dest[16]{};
    assert(shuttle_premiere::copyUYVY(dest,4,2,(char*)src,12));assert(dest[8]==12);
    assert(shuttle_premiere::copyUYVY(dest,4,2,(char*)src+12,-12));assert(dest[0]==12&&dest[8]==0);
    assert(!shuttle_premiere::copyUYVY(dest,3,2,(char*)src,12));assert(!shuttle_premiere::copyUYVY(dest,4,2,(char*)src,7));
    auto tc=shuttle_premiere::sequenceTimecode(25*2,25*3600,1,25,false);assert(tc.valid&&tc.hours==1&&tc.seconds==2&&tc.frames==0);
    tc=shuttle_premiere::sequenceTimecode(1800LL*1001,0,1001,30000,true);assert(tc.valid&&tc.minutes==1&&tc.seconds==0&&tc.frames==2);
    tc=shuttle_premiere::sequenceTimecode(17982LL*1001,0,1001,30000,true);assert(tc.minutes==10&&tc.seconds==0&&tc.frames==0);
    tc=shuttle_premiere::sequenceTimecode(3600LL*1001,0,1001,60000,true);assert(tc.minutes==1&&tc.frames==4);
    assert(!shuttle_premiere::sequenceTimecode(-1,0,1,25,false).valid);
    assert(!shuttle_premiere::sequenceTimecode(0,0,1,27,false).valid);
    // Stall physical completions after draining every software queue: never >6 in flight.
    auto port=privatePort();shuttle_sink::Reader receiver(2,true,port);Transport transport(port);
    auto profile=shuttle_output::profile(shuttle_output::Mode::HD1080p25);std::vector<uint8_t> image;
    unsigned received=0;std::deque<uint64_t> pending;
    auto until=std::chrono::steady_clock::now()+std::chrono::seconds(3);
    while(std::chrono::steady_clock::now()<until){
        Video v;v.mode=2;v.tc={1,1,2,3,4,0,25,0};v.pixels.assign(size_t(profile.width)*profile.height*2,uint8_t(received));transport.submit(17,std::move(v));
        receiver.read(image,profile.width,profile.height);if(receiver.acknowledge){++received;pending.push_back(receiver.sequence);assert(receiver.timecode.hours==1);}
        if(received==6)break;std::this_thread::sleep_for(std::chrono::milliseconds(3));
    }
    assert(received==6);
    for(unsigned n=0;n<30;++n){Video v;v.pixels.assign(size_t(profile.width)*profile.height*2,42);transport.submit(17,std::move(v));receiver.read(image,profile.width,profile.height);assert(!receiver.acknowledge);std::this_thread::sleep_for(std::chrono::milliseconds(2));}
    receiver.played(pending.front(),123,receiver.generation);
    until=std::chrono::steady_clock::now()+std::chrono::seconds(1);bool resumed=false;
    while(std::chrono::steady_clock::now()<until){receiver.read(image,profile.width,profile.height);if(receiver.acknowledge){resumed=true;break;}std::this_thread::sleep_for(std::chrono::milliseconds(2));}
    assert(resumed);
    transport.deactivate(17);
    puts("PASS: SDK callbacks and exact PPix release, Premiere-owned clock, padded/negative UYVY stride, sequence/drop-frame TC, six outstanding physical frames, stalled output and completion recovery; private loopback only");
}}
