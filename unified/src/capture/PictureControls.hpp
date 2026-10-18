// GPL-2.0-or-later. Software controls on deinterlaced native UYVY, before scaling.
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>
namespace shuttle {
struct PictureSettings { int brightness=0,contrast=100,colour=100,sharpness=0; };
class PictureControls {
    PictureSettings settings;
    std::array<uint8_t,256> luma,chroma;
    std::vector<uint8_t> row;
    static uint8_t bound(double value,int low,int high){return uint8_t(std::max(double(low),std::min(double(high),std::round(value))));}
public:
    explicit PictureControls(PictureSettings s):settings(s){
        for(int i=0;i<256;++i){luma[i]=bound((i-125.5)*s.contrast/100.0+125.5+s.brightness*2.19,16,235);chroma[i]=bound((i-128)*s.colour/100.0+128,16,240);}
    }
    void apply(uint8_t* data,unsigned width,unsigned height,size_t stride){
        if(!data||!width||width%2||stride<size_t(width)*2)return;
        const bool yChange=settings.brightness||settings.contrast!=100,cChange=settings.colour!=100;
        if(!yChange&&!cChange&&!settings.sharpness)return; // exact identity, including superwhites
        if(settings.sharpness)row.resize(width);
        for(unsigned y=0;y<height;++y){auto* p=data+y*stride;
            if(settings.sharpness)for(unsigned x=0;x<width;++x)row[x]=p[x*2+1];
            for(unsigned x=0;x<width;++x){
                if(cChange)p[x*2]=chroma[p[x*2]];
                if(settings.sharpness){double value=row[x]+settings.sharpness/100.0*(row[x]-(row[x?x-1:x]+row[x+1<width?x+1:x])*0.5);p[x*2+1]=luma[bound(value,0,255)];}
                else if(yChange)p[x*2+1]=luma[p[x*2+1]];
            }
        }
    }
};
}
