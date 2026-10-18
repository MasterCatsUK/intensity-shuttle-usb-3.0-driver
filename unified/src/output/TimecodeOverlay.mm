// GPL-2.0-or-later. Cached Core Text glyph masks, composed directly into UYVY.
#include "Timecode.hpp"
#include "AudioMeters.hpp"
#include <CoreText/CoreText.h>
#include <CoreGraphics/CoreGraphics.h>
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace shuttle_sink {
namespace {
constexpr char Characters[]="0123456789:- DFTCLRBSd";
struct FontAtlas {
    unsigned advance,height,cellWidth;
    std::vector<std::vector<uint8_t>> glyphs;
    FontAtlas(double size){
        CTFontRef font=CTFontCreateWithName(CFSTR("Menlo-Bold"),size,nullptr);
        if(!font)throw std::runtime_error("Cannot load timecode font");
        UniChar zero='0';CGGlyph zeroGlyph=0;CTFontGetGlyphsForCharacters(font,&zero,&zeroGlyph,1);CGSize metric{};
        CTFontGetAdvancesForGlyphs(font,kCTFontOrientationHorizontal,&zeroGlyph,&metric,1);
        advance=unsigned(std::ceil(metric.width));cellWidth=advance+4;
        height=unsigned(std::ceil(CTFontGetAscent(font)+CTFontGetDescent(font)))+4;
        for(char c:Characters){
            if(!c)break;
            std::vector<uint8_t> mask(size_t(cellWidth)*height,0);
            auto context=CGBitmapContextCreate(mask.data(),cellWidth,height,8,cellWidth,nullptr,kCGImageAlphaOnly);
            if(!context){CFRelease(font);throw std::runtime_error("Cannot draw timecode font");}
            CGContextSetShouldAntialias(context,true);CGContextSetShouldSmoothFonts(context,true);
            CGContextSetShouldSubpixelPositionFonts(context,false);CGContextSetShouldSubpixelQuantizeFonts(context,false);
            CGContextSetGrayFillColor(context,1,1);
            UniChar character=c;CGGlyph glyph=0;CTFontGetGlyphsForCharacters(font,&character,&glyph,1);
            CGPoint point{2,std::ceil(CTFontGetDescent(font))+2};
            CTFontDrawGlyphs(font,&glyph,&point,1,context);CGContextRelease(context);
            // The bitmap's stored row order is already suitable for video.
            glyphs.push_back(std::move(mask));
        }
        CFRelease(font);
    }
    const std::vector<uint8_t>& glyph(char c)const{
        const char* found=std::strchr(Characters,c);
        return glyphs[found?size_t(found-Characters):12];
    }
};
FontAtlas& atlas(unsigned width){static FontAtlas sd(24),hd(40);return width>=1280?hd:sd;}
FontAtlas& meterAtlas(unsigned width){static FontAtlas sd(14),hd(22);return width>=1280?hd:sd;}
void overlayText(const Timecode& code,char (&text)[24]){
    char time[16];timecodeText(code,time);std::snprintf(text,sizeof(text),"TC %s",time);
}
inline uint8_t mix(unsigned from,unsigned to,unsigned alpha){return uint8_t((from*(255-alpha)+to*alpha+127)/255);}
}
void prepareTimecodeOverlay(){(void)atlas(720);(void)meterAtlas(720);}
TimecodeBox timecodeOverlayBox(unsigned width,unsigned height,const Timecode& code,unsigned position){
    if(width<320||height<200||width%2)return {};
    char text[24];overlayText(code,text);auto& font=atlas(width);
    unsigned padding=width>=1280?12:8;
    unsigned boxWidth=(unsigned(std::strlen(text))*font.advance+4+2*padding+1)&~1u;
    unsigned boxHeight=font.height+2*padding;
    unsigned mx=(width/20)&~1u,my=height/20;
    unsigned horizontal=1;bool top=false;
    switch(validTimecodePosition(position)){
        case 0:horizontal=0;top=true;break;case 1:horizontal=2;top=true;break;
        case 2:horizontal=2;break;case 3:horizontal=0;break;case 4:top=true;break;
    }
    if(boxWidth+2*mx>width||boxHeight+2*my>height)return {};
    unsigned x=horizontal==0?mx:horizontal==2?width-mx-boxWidth:(width-boxWidth)/2;
    return {x&~1u,top?my:height-my-boxHeight,boxWidth,boxHeight};
}
void overlayTimecode(std::vector<uint8_t>& image,unsigned width,unsigned height,const Timecode& code,unsigned position){
    if(image.size()!=size_t(width)*height*2)return;
    auto box=timecodeOverlayBox(width,height,code,position);if(!box.width)return;
    auto& font=atlas(width);char text[24];overlayText(code,text);
    const unsigned padding=width>=1280?12:8;
    // The glyphs are rasterized once at startup. Per-frame composition uses
    // integer alpha blends only; no font loading or Core Text calls on USB I/O.
    std::vector<uint8_t> alpha(size_t(box.width)*box.height,0);
    for(unsigned n=0;text[n];++n){auto& glyph=font.glyph(text[n]);
        for(unsigned y=0;y<font.height;++y)for(unsigned x=0;x<font.cellWidth;++x){
            auto& dest=alpha[size_t(y+padding)*box.width+padding+n*font.advance+x];
            dest=std::max(dest,glyph[size_t(y)*font.cellWidth+x]);
        }
    }
    for(unsigned y=0;y<box.height;++y)for(unsigned x=0;x<box.width;x+=2){
        auto* pixel=&image[(size_t(box.y+y)*width+box.x+x)*2];
        unsigned a0=alpha[size_t(y)*box.width+x],a1=alpha[size_t(y)*box.width+x+1];
        // 50%-opacity black retains the picture and its colour beneath it.
        // White glyph coverage is antialiased; U/V share pair-average coverage.
        unsigned chroma=(a0+a1+1)/2;
        pixel[0]=mix((unsigned(pixel[0])+128+1)/2,128,chroma);
        pixel[2]=mix((unsigned(pixel[2])+128+1)/2,128,chroma);
        pixel[1]=mix((unsigned(pixel[1])+16+1)/2,235,a0);
        pixel[3]=mix((unsigned(pixel[3])+16+1)/2,235,a1);
    }
}
namespace {
bool overlaps(TimecodeBox a,TimecodeBox b){return a.width&&b.width&&a.x<b.x+b.width&&b.x<a.x+a.width&&a.y<b.y+b.height&&b.y<a.y+a.height;}
struct YUV {unsigned y,u,v;};
YUV rgb(double r,double g,double b,bool hd){
    double kr=hd?.2126:.299,kb=hd?.0722:.114,luma=kr*r+(1-kr-kb)*g+kb*b;
    return {unsigned(std::lround(16+219*luma)),unsigned(std::lround(128+112*(b-luma)/(1-kb))),unsigned(std::lround(128+112*(r-luma)/(1-kr)))};
}
void solid(std::vector<uint8_t>& image,unsigned width,unsigned x,unsigned y,unsigned w,unsigned h,YUV c){
    x&=~1u;w&=~1u;
    for(unsigned row=y;row<y+h;++row)for(unsigned col=x;col<x+w;col+=2){
        auto* p=&image[(size_t(row)*width+col)*2];p[0]=c.u;p[1]=p[3]=c.y;p[2]=c.v;
    }
}
void meterLabel(std::vector<uint8_t>& image,unsigned width,const FontAtlas& font,const char* text,unsigned x,unsigned y){
    x&=~1u;unsigned w=(unsigned(std::strlen(text))*font.advance+5)&~1u;
    std::vector<uint8_t> alpha(size_t(w)*font.height);
    for(unsigned n=0;text[n];++n){auto& glyph=font.glyph(text[n]);for(unsigned yy=0;yy<font.height;++yy)for(unsigned xx=0;xx<font.cellWidth;++xx){
        auto& dest=alpha[size_t(yy)*w+n*font.advance+xx];dest=std::max(dest,glyph[size_t(yy)*font.cellWidth+xx]);
    }}
    for(unsigned yy=0;yy<font.height;++yy)for(unsigned xx=0;xx<w;xx+=2){
        auto* p=&image[(size_t(y+yy)*width+x+xx)*2];unsigned a=alpha[size_t(yy)*w+xx],b=alpha[size_t(yy)*w+xx+1],c=(a+b+1)/2;
        p[0]=mix(p[0],128,c);p[2]=mix(p[2],128,c);p[1]=mix(p[1],235,a);p[3]=mix(p[3],235,b);
    }
}
}
TimecodeBox audioMeterBox(unsigned width,unsigned height,unsigned position,TimecodeBox avoid){
    if(width<320||height<200||width%2)return {};
    auto& font=meterAtlas(width);unsigned padding=width>=1280?12:8,gap=width>=1280?8:6;
    unsigned w=width>=1280?400:240,h=font.height*3+gap+padding*2,mx=(width/20)&~1u,my=height/20;
    position=validTimecodePosition(position);bool top=position==0||position==1||position==4;
    unsigned x=position==0||position==3?mx:position==1||position==2?width-mx-w:(width-w)/2;
    if(w+2*mx>width||h+2*my>height)return {};
    TimecodeBox box{x&~1u,top?my:height-my-h,w,h};
    if(overlaps(box,avoid)){
        int64_t below=int64_t(avoid.y)+avoid.height+gap,above=int64_t(avoid.y)-gap-h;
        if(top&&below+h<=height-my)box.y=unsigned(below);
        else if(above>=my)box.y=unsigned(above);
        else if(below+h<=height-my)box.y=unsigned(below);
        else return {};
    }
    return box;
}
void overlayAudioMeters(std::vector<uint8_t>& image,unsigned width,unsigned height,
    const shuttle_output_audio::StereoMeters& meters,unsigned position,TimecodeBox avoid){
    if(image.size()!=size_t(width)*height*2)return;
    auto box=audioMeterBox(width,height,position,avoid);if(!box.width)return;
    auto& font=meterAtlas(width);bool hd=width>=1280;
    unsigned padding=hd?12:8,gap=hd?8:6,barHeight=hd?16:10,led=hd?10:8;
    for(unsigned y=box.y;y<box.y+box.height;++y)for(unsigned x=box.x;x<box.x+box.width;x+=2){
        auto* p=&image[(size_t(y)*width+x)*2];p[0]=(unsigned(p[0])+129)/2;p[2]=(unsigned(p[2])+129)/2;p[1]=(unsigned(p[1])+17)/2;p[3]=(unsigned(p[3])+17)/2;
    }
    unsigned barX=(box.x+padding+font.advance+gap+1)&~1u;
    unsigned ledX=(box.x+box.width-padding-led)&~1u,barWidth=(ledX-gap-barX)&~1u;
    const YUV green=rgb(.08,.85,.22,hd),amber=rgb(1,.78,.06,hd),red=rgb(1,.08,.08,hd);
    for(unsigned ch=0;ch<2;++ch){
        auto& state=meters.channel(ch);unsigned row=box.y+padding+ch*(font.height+gap);
        meterLabel(image,width,font,ch?"R":"L",box.x+padding,row);
        unsigned barY=row+(font.height-barHeight)/2;
        solid(image,width,barX,barY,barWidth,barHeight,{36,128,128});
        double level=std::max(0.0,std::min(1.0,(state.levelDB+60)/60));
        unsigned filled=(unsigned(level*barWidth))&~1u;
        for(unsigned x=0;x<filled;x+=2){double db=-60+60*double(x)/barWidth;solid(image,width,barX+x,barY,2,barHeight,db< -18?green:db< -6?amber:red);}
        if(state.peakDB> -60){unsigned peak=(unsigned(std::max(0.0,std::min(1.0,(state.peakDB+60)/60))*(barWidth-2)))&~1u;solid(image,width,barX+peak,barY,2,barHeight,{235,128,128});}
        solid(image,width,ledX,row+(font.height-led)/2,led,led,state.clip>0?red:YUV{40,128,128});
    }
    unsigned scaleY=box.y+padding+font.height*2+gap;
    meterLabel(image,width,font,"-60",barX,scaleY);
    unsigned endLabelWidth=6*font.advance+4;
    meterLabel(image,width,font,"0 dBFS",ledX+led-endLabelWidth,scaleY);
}
}
