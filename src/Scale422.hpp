// GPL-2.0-or-later. Scale luma/chroma separately; preserve packed UYVY ordering.
#pragma once
#include <Accelerate/Accelerate.h>
#include <array>
#include <vector>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <algorithm>
namespace shuttle {
class Scale422 {
    unsigned sourceHeight,width,height;
    bool identity;
    std::array<std::vector<uint8_t>,3> input,output;
    std::vector<uint8_t> scratch;
    vImage_Buffer source(unsigned p) { unsigned w=p?360:720;return {input[p].data(),sourceHeight,w,w}; }
    vImage_Buffer target(unsigned p) { unsigned w=p?width/2:width;return {output[p].data(),height,w,w}; }
public:
    Scale422(unsigned sourceHeight,unsigned width,unsigned height):sourceHeight(sourceHeight),width(width),height(height),identity(width==720 && height==sourceHeight) {
        if((sourceHeight!=480 && sourceHeight!=576) || width<2 || width%2 || width>1440 || !height || height>1080)
            throw std::invalid_argument("Invalid SD output scaling dimensions");
        if(identity) return;
        size_t largest=0;
        for(unsigned p=0;p<3;++p) {
            input[p].resize((p?360:720)*sourceHeight);output[p].resize((p?width/2:width)*height);
            auto s=source(p),d=target(p);
            auto bytes=vImageScale_Planar8(&s,&d,nullptr,kvImageHighQualityResampling|kvImageGetTempBufferSize);
            if(bytes<0) throw std::runtime_error("Cannot allocate output resampler");
            largest=std::max(largest,size_t(bytes));
        }
        scratch.resize(std::max(size_t(1),largest));
    }
    // Caller owns the immutable destination surface. No allocation during scaling.
    bool write(const uint8_t *bytes,uint8_t *dest,size_t stride) {
        if(!bytes || !dest || stride<size_t(width)*2) return false;
        if(identity) { for(unsigned y=0;y<height;++y) std::memcpy(dest+y*stride,bytes+y*1440,1440);return true; }
        for(unsigned y=0;y<sourceHeight;++y) for(unsigned x=0;x<360;++x) {
            const uint8_t *pair=bytes+y*1440+x*4;size_t n=y*360+x;
            input[1][n]=pair[0];input[0][n*2]=pair[1];input[2][n]=pair[2];input[0][n*2+1]=pair[3];
        }
        for(unsigned p=0;p<3;++p) {
            auto s=source(p),d=target(p);
            if(vImageScale_Planar8(&s,&d,scratch.data(),kvImageHighQualityResampling)!=kvImageNoError) return false;
        }
        for(unsigned y=0;y<height;++y) for(unsigned x=0;x<width/2;++x) {
            uint8_t *pair=dest+y*stride+x*4;size_t n=y*(width/2)+x;
            pair[0]=output[1][n];pair[1]=output[0][n*2];pair[2]=output[2][n];pair[3]=output[0][n*2+1];
        }
        return true;
    }
};
} // namespace shuttle
