// GPL-2.0-or-later. SDK-independent validation and sequence timecode conversion.
#pragma once
#include "../src/output/Timecode.hpp"
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
namespace shuttle_premiere {
inline bool copyUYVY(uint8_t* output,unsigned width,unsigned height,const char* input,ptrdiff_t stride){
    if(!output||!input||!width||width%2||!height||width>1920||height>1080||
       stride==std::numeric_limits<ptrdiff_t>::min()||size_t(stride<0?-stride:stride)<size_t(width)*2)return false;
    for(unsigned y=0;y<height;++y)std::memcpy(output+size_t(y)*width*2,input+ptrdiff_t(y)*stride,size_t(width)*2);
    return true;
}
inline shuttle_sink::Timecode sequenceTimecode(int64_t ticks,int64_t zero,int64_t duration,int64_t ticksPerSecond,bool drop){
    shuttle_sink::Timecode tc{};
    if(ticks<0||duration<=0||ticksPerSecond<=0)return tc;
    const double fps=double(ticksPerSecond)/duration;
    unsigned rate=0;
    for(unsigned r:{24u,25u,30u,50u,60u})if(fps>r*0.998&&fps<r*1.002){rate=r;break;}
    if(!rate|| (drop&&rate!=30&&rate!=60))return tc;
    __int128 total=static_cast<__int128>(ticks)+zero;
    if(total<0)return tc;
    int64_t frames=int64_t(total/duration);
    if(drop){
        // SMPTE 29.97/59.94: skip 2/4 frame labels each minute except every tenth.
        const int64_t d=rate==60?4:2,per10=rate*600-d*9,perMinute=rate*60-d;
        frames%=per10*6*24;
        int64_t tens=frames/per10,rem=frames%per10;
        frames+=d*9*tens+(rem>=d?d*((rem-d)/perMinute):0);
    }else frames%=int64_t(rate)*86400;
    tc.valid=1;tc.rate=uint8_t(rate);tc.drop=drop;tc.frames=frames%rate;
    frames/=rate;tc.seconds=frames%60;frames/=60;tc.minutes=frames%60;tc.hours=(frames/60)%24;
    return tc;
}
}
