// Playback must never wait for scope analysis/rasterisation. No device access.
#include "../unified/src/output/Scopes.hpp"
#include <cassert>
#include <chrono>
#include <thread>
#include <cstdio>
static std::vector<uint8_t> solid(unsigned w,unsigned h,uint8_t y){std::vector<uint8_t> f(size_t(w)*h*2);for(size_t n=0;n<f.size();n+=4){f[n]=f[n+2]=128;f[n+1]=f[n+3]=y;}return f;}
int main(){@autoreleasepool{
 using namespace shuttle_scopes;unsigned w=1920,h=1080;auto source=solid(w,h,235);AsyncRenderer worker;
 auto video=source;assert(worker.replace(video,w,h,View::Video)&&video==source&&worker.completed()==0);
 double worst=0;std::vector<uint8_t> got;unsigned ready=0;auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
 for(unsigned n=0;n<100;++n){got=source;auto before=std::chrono::steady_clock::now();bool ok=worker.replace(got,w,h,View::FourUp);worst=std::max(worst,std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-before).count());assert(got!=source&&got.size()==source.size());if(ok)++ready;assert(std::chrono::steady_clock::now()<deadline);std::this_thread::sleep_for(std::chrono::milliseconds(4));}
 assert(ready>50&&worker.completed()>5);Renderer direct;auto expected=source;direct.replace(expected,w,h,View::FourUp);assert(got==expected);
 // A mode switch cannot return a cached picture belonging to the previous view.
 auto changed=source;bool immediate=worker.replace(changed,w,h,View::Vectorscope);assert(!immediate);auto previous=got;
 do{std::this_thread::sleep_for(std::chrono::milliseconds(2));changed=source;assert(std::chrono::steady_clock::now()<deadline);}while(!worker.replace(changed,w,h,View::Vectorscope));assert(changed!=previous);
 std::shared_ptr<const Raster> native;do{native=worker.native(source,w,h,2560,1440,View::FourUp);std::this_thread::sleep_for(std::chrono::milliseconds(2));assert(std::chrono::steady_clock::now()<deadline);}while(!native);
 assert(native->width==2560&&native->height==1440&&native->bgra.size()==size_t(2560)*1440*4);
 auto normal=source;assert(worker.replace(normal,w,h,View::Video)&&normal==source);
 printf("PASS: asynchronous scopes coalesce frames, hold last completed raster, reject stale view, and preserve Video. %llu renders; last %.2fms on worker, worst submission %.2fms.\n",(unsigned long long)worker.completed(),worker.renderMilliseconds(),worst);
}}
