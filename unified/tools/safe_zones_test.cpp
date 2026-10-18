// Geometry and pixel regression, no devices/apps/preferences.
#include "../src/output/SafeZones.hpp"
#include <cassert>
#include <cmath>
#include <chrono>
#include <fstream>
using namespace shuttle_sink;
static bool Band(unsigned x,unsigned y,TimecodeBox r){
    unsigned left=r.x-2,top=r.y-2,right=r.x+r.width+2,bottom=r.y+r.height+2;
    return x>=left&&x<right&&y>=top&&y<bottom&&(x<left+6||x>=right-6||y<top+6||y>=bottom-6);
}
static std::vector<uint8_t> Picture(unsigned w,unsigned h){
    std::vector<uint8_t> result(size_t(w)*h*2);
    for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;x+=2){auto* p=&result[(size_t(y)*w+x)*2];p[0]=p[2]=128;p[1]=p[3]=(x/48+y/48)%2?180:80;}return result;
}
int main(int argc,char**argv){
    for(auto size:std::vector<std::pair<unsigned,unsigned>>{{320,200},{720,576},{720,486},{1920,1080}}){
        unsigned w=size.first,h=size.second;auto title=safeZoneBox(w,h,true),action=safeZoneBox(w,h,false);
        assert(title.x>action.x&&title.y>action.y&&title.width<action.width&&title.height<action.height);
        for(auto spec:std::vector<std::pair<TimecodeBox,double>>{{title,.8},{action,.9}}){
            assert(spec.first.x%2==0&&spec.first.width%2==0);
            assert(std::abs(double(spec.first.width)-w*spec.second)<=2&&std::abs(double(spec.first.height)-h*spec.second)<=1);
            assert(2*spec.first.x+spec.first.width==w&&2*spec.first.y+spec.first.height==h);
        }
        auto original=Picture(w,h);
        for(unsigned flags=0;flags<4;++flags){
            auto image=original;bool t=flags&1,a=flags&2;overlaySafeZones(image,w,h,t,a);unsigned changed=0;
            for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x){
                size_t n=(size_t(y)*w+x)*2;bool guide=(t&&Band(x,y,title))||(a&&Band(x,y,action));
                if(!guide)assert(image[n]==original[n]&&image[n+1]==original[n+1]);
                else{assert(image[n]>=16&&image[n]<=240&&image[n+1]>=16&&image[n+1]<=235);changed+=image[n]!=original[n]||image[n+1]!=original[n+1];}
            }
            assert(flags?changed>0:image==original);
            if(t){size_t n=(size_t(title.y)*w+w/2)*2;assert(image[n]==128&&image[n+2]==128&&image[n+1]>original[n+1]);}
            if(a){size_t n=(size_t(action.y)*w+w/2)*2;assert(image[n]<128);}
        }
    }
    auto image=Picture(1920,1080);
    if(argc==2){
        overlaySafeZones(image,1920,1080,true,true);
        std::ofstream ppm(argv[1],std::ios::binary);ppm<<"P6\n1920 1080\n255\n";
        for(size_t n=0;n<1920*1080;n+=2){
            double u=(double(image[n*2])-128)/224,v=(double(image[n*2+2])-128)/224;
            for(unsigned k=0;k<2;++k){double y=(double(image[(n+k)*2+1])-16)/219,r=y+1.5748*v,b=y+1.8556*u,g=(y-.2126*r-.0722*b)/.7152;
                auto byte=[](double value){return char(std::lround(std::max(0.0,std::min(1.0,value))*255));};char rgb[]={byte(r),byte(g),byte(b)};ppm.write(rgb,3);
            }
        }
    }
    auto begin=std::chrono::steady_clock::now();for(unsigned n=0;n<500;++n)overlaySafeZones(image,1920,1080,true,true);
    printf("PASS: 80/90 percent geometry, independent toggles and off identity at four sizes; guide-only pixel changes, pair alignment, white/yellow separation, legal range; HD average %.3f ms/frame\n",std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count()/500);
}
