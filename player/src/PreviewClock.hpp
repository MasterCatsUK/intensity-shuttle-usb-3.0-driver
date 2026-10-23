// GPL-2.0-or-later. 19 October 2026: steady local preview cadence.
#pragma once
#include <algorithm>
#include <cstdint>
namespace player {
constexpr unsigned PreviewFrames=8;
class PreviewClock {
    uint64_t first=0,anchorNS=0;
public:
    void reset(){first=anchorNS=0;}
    uint64_t choose(uint64_t newest,unsigned rateNom,unsigned rateDen,uint64_t nowNS){
        if(!newest||!rateNom||!rateDen)return 0;
        const uint64_t oldest=newest>=PreviewFrames?newest-PreviewFrames+1:1;
        if(!first){first=oldest;anchorNS=nowNS;}
        const uint64_t elapsed=nowNS>=anchorNS?nowNS-anchorNS:0;
        uint64_t wanted=first+uint64_t(static_cast<unsigned __int128>(elapsed)*rateNom/(1000000000ULL*rateDen));
        if(wanted<oldest){first=wanted=oldest;anchorNS=nowNS;}
        if(wanted>newest){first=wanted=newest;anchorNS=nowNS;}
        return wanted;
    }
};
}
