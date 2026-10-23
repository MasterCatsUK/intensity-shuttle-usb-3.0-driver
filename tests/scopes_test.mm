// GPL-2.0-or-later. Analytical SDR scope fixtures; no USB/CMIO/audio routing.
#include "../unified/src/output/Scopes.hpp"
#include <cassert>
#include <algorithm>
#include <chrono>
#include <cstdio>
static std::vector<uint8_t> solid(unsigned w,unsigned h,uint8_t y,uint8_t u=128,uint8_t v=128){std::vector<uint8_t> f(size_t(w)*h*2);for(size_t n=0;n<f.size();n+=4){f[n]=u;f[n+1]=y;f[n+2]=v;f[n+3]=y;}return f;}
int main(){@autoreleasepool{
 using namespace shuttle_scopes;
 for(bool hd:{false,true}){auto black=decode(128,16,128,hd),white=decode(128,235,128,hd),red=decode(90,81,240,false);assert(black.y==0&&black.r==0&&white.y==1&&white.r==1);assert(red.r>.99&&red.g<.01&&red.b<.01);auto super=decode(128,255,128,hd);assert(super.y>1.09);}
 for(unsigned w:{720u,1920u}){unsigned h=w==720?576:1080;Analysis a;for(unsigned y:{16u,235u}){auto f=solid(w,h,y);a.update(f,w,h);assert(a.samples>10000);for(unsigned channel=0;channel<3;++channel)assert(a.histogram[channel][y==16?0:255]==a.samples);assert(a.vector[128*256+128]==a.samples);unsigned row=unsigned(std::lround((1.2-(y==16?0:1))/1.4*(Analysis::Height-1)));uint64_t sum=0;for(unsigned x=0;x<a.columns;++x)sum+=a.wave[0][row*a.columns+x];assert(sum==a.samples);}
  auto source=solid(w,h,81,90,240);for(unsigned view=1;view<7;++view){Renderer r;auto f=source;auto start=std::chrono::steady_clock::now();r.replace(f,w,h,View(view));double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();assert(f.size()==source.size()&&f!=source);for(size_t n=0;n<f.size();n+=2){assert(f[n]>=16&&f[n]<=240&&f[n+1]>=16&&f[n+1]<=235);}printf("PASS: %ux%u scope%u %.2fms\n",w,h,view,ms);}
  // A flat white waveform must be continuous at output resolution, not a
  // sparse sampling grid when the analysis raster is enlarged to full HD.
  if(w==1920){auto white=solid(w,h,235);Renderer smooth;smooth.replace(white,w,h,View::Luma);unsigned widest=0;for(unsigned y=60;y<h-60;++y){unsigned lit=0;for(unsigned x=60;x<w-25;++x)if(white[(size_t(y)*w+x)*2+1]>140)++lit;widest=std::max(widest,lit);}assert(widest>(w-85)*.9);}
  Renderer pass;auto f=source;pass.replace(f,w,h,View::Video);assert(f==source);
 }
 auto stripe=solid(1920,1080,16);for(unsigned y=0;y<1080;++y)stripe[(size_t(y)*1920+1)*2+1]=235;
 Analysis detail;detail.update(stripe,1920,1080);assert(detail.columns==960&&detail.histogram[0][255]==360);
 puts("PASS: SDR black/white/superwhite, Rec601 red, histogram counts, luma positions, neutral vectorscope and all six scope renders at SD/HD; legal output and untouched Video mode.");
}}
