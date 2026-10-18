// GPL-2.0-or-later. Optional 80% title / 90% action guides on outgoing video.
#pragma once
#include "Timecode.hpp"
namespace shuttle_sink {
inline TimecodeBox safeZoneBox(unsigned width,unsigned height,bool title){
    if(width<320||height<200||width%2)return {};
    unsigned inset=title?10:5;
    unsigned x=((width*inset+100)/200)*2,y=(height*inset+50)/100;
    return {x,y,width-2*x,height-2*y};
}
namespace safe_zone_detail {
inline uint8_t blend(unsigned from,unsigned to,unsigned alpha){return uint8_t((from*(255-alpha)+to*alpha+127)/255);}
inline void fill(std::vector<uint8_t>& image,unsigned width,TimecodeBox r,unsigned y,unsigned u,unsigned v,unsigned alpha){
    for(unsigned yy=r.y;yy<r.y+r.height;++yy)for(unsigned xx=r.x;xx<r.x+r.width;xx+=2){
        auto* p=&image[(size_t(yy)*width+xx)*2];p[0]=blend(p[0],u,alpha);p[1]=blend(p[1],y,alpha);p[2]=blend(p[2],v,alpha);p[3]=blend(p[3],y,alpha);
    }
}
inline void stroke(std::vector<uint8_t>& image,unsigned width,TimecodeBox r,unsigned thickness,unsigned y,unsigned u,unsigned v,unsigned alpha){
    fill(image,width,{r.x,r.y,r.width,thickness},y,u,v,alpha);
    fill(image,width,{r.x,r.y+r.height-thickness,r.width,thickness},y,u,v,alpha);
    fill(image,width,{r.x,r.y+thickness,thickness,r.height-2*thickness},y,u,v,alpha);
    fill(image,width,{r.x+r.width-thickness,r.y+thickness,thickness,r.height-2*thickness},y,u,v,alpha);
}
}
inline void overlaySafeZones(std::vector<uint8_t>& image,unsigned width,unsigned height,bool title,bool action){
    if((!title&&!action)||image.size()!=size_t(width)*height*2)return;
    for(unsigned guide=0;guide<2;++guide){
        bool isTitle=guide==1;if(isTitle?!title:!action)continue;
        auto box=safeZoneBox(width,height,isTitle);if(!box.width)continue;
        TimecodeBox halo{box.x-2,box.y-2,box.width+4,box.height+4};
        // Two-pixel cores remain visible in interlaced modes. A dark keyline
        // keeps both guides readable against bright footage.
        safe_zone_detail::stroke(image,width,halo,6,16,128,128,128);
        if(isTitle)safe_zone_detail::stroke(image,width,box,2,235,128,128,230);
        else safe_zone_detail::stroke(image,width,box,2,width>=1280?219:210,16,width>=1280?138:146,230);
    }
}
}
