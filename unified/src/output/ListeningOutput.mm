// GPL-2.0-or-later. Optional local listening, isolated from video/USB scheduling.
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#include "ListeningOutput.hpp"
#include "../capture/MonitorAudio.hpp"
#include <thread>
#include <mutex>
#include <condition_variable>
#include <array>
namespace shuttle_listen {
struct Output::Impl {
    shuttle_monitor::StereoRing ring;
    std::mutex mutex;std::condition_variable changed;bool stopping=false;
    AudioQueueRef queue=nullptr;NSString* current=nil;std::thread worker;
    static void render(void* context,AudioQueueRef queue,AudioQueueBufferRef buffer){
        auto& ring=static_cast<Impl*>(context)->ring;
        ring.render(static_cast<float*>(buffer->mAudioData),buffer->mAudioDataBytesCapacity/8);
        buffer->mAudioDataByteSize=buffer->mAudioDataBytesCapacity;AudioQueueEnqueueBuffer(queue,buffer,0,nullptr);
    }
    void stop(){
        ring.listening=false;
        if(queue){AudioQueueStop(queue,true);AudioQueueDispose(queue,true);queue=nullptr;}
        current=nil;
    }
    bool start(NSString* uid){
        // The virtual output is the input of this pipeline: sending back to it
        // would create a feedback loop. Explicit physical output UID required.
        if(!uid.length||[uid isEqual:@"local.shuttle.audio.hdmi"]||[uid isEqual:@"local.shuttle.audio.stereo"]){fprintf(stderr,"Listening unavailable: choose Mac speakers or headphones.\n");return false;}
        AudioStreamBasicDescription f{};f.mSampleRate=48000;f.mFormatID=kAudioFormatLinearPCM;
        f.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked;f.mBytesPerFrame=f.mBytesPerPacket=8;f.mFramesPerPacket=1;f.mChannelsPerFrame=2;f.mBitsPerChannel=32;
        OSStatus status=AudioQueueNewOutput(&f,render,this,nullptr,nullptr,0,&queue);
        CFStringRef selected=(__bridge CFStringRef)uid;
        if(!status)status=AudioQueueSetProperty(queue,kAudioQueueProperty_CurrentDevice,&selected,sizeof(selected));
        if(!status){ring.read.store(ring.write.load());ring.listening=true;
            for(unsigned n=0;n<3&&!status;++n){AudioQueueBufferRef b=nullptr;status=AudioQueueAllocateBuffer(queue,512*8,&b);if(!status)render(this,queue,b);}
            if(!status)status=AudioQueueStart(queue,nullptr);
        }
        if(status){stop();fprintf(stderr,"Listening output unavailable (Core Audio %d). Meters and destination audio remain active.\n",int(status));return false;}
        current=[uid copy];fprintf(stderr,"Listening on selected speakers/headphones. Monitor volume is independent of outgoing audio.\n");return true;
    }
    void run(){
        std::unique_lock<std::mutex> lock(mutex);
        NSString* lastFailure=nil;
        while(!stopping){lock.unlock();@autoreleasepool{
            CFStringRef domain=CFSTR("local.shuttle.camera");CFPreferencesAppSynchronize(domain);Boolean exists=false;
            bool wanted=CFPreferencesGetAppBooleanValue(CFSTR("OutputListenEnabled"),domain,&exists)&&exists;
            id value=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("OutputListenVolume"),domain));
            double gain=[value isKindOfClass:NSNumber.class]?[value doubleValue]:.5;if(!std::isfinite(gain))gain=.5;
            ring.gain=float(std::max(0.,std::min(1.,gain)));
            id saved=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("OutputListenDeviceUID"),domain));NSString* uid=[saved isKindOfClass:NSString.class]?saved:@"";
            if(!wanted){if(queue){stop();fputs("Local listening off; meters continue receiving audio.\n",stderr);}lastFailure=nil;}
            else if(![uid isEqual:current]&&![uid isEqual:lastFailure]){stop();if(!start(uid))lastFailure=[uid copy]?:@"";else lastFailure=nil;}
        }lock.lock();changed.wait_for(lock,std::chrono::milliseconds(200),[this]{return stopping;});}
        lock.unlock();stop();
    }
    Impl(){worker=std::thread([this]{run();});}
    ~Impl(){{std::lock_guard<std::mutex> lock(mutex);stopping=true;}changed.notify_one();worker.join();}
};
Output::Output(bool enabled){if(enabled)impl.reset(new Impl);}
Output::~Output()=default;
void Output::push(const std::vector<int32_t>& pcm){
    if(!impl||!impl->ring.listening.load(std::memory_order_relaxed))return;
    std::array<float,4096> values{};size_t frames=pcm.size()/8;
    for(size_t at=0;at<frames;){unsigned count=unsigned(std::min<size_t>(2048,frames-at));
        for(unsigned n=0;n<count;++n){values[n*2]=float(pcm[(at+n)*8]/8388607.0);values[n*2+1]=float(pcm[(at+n)*8+1]/8388607.0);}
        impl->ring.push(values.data(),nullptr,count,true);at+=count;
    }
}
}
