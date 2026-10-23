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
    unsigned sourceHeight,width,height,imageWidth,imageHeight,offsetX,offsetY;
    bool identity;
    std::array<std::vector<uint8_t>,3> input,output;
    std::vector<uint8_t> scratch;
    vImage_Buffer source(unsigned p) { unsigned w=p?360:720;return {input[p].data(),sourceHeight,w,w}; }
    vImage_Buffer target(unsigned p) { unsigned w=p?imageWidth/2:imageWidth;return {output[p].data(),imageHeight,w,w}; }
public:
    Scale422(unsigned sourceHeight,unsigned width,unsigned height,unsigned contentWidth=0,unsigned contentHeight=0):sourceHeight(sourceHeight),width(width),height(height),imageWidth(contentWidth?contentWidth:width),imageHeight(contentHeight?contentHeight:height),offsetX(0),offsetY(0),identity(false) {
        if((sourceHeight!=240 && sourceHeight!=288 && sourceHeight!=480 && sourceHeight!=576) || width<2 || width%2 || width>1920 || !height || height>1080 || imageWidth<2 || imageWidth%2 || imageWidth>width || !imageHeight || imageHeight>height)
            throw std::invalid_argument("Invalid SD output scaling dimensions");
        offsetX=((width-imageWidth)/2)&~1u;offsetY=(height-imageHeight)/2;
        identity=width==720 && height==sourceHeight && imageWidth==width && imageHeight==height;
        if(identity) return;
        size_t largest=0;
        for(unsigned p=0;p<3;++p) {
            input[p].resize((p?360:720)*sourceHeight);output[p].resize((p?imageWidth/2:imageWidth)*imageHeight);
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
        // Studio-range neutral black in borders; do not touch row padding.
        if(imageWidth!=width||imageHeight!=height)
            for(unsigned y=0;y<height;++y)for(unsigned x=0;x<width/2;++x){auto p=dest+y*stride+x*4;p[0]=p[2]=128;p[1]=p[3]=16;}
        for(unsigned y=0;y<imageHeight;++y) for(unsigned x=0;x<imageWidth/2;++x) {
            uint8_t *pair=dest+(y+offsetY)*stride+offsetX*2+x*4;size_t n=y*(imageWidth/2)+x;
            pair[0]=output[1][n];pair[1]=output[0][n*2];pair[2]=output[2][n];pair[3]=output[0][n*2+1];
        }
        return true;
    }
};
// Resample each field separately so no filter can mix different motion instants.
class InterlacedScale422 {
    unsigned sourceHeight,width,height;
    Scale422 fieldScale;
    std::vector<uint8_t> sourceField,targetField;
public:
    InterlacedScale422(unsigned sourceH,unsigned w,unsigned h,unsigned iw,unsigned ih):sourceHeight(sourceH),width(w),height(h),fieldScale(sourceH/2,w,h/2,iw,ih/2),sourceField(1440*sourceH/2),targetField(w*h) {
        if((sourceH!=480&&sourceH!=576)||h%2||ih%2)throw std::invalid_argument("Invalid interlaced dimensions");
    }
    bool write(const uint8_t *bytes,uint8_t *dest,size_t stride){
        if(!bytes||!dest||stride<width*2)return false;
        for(unsigned field=0;field<2;++field){
            for(unsigned y=0;y<sourceHeight/2;++y)std::memcpy(sourceField.data()+y*1440,bytes+(2*y+field)*1440,1440);
            if(!fieldScale.write(sourceField.data(),targetField.data(),width*2))return false;
            for(unsigned y=0;y<height/2;++y)std::memcpy(dest+(2*y+field)*stride,targetField.data()+y*width*2,width*2);
        }
        return true;
    }
};
} // namespace shuttle
