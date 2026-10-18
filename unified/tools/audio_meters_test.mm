// Synthetic outgoing PCM and offline pixels only; no devices or preferences.
#include "../src/output/AudioMeters.hpp"
#include <cassert>
#include <chrono>
#include <fstream>
using namespace shuttle_output_audio;
using namespace shuttle_sink;
static std::vector<int32_t> Signal(unsigned frames,int32_t left,int32_t right){
    std::vector<int32_t> pcm(size_t(frames)*8,8388607);
    for(unsigned n=0;n<frames;++n){pcm[n*8]=n%2?-left:left;pcm[n*8+1]=n%2?-right:right;}return pcm;
}
static bool Overlap(TimecodeBox a,TimecodeBox b){return a.x<b.x+b.width&&b.x<a.x+a.width&&a.y<b.y+b.height&&b.y<a.y+a.height;}
static std::vector<uint8_t> Picture(unsigned w,unsigned h){
    std::vector<uint8_t> result(size_t(w)*h*2);
    for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;x+=2){auto* p=&result[(size_t(y)*w+x)*2];p[0]=p[2]=128;p[1]=p[3]=(x/24+y/24)%2?180:80;}return result;
}
int main(int argc,char**argv){
    for(auto rate:std::vector<std::pair<unsigned,unsigned>>{{25,1},{30000,1001}}){
        double dt=double(rate.second)/rate.first;unsigned frames=unsigned(48000*dt);
        auto pcm=Signal(frames,4194303,1048576),original=pcm;StereoMeters m;m.update(pcm,dt);
        assert(std::abs(m.channel(0).levelDB+6.0206)<.001&&std::abs(m.channel(1).levelDB+18.0618)<.001&&pcm==original);
        double peak=m.channel(0).peakDB;m.update({},dt);assert(m.channel(0).levelDB<peak&&m.channel(0).peakDB==peak);
        for(unsigned n=0;n<100;++n)m.update({},dt);
        assert(m.channel(0).levelDB==-60&&m.channel(0).peakDB<peak);
        auto clipped=Signal(frames,8388607,0);clipped[0]=-8388608;m.update(clipped,dt);
        assert(m.channel(0).levelDB==0&&m.channel(0).clip>0&&m.channel(1).clip==0);
        for(unsigned n=0;n<unsigned(std::ceil(1.2/dt));++n)m.update({},dt);
        assert(m.channel(0).clip==0);m.reset();assert(m.channel(0).levelDB==-60&&m.channel(0).peakDB==-60);
    }
    assert(savedMeterPosition(0)==2&&savedMeterPosition(100)==2);
    StereoMeters m;m.update(Signal(1920,4194303,1048576),.04);prepareTimecodeOverlay();
    Timecode code{1,1,23,45,12,0,25,0};
    for(auto size:std::vector<std::pair<unsigned,unsigned>>{{320,200},{720,576},{720,486},{1920,1080}}){
        unsigned w=size.first,h=size.second;
        for(unsigned pos=0;pos<6;++pos){
            auto box=audioMeterBox(w,h,pos);assert(box.width&&box.height&&box.x%2==0&&box.x+box.width<=w&&box.y+box.height<=h);
            for(unsigned tc=0;tc<6;++tc){auto avoid=timecodeOverlayBox(w,h,code,tc);auto b=audioMeterBox(w,h,pos,avoid);assert(b.width&&b.y+b.height<=h&&!Overlap(b,avoid));}
            auto original=Picture(w,h),image=original;overlayAudioMeters(image,w,h,m,pos);
            unsigned changed=0;
            for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x){
                size_t n=(size_t(y)*w+x)*2;bool inside=x>=box.x&&x<box.x+box.width&&y>=box.y&&y<box.y+box.height;
                if(!inside)assert(image[n]==original[n]&&image[n+1]==original[n+1]);
                else{assert(image[n]>=16&&image[n]<=240&&image[n+1]>=16&&image[n+1]<=235);changed+=image[n]!=original[n]||image[n+1]!=original[n+1];}
            }
            assert(changed);
        }
    }
    if(argc==2){
        auto image=Picture(1920,1080);
        for(unsigned pos=0;pos<6;++pos){code.hours=pos+1;overlayTimecode(image,1920,1080,code,pos);overlayAudioMeters(image,1920,1080,m,pos,timecodeOverlayBox(1920,1080,code,pos));}
        std::ofstream ppm(argv[1],std::ios::binary);ppm<<"P6\n1920 1080\n255\n";
        for(size_t n=0;n<1920*1080;n+=2){
            double u=(double(image[n*2])-128)/224,v=(double(image[n*2+2])-128)/224;
            for(unsigned k=0;k<2;++k){double y=(double(image[(n+k)*2+1])-16)/219;
                double r=y+1.5748*v,b=y+1.8556*u,g=(y-.2126*r-.0722*b)/.7152;
                auto byte=[](double value){return char(std::lround(std::max(0.0,std::min(1.0,value))*255));};
                char rgb[]={byte(r),byte(g),byte(b)};ppm.write(rgb,3);
            }
        }
    }
    auto image=Picture(1920,1080);auto begin=std::chrono::steady_clock::now();
    for(unsigned frame=0;frame<500;++frame)overlayAudioMeters(image,1920,1080,m,frame%6);
    printf("PASS: independent L/R dBFS, signed/full-scale PCM, no PCM changes, PAL/NTSC decay/hold/clip/reset; six positions/four sizes, timecode collision avoidance and legal pixels; HD average %.3f ms/frame\n",std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count()/500);
}
