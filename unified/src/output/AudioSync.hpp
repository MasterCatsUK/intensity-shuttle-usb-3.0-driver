// GPL-2.0-or-later. HDMI timeline audio offset after the cadence cursor.
#pragma once
#include <cstdint>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>
namespace shuttle_output_audio {
constexpr int MinAudioOffsetMS=-100,MaxAudioOffsetMS=500;
inline int clampAudioOffset(int value){return value<MinAudioOffsetMS?MinAudioOffsetMS:value>MaxAudioOffsetMS?MaxAudioOffsetMS:value;}
inline uint64_t offsetAudioSample(uint64_t first,int milliseconds){
    // Positive = later sound: older audio; negative = earlier: newer audio.
    int64_t shift=int64_t(clampAudioOffset(milliseconds))*48;
    if(shift>=0)return first<uint64_t(shift)?0:first-uint64_t(shift);
    uint64_t advance=uint64_t(-shift);return first>UINT64_MAX-advance?UINT64_MAX:first+advance;
}
// Preference I/O stays off the USB event thread.
class LiveAudioOffset {
    std::atomic<int> value_;std::mutex mutex_;std::condition_variable wake_;
    bool stopping_=false;std::thread worker_;
public:
    using Read=int(*)();
    LiveAudioOffset(int initial,Read read):value_(clampAudioOffset(initial)),worker_([this,read]{
        std::unique_lock<std::mutex> lock(mutex_);
        while(!wake_.wait_for(lock,std::chrono::milliseconds(200),[this]{return stopping_;})){
            lock.unlock();int next=read();value_.store(clampAudioOffset(next));lock.lock();
        }
    }){}
    ~LiveAudioOffset(){{std::lock_guard<std::mutex> lock(mutex_);stopping_=true;}wake_.notify_one();worker_.join();}
    int milliseconds()const{return value_.load();}
};
}
