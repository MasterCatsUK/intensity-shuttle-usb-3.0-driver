// Rendering geometry, transparency and glyph antialiasing; no devices/apps.
#include "../src/output/Timecode.hpp"
#include <cassert>
#include <chrono>
#include <fstream>
using namespace shuttle_sink;
static std::vector<uint8_t> Picture(unsigned w,unsigned h){
    std::vector<uint8_t> result(size_t(w)*h*2);
    for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;x+=2){
        auto* p=&result[(size_t(y)*w+x)*2];p[0]=80;p[2]=160;
        p[1]=p[3]=((x/24+y/24)%2)?180:80;
    }
    return result;
}
int main(int argc,char**argv){
    prepareTimecodeOverlay();Timecode code{1,1,23,45,12,0,25,0};
    for(auto size:std::vector<std::pair<unsigned,unsigned>>{{320,200},{720,576},{720,486},{1920,1080}}){
        unsigned w=size.first,h=size.second;
        for(unsigned position=0;position<6;++position){
            auto original=Picture(w,h),image=original;auto b=timecodeOverlayBox(w,h,code,position);
            assert(b.width&&b.height&&b.x%2==0&&b.x+b.width<=w&&b.y+b.height<=h);
            bool top=position==0||position==1||position==4;
            assert(top?b.y<h/2:b.y>h/2);
            if(position==0||position==3)assert(b.x<w/4);
            if(position==1||position==2)assert(b.x+b.width>w*3/4);
            if(position==4||position==5)assert(abs(int(2*b.x+b.width)-int(w))<=2);
            overlayTimecode(image,w,h,code,position);unsigned white=0,soft=0;
            for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x){
                size_t n=(size_t(y)*w+x)*2;bool inside=x>=b.x&&x<b.x+b.width&&y>=b.y&&y<b.y+b.height;
                if(!inside){assert(image[n]==original[n]&&image[n+1]==original[n+1]);continue;}
                unsigned dim=(original[n+1]+17)/2;
                assert(image[n+1]>=dim&&image[n+1]<=235);
                if(image[n+1]==235)++white;
                if(image[n+1]>dim&&image[n+1]<235)++soft;
            }
            // The padded corner has no text: exact 50% black, preserving
            // source contrast and chroma rather than an opaque black panel.
            size_t n=(size_t(b.y)*w+b.x)*2;
            assert(image[n+1]==(original[n+1]+17)/2&&image[n]==104&&image[n+2]==144);
            assert(white&&soft);
        }
    }
    assert(savedTimecodePosition(0)==5&&savedTimecodePosition(99)==5);
    for(unsigned p=0;p<6;++p)assert(savedTimecodePosition(p+1)==p);
    auto image=Picture(1920,1080);
    if(argc==2){
        for(unsigned p=0;p<6;++p){code.hours=p+1;overlayTimecode(image,1920,1080,code,p);}
        std::ofstream ppm(argv[1],std::ios::binary);ppm<<"P6\n1920 1080\n255\n";
        for(size_t n=0;n<1920*1080;++n){char c=image[n*2+1],rgb[]={c,c,c};ppm.write(rgb,3);}
    }
    auto begin=std::chrono::steady_clock::now();
    for(unsigned f=0;f<500;++f){code.frames=f%25;overlayTimecode(image,1920,1080,code,f%6);}
    double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count()/500;
    printf("PASS: six placements at four sizes, outside pixels unchanged, exact translucent blend, antialiased edges, saved-position compatibility; HD render average %.3f ms/frame\n",ms);
}
