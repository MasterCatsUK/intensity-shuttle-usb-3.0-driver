// GPL-2.0-or-later. Keep fixed 10 ms packets across PAL/NTSC audio block sizes.
#pragma once
#include "AudioProtocol.hpp"
#include <algorithm>
#include <cstdint>
namespace shuttle_audio {
class Packetizer {
    Packet packet{};
    unsigned used=0;
    uint64_t expectedNS=0,baseNS=0,sourceFrames=0;
public:
    void reset() { used=0;expectedNS=0;baseNS=0;sourceFrames=0; }
    template<class Sample,class Send> void push(unsigned count,uint64_t startNS,Sample sample,Send send) {
        int64_t gap=int64_t(startNS)-int64_t(expectedNS);
        if(!expectedNS || gap>1000000 || gap < -1000000) { used=0;baseNS=startNS;sourceFrames=0; }
        for(unsigned n=0;n<count;++n) {
            if(!used) packet.hostNS=baseNS+(sourceFrames+n)*1000000000ULL/Rate;
            for(unsigned ch=0;ch<2;++ch) packet.samples[used*2+ch]=sample(n,ch);
            if(++used==Frames) { send(packet);used=0; }
        }
        sourceFrames+=count;
        expectedNS=baseNS+sourceFrames*1000000000ULL/Rate;
    }
};
} // namespace shuttle_audio
