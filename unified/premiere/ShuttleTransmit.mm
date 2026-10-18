// GPL-2.0-or-later. Original Mercury Transmit adapter; Adobe SDK headers required.
#include "PrSDKTransmit.h"
#include "PrSDKPPixSuite.h"
#include "PrSDKSequenceInfoSuite.h"
#include "SPBasic.h"
#import <Foundation/Foundation.h>
#include "../src/output/SharedOutput.hpp"
#include "../src/output/OutputPacket.hpp"
#include "FrameTools.hpp"
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <atomic>
#include <algorithm>
#include <chrono>
#include <cstdio>
namespace {
void logMessage(const char* message){NSLog(@"Shuttle Premiere: %s",message);}
unsigned savedMode(){CFPropertyListRef v=CFPreferencesCopyAppValue(CFSTR("OutputMode"),CFSTR("local.shuttle.camera"));int n=2;if(v){if(CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)v,kCFNumberIntType,&n);CFRelease(v);}return n>=0&&n<6?unsigned(n):2;}
struct Video {unsigned mode=2;uint64_t generation=0;shuttle_sink::Timecode tc;std::vector<uint8_t> pixels;};
// One transport for all Adobe player instances. The latest active monitor owns it.
class Transport {
    std::mutex mutex;std::condition_variable changed;std::deque<Video> queue;
    bool done=false;uint64_t owner=0,generation=0;uint16_t port;std::thread worker;
    void run(){
        try{
            shuttle_sink::Mapping mapping(port);mapping.open(true);
            uint64_t currentGeneration=UINT64_MAX,sequence=0;unsigned currentMode=2;
            std::deque<uint64_t> outstanding;
            for(;;){
                Video frame;bool have=false;uint64_t gen;
                {std::unique_lock<std::mutex> lock(mutex);changed.wait_for(lock,std::chrono::milliseconds(2));if(done)break;gen=generation;
                    if(!queue.empty()){currentMode=queue.front().mode;}}
                if(gen!=currentGeneration){mapping.reset();mapping.data().mode=currentMode;outstanding.clear();currentGeneration=gen;}
                if(!gen)continue;
                mapping.pump();
                if(!mapping.data().consumer){outstanding.clear();continue;}
                shuttle_sink::Ack ack;while(mapping.popCompletion(ack)){
                    if(!outstanding.empty()&&outstanding.front()==ack.sequence)outstanding.pop_front();
                    else {mapping.reset();mapping.data().mode=currentMode;outstanding.clear();break;}
                }
                auto& ring=mapping.data();
                if(!ring.consumer||outstanding.size()>=6||ring.written.load()-ring.read.load()>=shuttle_sink::Count)continue;
                {std::lock_guard<std::mutex> lock(mutex);if(gen==generation&&!queue.empty()){frame=std::move(queue.front());queue.pop_front();have=true;}}
                if(!have||frame.generation!=currentGeneration)continue;
                auto p=shuttle_output::profile(static_cast<shuttle_output::Mode>(frame.mode));
                auto& slot=ring.slots[ring.written.load()%shuttle_sink::Count];slot.sequence=++sequence;
                // Sequence time is intentionally not passed as host time. The USB engine
                // aligns the independent Core Audio HDMI route using physical wire time.
                slot.hostNS=0;slot.width=p.width;slot.height=p.height;slot.timecode=frame.tc;
                memcpy(slot.image,frame.pixels.data(),frame.pixels.size());
                outstanding.push_back(sequence);ring.written.fetch_add(1);mapping.pump();
            }
        }catch(const std::exception& e){logMessage(e.what());}catch(...){logMessage("Transport stopped after an unexpected error");}
    }
public:
    explicit Transport(uint16_t selectedPort=shuttle_sink::PremierePort):port(selectedPort),worker([this]{@autoreleasepool{run();}}){}
    ~Transport(){{std::lock_guard<std::mutex> lock(mutex);done=true;}changed.notify_one();worker.join();}
    void submit(uint64_t id,Video&& frame){std::lock_guard<std::mutex> lock(mutex);
        if(owner!=id){owner=id;++generation;queue.clear();}
        frame.generation=generation;
        if(queue.size()>=6)queue.pop_front();
        queue.push_back(std::move(frame));changed.notify_one();
    }
    void deactivate(uint64_t id){std::lock_guard<std::mutex> lock(mutex);if(owner==id){owner=0;++generation;queue.clear();changed.notify_one();}}
};
struct Plugin {
    SPBasicSuite* basic=nullptr;PrSDKPPixSuite* pixels=nullptr;PrSDKTimeSuite* time=nullptr;PrSDKSequenceInfoSuite* sequence=nullptr;
    PrTime ticks=0;unsigned mode=savedMode();Transport transport;
    bool acquire(const tmStdParms* std){
        basic=std->piSuites->utilFuncs->getSPBasicSuite();
        if(!basic)return false;
        if(basic->AcquireSuite(kPrSDKPPixSuite,1,(const void**)&pixels)||!pixels)return false;
        if(basic->AcquireSuite(kPrSDKTimeSuite,1,(const void**)&time)||!time||time->GetTicksPerSecond(&ticks)||ticks<=0)return false;
        basic->AcquireSuite(kPrSDKSequenceInfoSuite,1,(const void**)&sequence);
        return true;
    }
    ~Plugin(){if(basic){if(sequence)basic->ReleaseSuite(kPrSDKSequenceInfoSuite,1);if(time)basic->ReleaseSuite(kPrSDKTimeSuite,1);if(pixels)basic->ReleaseSuite(kPrSDKPPixSuite,1);}}
};
struct Instance {unsigned mode;uint64_t id;bool active=false,rejected=false;};
std::atomic<uint64_t> instanceCounter{0};
Plugin* plugin(const tmStdParms* s){return static_cast<Plugin*>(s->ioPrivatePluginData);}
Instance* instance(const tmInstance* i){return static_cast<Instance*>(i->ioPrivateInstanceData);}
tmResult startup(tmStdParms* s,tmPluginInfo* info){try{
    auto p=std::unique_ptr<Plugin>(new Plugin);if(!p->acquire(s))return tmResult_ErrorUnsupported;
    const char16_t* name=u"Intensity Shuttle — HDMI Output";
    std::memset(info,0,sizeof(*info));for(unsigned k=0;name[k]&&k<255;++k)info->outDisplayName[k]=name[k];
    strcpy(info->outIdentifier.mGUID,"0c0d6f54-2a42-4df5-a6aa-e9273a841103");
    info->outVideoAvailable=kPrTrue;info->outVideoDefaultEnabled=kPrFalse;
    // Premiere remains the playback clock. Audio goes through the existing
    // Core Audio HDMI output; no SDK audio clock is advertised or fabricated.
    info->outAudioAvailable=kPrFalse;info->outClockAvailable=kPrFalse;info->outInterfaceVersion=tmInterfaceVersion1;
    s->ioPrivatePluginData=p.release();logMessage("Loaded video transmitter 0.1.29 (Premiere clock; Core Audio HDMI sound)");return tmResult_Success;
}catch(...){return tmResult_ErrorMemory;}}
tmResult needsReset(const tmStdParms* s,prBool* reset){*reset=plugin(s)->mode!=savedMode();return tmResult_Success;}
tmResult shutdown(tmStdParms* s){delete plugin(s);s->ioPrivatePluginData=nullptr;return tmResult_Success;}
tmResult create(const tmStdParms* s,tmInstance* i){try{i->ioPrivateInstanceData=new Instance{plugin(s)->mode,++instanceCounter,false,false};return tmResult_Success;}catch(...){return tmResult_ErrorMemory;}}
tmResult dispose(const tmStdParms* s,tmInstance* i){if(auto* n=instance(i)){plugin(s)->transport.deactivate(n->id);delete n;i->ioPrivateInstanceData=nullptr;}return tmResult_Success;}
tmResult query(const tmStdParms* s,const tmInstance* i,csSDK_int32 index,tmVideoMode* v){
    if(index!=0)return tmResult_ErrorUnsupported;auto n=instance(i);if(!n)return tmResult_ErrorInvalidArgument;
    auto p=shuttle_output::profile(static_cast<shuttle_output::Mode>(n->mode));std::memset(v,0,sizeof(*v));
    v->outWidth=p.width;v->outHeight=p.height;
    v->outPARNum=p.width==720?(p.height==486?9:16):1;v->outPARDen=p.width==720?(p.height==486?10:15):1;
    v->outFieldType=p.interlaced?(p.firstOdd?prFieldsLowerFirst:prFieldsUpperFirst):prFieldsNone;
    v->outPixelFormat=p.height>576?PrPixelFormat_UYVY_422_8u_709:PrPixelFormat_UYVY_422_8u_601;
    v->outColorSpaceRec.outColorSpaceType=kPrSDKColorSpaceType_SEITags;
    auto& color=v->outColorSpaceRec.outSEICodesRec;color.colorPrimariesCode=p.height>576?1:p.height==576?5:6;
    color.transferCharacteristicCode=1;color.matrixEquationsCode=p.height>576?1:6;color.bitDepth=8;color.isFullRange=false;color.isRGB=false;
    v->outLatency=PrTime(static_cast<__int128>(plugin(s)->ticks)*p.rateDen*6/p.rateNom);
    return tmResult_Success;
}
tmResult activate(const tmStdParms* s,const tmInstance* i,PrActivationEvent,prBool,prBool video){
    if(auto* n=instance(i)){n->active=video;if(!video)plugin(s)->transport.deactivate(n->id);}return tmResult_Success;
}
tmResult push(const tmStdParms* s,const tmInstance* i,const tmPushVideo* video){
    auto p=plugin(s);auto n=instance(i);tmResult result=tmResult_Success;
    try{if(n&&n->active&&video->inFrameCount){
        auto profile=shuttle_output::profile(static_cast<shuttle_output::Mode>(n->mode));
        prRect bounds{};csSDK_int32 stride=0;char* data=nullptr;PrPixelFormat format=PrPixelFormat_Invalid;
        auto ppix=video->inFrames[0].inFrame;
        if(!p->pixels->GetBounds(ppix,&bounds)&&!p->pixels->GetRowBytes(ppix,&stride)&&!p->pixels->GetPixelFormat(ppix,&format)&&
            !p->pixels->GetPixels(ppix,PrPPixBufferAccess_ReadOnly,&data)&&
            bounds.right-bounds.left==int(profile.width)&&bounds.bottom-bounds.top==int(profile.height)&&
            format==(profile.height>576?PrPixelFormat_UYVY_422_8u_709:PrPixelFormat_UYVY_422_8u_601)){
            Video frame;frame.mode=n->mode;frame.pixels.resize(size_t(profile.width)*profile.height*2);
            if(shuttle_premiere::copyUYVY(frame.pixels.data(),profile.width,profile.height,data,stride)){
                PrTime zero=0;prBool drop=kPrFalse;
                if(p->sequence&&i->inTimelineID&&!p->sequence->GetZeroPoint(i->inTimelineID,&zero)&&!p->sequence->GetTimecodeDropFrame(i->inTimelineID,&drop))
                    frame.tc=shuttle_premiere::sequenceTimecode(video->inTime,zero,i->inVideoFrameRate,p->ticks,drop);
                p->transport.submit(n->id,std::move(frame));
            }
        }else if(!n->rejected){n->rejected=true;logMessage("Rejected frame with unexpected raster or pixel format");}
    }}catch(...){result=tmResult_ErrorMemory;}
    // Every Adobe-owned PPix is released exactly once, including unsupported
    // labels, inactive instances, malformed frames, and allocation failures.
    for(csSDK_size_t k=0;k<video->inFrameCount;++k)p->pixels->Dispose(video->inFrames[k].inFrame);
    return result;
}
}
extern "C" __attribute__((visibility("default"))) tmResult xTransmitEntry(csSDK_int32 version,prBool load,piSuitesPtr,tmModule* module){
    if(version<tmInterfaceVersion1||version>tmInterfaceVersion4)return tmResult_ErrorUnsupported;
    if(!load)return tmResult_Success;
    // Use only v1 fields, so this SDK26 build also works with older hosts.
    module->Startup=startup;module->Shutdown=shutdown;module->CreateInstance=create;module->DisposeInstance=dispose;
    module->SetupDialog=nullptr;module->NeedsReset=needsReset;module->QueryAudioMode=nullptr;module->StartPlaybackClock=nullptr;module->StopPlaybackClock=nullptr;module->QueryVideoMode=query;module->ActivateDeactivate=activate;module->PushVideo=push;
    return tmResult_Success;
}
