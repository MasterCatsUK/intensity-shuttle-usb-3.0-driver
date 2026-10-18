// GPL-2.0-or-later. Read-only stereo peak meters for the actual outgoing PCM.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "Timecode.hpp"
namespace shuttle_output_audio {
struct MeterChannel {double levelDB=-60,peakDB=-60,hold=0,clip=0;};
class StereoMeters {
    MeterChannel channels_[2];
public:
    void reset(){channels_[0]={};channels_[1]={};}
    void update(const std::vector<int32_t>& pcm,double seconds){
        if(!std::isfinite(seconds)||seconds<=0)return;
        seconds=std::min(seconds,1.0);
        for(unsigned ch=0;ch<2;++ch){
            uint64_t maximum=0;
            for(size_t frame=0;frame<pcm.size()/8;++frame){
                int64_t sample=pcm[frame*8+ch];maximum=std::max(maximum,uint64_t(sample<0?-sample:sample));
            }
            double db=maximum?20*std::log10(std::min(1.0,double(maximum)/8388607.0)):-60;
            db=std::max(-60.0,db);auto& state=channels_[ch];
            state.levelDB=std::max(db,state.levelDB-24*seconds);
            if(db>=state.peakDB){state.peakDB=db;state.hold=0.75;}
            else {state.hold=std::max(0.0,state.hold-seconds);if(!state.hold)state.peakDB=std::max(state.levelDB,state.peakDB-18*seconds);}
            state.clip=maximum>=8388607?1.0:std::max(0.0,state.clip-seconds);
        }
    }
    const MeterChannel& channel(unsigned index)const{return channels_[index<2?index:0];}
};
inline unsigned savedMeterPosition(long value){return value>=1&&value<=6?unsigned(value-1):2;}
}
namespace shuttle_sink {
TimecodeBox audioMeterBox(unsigned width,unsigned height,unsigned position=2,TimecodeBox avoid={});
void overlayAudioMeters(std::vector<uint8_t>& image,unsigned width,unsigned height,
    const shuttle_output_audio::StereoMeters& meters,unsigned position=2,TimecodeBox avoid={});
}
