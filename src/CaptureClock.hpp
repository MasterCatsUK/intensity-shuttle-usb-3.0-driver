// GPL-2.0-or-later. One source timecode-to-host mapping for both capture paths.
#pragma once
#include <cstdint>
#include <mutex>
#include <algorithm>
#include "VideoProfile.hpp"
namespace shuttle {
constexpr uint64_t FrameNS=40000000ULL, FieldNS=20000000ULL, PlayoutDelayNS=80000000ULL;
class CaptureClock {
    std::mutex lock;
    VideoProfile profile;
    bool anchored=false;
    uint16_t previous=0;
    uint64_t start=0,lastAudio=0;
    uint64_t advance(uint16_t tc,uint64_t now,bool audioBlock=false) {
        uint64_t period=profile.frameNS();
        uint64_t observed=now>period?now-period:0;
        if(!anchored) { anchored=true;previous=tc;start=observed;return start; }
        int delta=int16_t(uint16_t(tc-previous));
        if(!delta && !audioBlock) return start;
        if(!delta) delta=1; // A fresh PCM block advances even if video timecode freezes.
        int64_t candidate=int64_t(start)+int64_t(delta)*int64_t(profile.frameNS());
        int64_t error=candidate-int64_t(observed);
        if(delta<0 || delta>250 || error>250000000LL || error < -250000000LL)
            start=std::max(start+profile.frameNS(),observed); // A reset never closes up elapsed time.
        else start=uint64_t(candidate);
        previous=tc;return start;
    }
public:
    void configure(VideoProfile value) { std::lock_guard<std::mutex> guard(lock);profile=value;anchored=false;lastAudio=0; }
    void reset() { std::lock_guard<std::mutex> guard(lock);anchored=false;lastAudio=0; }
    uint64_t audio(uint16_t tc,uint64_t now) {
        std::lock_guard<std::mutex> guard(lock);lastAudio=now;return advance(tc,now,true);
    }
    uint64_t video(uint16_t tc,uint64_t now) {
        std::lock_guard<std::mutex> guard(lock);
        if(!anchored || !lastAudio || (now>lastAudio && now-lastAudio>200000000ULL)) return advance(tc,now);
        int delta=int16_t(uint16_t(tc-previous));
        int64_t value=int64_t(start)+int64_t(delta)*int64_t(profile.frameNS());
        if(value<0 || delta < -32 || delta>32) return 0; // Stale or other-format counter.
        return uint64_t(value);
    }
};
} // namespace shuttle
