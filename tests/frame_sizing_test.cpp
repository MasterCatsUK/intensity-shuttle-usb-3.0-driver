// Pure geometry/connector fixtures: no media, displays, hardware or preferences.
#include "FrameSizing.hpp"
#include "ExtendedDisplaySize.hpp"
#include <cassert>
#include <cstdio>
static bool near(double a,double b){return std::abs(a-b)<0.001;}
int main(){
    for(unsigned m=0;m<6;++m){auto mode=shuttle_output::Mode(m);auto size=shuttle_output::extendedDisplaySize(mode);bool sd=m==0||m==3;assert(size.width==(sd?1024:1920)&&size.height==(sd?768:1080));auto p=shuttle_output::profile(mode);auto fit=shuttle_output::destination(size.width,size.height,p.width,p.height,p.pixelAspect(),shuttle_output::Sizing::Fit);assert(std::abs(fit.x)<0.01&&std::abs(fit.y)<0.01&&std::abs(fit.width-p.width)<0.01&&std::abs(fit.height-p.height)<0.01);}
using namespace shuttle_output;
    auto r=destination(4,3,1920,1080,1,Sizing::Fit);assert(near(r.x,240)&&near(r.width,1440)&&near(r.height,1080));
    r=destination(4,3,1920,1080,1,Sizing::Fill);assert(near(r.x,0)&&near(r.y,-180)&&near(r.width,1920)&&near(r.height,1440));
    r=destination(4,3,1920,1080,1,Sizing::Stretch);assert(near(r.x,0)&&near(r.y,0)&&near(r.width,1920)&&near(r.height,1080));
    r=destination(4,3,720,576,16.0/15,Sizing::Fit);assert(near(r.width,720)&&near(r.height,576));
    r=destination(4,3,720,486,.9,Sizing::Fit);assert(near(r.width,720)&&near(r.height,486));
    r=crop(2560,1440,720,576,16.0/15,Sizing::Fill);assert(near(r.width,1920)&&near(r.x,320)&&near(r.height,1440));
    assert(destination(0,1,1920,1080,1,Sizing::Fit).width==0);
    for(unsigned c=0;c<4;++c)for(unsigned m=0;m<6;++m){auto connector=static_cast<Connector>(c);bool sd=m==0||m==3;assert(connectorSupports(connector,m)==(c==0||c==3||sd));assert(connectorSupports(connector,compatibleMode(connector,m)));}
    assert(compatibleMode(Connector::SVideo,2)==0&&compatibleMode(Connector::Composite,5)==3);
    puts("PASS: fit/fill/stretch, PAL/NTSC pixel aspect, desktop crop, invalid dimensions and connector mode limits");
}
