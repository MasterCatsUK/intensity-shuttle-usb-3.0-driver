// GPL-2.0-or-later. Verify scaled geometry, colour-plane separation and row bounds.
#include "Scale422.hpp"
#include "VideoProfile.hpp"
#include <cassert>
#include <cstdio>
#include <chrono>
int main() {
    for(bool ntsc:{false,true}) for(bool wide:{false,true}) for(auto mode:{shuttle::OutputSize::Native,shuttle::OutputSize::SquarePixels,shuttle::OutputSize::Size1280x960,shuttle::OutputSize::Size1440x1080,shuttle::OutputSize::Size1280x720,shuttle::OutputSize::Size1920x1080}) {
        shuttle::CaptureSettings s;s.profile.ntsc=ntsc;s.widescreen=wide;s.outputSize=mode;
        unsigned w=s.outputWidth(),h=s.outputHeight(),sourceH=s.profile.height();
        unsigned iw=s.imageWidth(),ih=s.imageHeight(),ox=((w-iw)/2)&~1u,oy=(h-ih)/2;
        assert(iw<=w&&ih<=h&&iw%2==0);
        assert(mode==shuttle::OutputSize::Native || s.aspectH()==1 && s.aspectV()==1);
        shuttle::Scale422 scale(sourceH,w,h,iw,ih);
        std::vector<uint8_t> source(1440*sourceH),dest((w*2+32)*h+64,0xa5);size_t stride=w*2+32;
        for(uint8_t fieldLevel:{uint8_t(50),uint8_t(180)}) {
            for(size_t n=0;n<source.size();n+=4) { source[n]=60;source[n+1]=fieldLevel;source[n+2]=200;source[n+3]=fieldLevel; }
            assert(scale.write(source.data(),dest.data()+32,stride));
            for(unsigned y=0;y<h;++y) {
                auto row=dest.data()+32+y*stride;
                for(unsigned x=0;x<w*2;x+=4) {
                    bool picture=y>=oy&&y<oy+ih&&x/2>=ox&&x/2<ox+iw;
                    int u=picture?60:128,v=picture?200:128,level=picture?fieldLevel:16;
                    assert(abs(int(row[x])-u)<=1 && abs(int(row[x+2])-v)<=1);
                    assert(abs(int(row[x+1])-level)<=1 && abs(int(row[x+3])-level)<=1);
                }
                for(unsigned x=w*2;x<stride;++x) assert(row[x]==0xa5);
            }
            for(unsigned x=0;x<32;++x) assert(dest[x]==0xa5 && dest[dest.size()-1-x]==0xa5);
        }
        // Native mode must retain every original sample, including changing Y/chroma.
        if(mode==shuttle::OutputSize::Native) {
            for(size_t n=0;n<source.size();++n) source[n]=uint8_t(n*37);
            assert(scale.write(source.data(),dest.data()+32,stride));
            for(unsigned y=0;y<h;++y) assert(!memcmp(source.data()+y*1440,dest.data()+32+y*stride,1440));
        }
        assert(!scale.write(source.data(),dest.data(),w*2-1));
        printf("PASS: %s %s %ux%u, independent U/Y/V planes, distinct fields, stride/guard bounds\n",ntsc?"NTSC":"PAL",wide?"16:9":"4:3",w,h);
    }
    // A coloured half-image catches U/V swapping and accidental packed-byte scaling.
    shuttle::Scale422 scale(576,768,576);std::vector<uint8_t> src(1440*576),dst(1536*576);
    for(unsigned y=0;y<576;++y) for(unsigned x=0;x<360;++x) { auto p=src.data()+y*1440+x*4;bool left=x<180;p[0]=left?40:180;p[1]=p[3]=left?80:170;p[2]=left?210:70; }
    assert(scale.write(src.data(),dst.data(),1536));
    for(unsigned y:{0u,288u,575u}) for(unsigned x:{0u,80u,280u,380u}) { auto p=dst.data()+y*1536+x*4;bool left=x<192;assert(abs(int(p[0])-(left?40:180))<=1 && abs(int(p[2])-(left?210:70))<=1); }
    puts("PASS: coloured edges retain U/V ordering and picture halves");
}
