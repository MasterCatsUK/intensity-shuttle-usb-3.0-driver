// GPL-2.0-or-later. Estimate host presentation from completed USB microframes.
#pragma once
#include <cstdint>
#include <cstddef>
#include <limits>

namespace shuttle_output_audio {
class WireClock {
    uint64_t tick_=0,host_=0;
    bool valid_=false;
public:
    static constexpr uint64_t TickNS=125000;
    bool valid() const{return valid_;}
    void completed(uint64_t endTick,uint64_t hostNS){
        if(valid_&&endTick<=tick_)return;
        if(valid_){
            const __int128 predicted=__int128(host_)+__int128(endTick-tick_)*TickNS;
            const __int128 error=__int128(hostNS)-predicted;
            // Callback delivery can be late or batched after a control read.
            // Such observations do not mean the USB bus changed phase. Ignore
            // outliers, and bound ordinary phase corrections to 250 us per
            // 32-ms transfer so frame-start acknowledgements cannot jump back.
            if(predicted<0||predicted>std::numeric_limits<uint64_t>::max())return;
            __int128 correction=0;
            if(error>-8000000&&error<8000000){correction=error/8;if(correction>250000)correction=250000;if(correction< -250000)correction= -250000;}
            hostNS=uint64_t(predicted+correction);
        }
        tick_=endTick;host_=hostNS;valid_=true;
    }
    static bool position(uint64_t startTick,const unsigned* lengths,size_t count,
                         size_t byteOffset,uint64_t& tick,uint64_t& fractionNS){
        size_t packet=0;
        while(packet<count&&byteOffset>=lengths[packet]){
            byteOffset-=lengths[packet];++packet;
        }
        if(packet==count&&byteOffset)return false;
        if(startTick>std::numeric_limits<uint64_t>::max()-packet)return false;
        tick=startTick+packet;
        fractionNS=packet<count&&lengths[packet]?uint64_t(__int128(byteOffset)*TickNS/lengths[packet]):0;
        return true;
    }
    bool atTick(uint64_t tick,uint64_t fractionNS,uint64_t& hostNS) const{
        if(!valid_||fractionNS>=TickNS)return false;
        const __int128 offset=(__int128(tick)-tick_)*TickNS+fractionNS;
        const __int128 result=__int128(host_)+offset;
        if(result<0||result>std::numeric_limits<uint64_t>::max())return false;
        hostNS=uint64_t(result);return true;
    }
    bool at(uint64_t startTick,const unsigned* lengths,size_t count,
            size_t byteOffset,uint64_t& hostNS) const{
        uint64_t tick=0,fraction=0;
        return position(startTick,lengths,count,byteOffset,tick,fraction)&&atTick(tick,fraction,hostNS);
    }
};

enum class VideoClockDomain {Unknown,Host,Wire};
inline VideoClockDomain classifyPTS(uint64_t ptsNS,uint64_t hostNS){
    const uint64_t distance=ptsNS>hostNS?ptsNS-hostNS:hostNS-ptsNS;
    // Queues are bounded to a few frames. An unrelated media-time origin must
    // never be used directly as an absolute Core Audio sample position.
    return distance<=2000000000ULL?VideoClockDomain::Host:VideoClockDomain::Wire;
}
}
