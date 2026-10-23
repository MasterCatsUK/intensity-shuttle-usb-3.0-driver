// GPL-2.0-or-later. Original software scopes; no editor UI capture or private APIs.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include "Scopes.hpp"
#include "IdleScreen.hpp"
#include <algorithm>
#include <cmath>
#include <chrono>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
namespace shuttle_scopes {
RGB decode(uint8_t u,uint8_t y,uint8_t v,bool hd){double l=(int(y)-16)/219.,cb=(int(u)-128)/224.,cr=(int(v)-128)/224.;double kr=hd?.2126:.299,kb=hd?.0722:.114;double r=l+2*(1-kr)*cr,b=l+2*(1-kb)*cb,g=(l-kr*r-kb*b)/(1-kr-kb);return{r,g,b,l,cb,cr};}
Analysis::Analysis():vector(VectorSize*VectorSize){for(auto& w:wave)w.resize(Width*Height);}
void Analysis::update(const std::vector<uint8_t>& image,unsigned width,unsigned height){
 if(!width||width%2||image.size()!=size_t(width)*height*2)throw std::runtime_error("Invalid scope image");hd=width>720;columns=std::min(Width,width);for(auto& w:wave)w.resize(columns*Height);samples=0;for(auto& w:wave)std::fill(w.begin(),w.end(),0);for(auto& h:histogram)h.fill(0);std::fill(vector.begin(),vector.end(),0);
 unsigned stepX=1,stepY=std::max(1u,(height+359)/360);
 for(unsigned y=0;y<height;y+=stepY)for(unsigned x=0;x<width;x+=stepX){auto pair=(size_t(y)*width+(x&~1u))*2;auto c=decode(image[pair],image[pair+(x%2?3:1)],image[pair+2],hd);double values[]={c.y,c.r,c.g,c.b};unsigned column=x*columns/width;
  for(unsigned ch=0;ch<4;++ch){int row=std::max(0,std::min(int(Height-1),int(std::lround((1.2-values[ch])/1.4*(Height-1)))));++wave[ch][row*columns+column];if(ch){unsigned bin=unsigned(std::max(0,std::min(255,int(std::lround(values[ch]*255)))));++histogram[ch-1][bin];}}
  unsigned vx=unsigned(std::max(0,std::min(255,int(std::lround(127.5+c.cb*220))))),vy=unsigned(std::max(0,std::min(255,int(std::lround(127.5-c.cr*220)))));++vector[vy*VectorSize+vx];++samples;
 }
}
struct Rect{double x,y,w,h;};
struct Painter {
 unsigned width,height;double pixelAspect=1;std::vector<uint8_t> bgra;CGContextRef cg;CGColorSpaceRef colour;
 Painter(unsigned w,unsigned h):width(w),height(h),bgra(size_t(w)*h*4){for(size_t n=0;n<bgra.size();n+=4){bgra[n]=bgra[n+1]=bgra[n+2]=22;bgra[n+3]=255;}colour=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);cg=CGBitmapContextCreate(bgra.data(),w,h,8,w*4,colour,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);if(!cg)throw std::runtime_error("Cannot render scopes");CGContextTranslateCTM(cg,0,h);CGContextScaleCTM(cg,1,-1);}
 ~Painter(){if(cg)CGContextRelease(cg);if(colour)CGColorSpaceRelease(colour);}
 double font()const{return std::max(10.,height/65.);}
 void line(double x,double y,double xx,double yy,double gray=.28){CGContextSetRGBStrokeColor(cg,gray,gray,gray,1);CGContextSetLineWidth(cg,1);CGContextMoveToPoint(cg,x,y);CGContextAddLineToPoint(cg,xx,yy);CGContextStrokePath(cg);}
 void text(const char* value,double x,double y,double size=14){@autoreleasepool{NSString* string=@(value);CTFontRef font=CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,size,nullptr);CGColorRef c=CGColorCreateGenericRGB(.66,.66,.66,1);NSDictionary* attributes=@{(__bridge id)kCTFontAttributeName:(__bridge id)font,(__bridge id)kCTForegroundColorAttributeName:(__bridge id)c};NSAttributedString* a=[[NSAttributedString alloc] initWithString:string attributes:attributes];CTLineRef t=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)a);CGContextSaveGState(cg);CGContextTranslateCTM(cg,x,y);CGContextScaleCTM(cg,1,-1);CGContextSetTextMatrix(cg,CGAffineTransformIdentity);CGContextSetTextPosition(cg,0,0);CTLineDraw(t,cg);CGContextRestoreGState(cg);CFRelease(t);CGColorRelease(c);CFRelease(font);}}
 // Draw a continuous density image. Scaling a transparent phosphor raster rather
 // than isolated output pixels avoids the regular dot grid on large displays.
 void addDensity(std::vector<uint8_t>& pixels,const std::vector<uint32_t>& bins,unsigned w,unsigned h,unsigned red,unsigned green,unsigned blue){
  for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x){size_t n=size_t(y)*w+x;double count=0;for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){int xx=int(x)+dx,yy=int(y)+dy;if(xx>=0&&yy>=0&&xx<int(w)&&yy<int(h))count+=bins[size_t(yy)*w+xx]*(dx==0?2:1)*(dy==0?2:1)/16.;}if(!count)continue;double core=std::min(1.,std::log1p(count)*.22),alpha=std::min(1.,.46+std::sqrt(count)*.3);auto* p=&pixels[n*4];p[0]=uint8_t(std::min(255.,p[0]+(blue+(255-blue)*core)*alpha));p[1]=uint8_t(std::min(255.,p[1]+(green+(255-green)*core)*alpha));p[2]=uint8_t(std::min(255.,p[2]+(red+(255-red)*core)*alpha));p[3]=uint8_t(std::min(255.,p[3]+255*alpha));}
 }
 void drawDensity(std::vector<uint8_t>& pixels,unsigned w,unsigned h,Rect r){
  CGContextRef layer=CGBitmapContextCreate(pixels.data(),w,h,8,w*4,colour,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);if(!layer)throw std::runtime_error("Cannot draw scope trace");CGImageRef image=CGBitmapContextCreateImage(layer);CGContextSaveGState(cg);CGContextTranslateCTM(cg,r.x,r.y+r.h);CGContextScaleCTM(cg,1,-1);CGContextSetInterpolationQuality(cg,kCGInterpolationHigh);CGContextSetBlendMode(cg,kCGBlendModePlusLighter);CGContextDrawImage(cg,CGRectMake(0,0,r.w,r.h),image);CGContextRestoreGState(cg);CGImageRelease(image);CGContextRelease(layer);
 }
 void density(const std::vector<uint32_t>& bins,unsigned w,unsigned h,Rect r,unsigned red,unsigned green,unsigned blue){
  unsigned rw=std::min(w,std::max(32u,unsigned(std::ceil(r.w)))),rh=std::min(h,std::max(32u,unsigned(std::ceil(r.h))));
  const std::vector<uint32_t>* measured=&bins;std::vector<uint32_t> reduced;
  if(rw!=w||rh!=h){reduced.resize(size_t(rw)*rh);for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x)reduced[size_t(y*rh/h)*rw+x*rw/w]+=bins[size_t(y)*w+x];measured=&reduced;}
  std::vector<uint8_t> pixels(size_t(rw)*rh*4,0);addDensity(pixels,*measured,rw,rh,red,green,blue);drawDensity(pixels,rw,rh,r);
 }
 Rect graph(Rect tile,const char* title,bool levels=true){double f=font();text(title,tile.x+12,tile.y+f+10,f);Rect r{tile.x+48,tile.y+f+25,tile.w-64,tile.h-f-58};if(levels){CGContextSetRGBFillColor(cg,.115,.115,.115,1);CGContextFillRect(cg,CGRectMake(r.x,r.y,r.w,r.h));for(int value:{-20,0,25,50,75,100,120}){double yy=r.y+(120-value)/140.*r.h;line(r.x,yy,r.x+r.w,yy,value==0||value==100?.34:.20);char label[16];snprintf(label,sizeof(label),"%d",value);text(label,tile.x+8,yy+4,f*.8);}line(r.x,r.y,r.x,r.y+r.h);line(r.x+r.w,r.y,r.x+r.w,r.y+r.h);}return r;}
 void wave(const Analysis& a,Rect tile,View type){Rect r=graph(tile,type==View::Luma?"Waveform · Luma":type==View::Parade?"Waveform · RGB Parade":"Waveform · RGB Overlay");unsigned count=type==View::Luma?1:3;const unsigned colours[4][3]={{235,255,235},{255,120,120},{120,255,120},{140,170,255}};
  if(type==View::Overlay){std::vector<uint8_t> pixels(a.columns*Analysis::Height*4,0);for(unsigned ch=1;ch<=3;++ch)addDensity(pixels,a.wave[ch],a.columns,Analysis::Height,colours[ch][0],colours[ch][1],colours[ch][2]);drawDensity(pixels,a.columns,Analysis::Height,r);return;}
  for(unsigned c=0;c<count;++c){unsigned ch=type==View::Luma?0:c+1;double section=type==View::Parade?r.w/3:r.w,left=r.x+(type==View::Parade?c*section:0);if(type==View::Parade){line(left,r.y,left,r.y+r.h);text(c==0?"Red":c==1?"Green":"Blue",left+section*.42,r.y+r.h+font(),font()*.85);}density(a.wave[ch],a.columns,Analysis::Height,{left,r.y,section,r.h},colours[ch][0],colours[ch][1],colours[ch][2]);}
 }
 void histogram(const Analysis& a,Rect tile){Rect r=graph(tile,"Histogram · RGB",false);CGContextSetRGBFillColor(cg,.115,.115,.115,1);CGContextFillRect(cg,CGRectMake(r.x,r.y,r.w,r.h));uint32_t maximum=1;for(auto& h:a.histogram)for(auto n:h)maximum=std::max(maximum,n);for(unsigned i=0;i<=4;++i){double x=r.x+i*r.w/4;line(x,r.y,x,r.y+r.h,.24);char label[12];snprintf(label,sizeof(label),"%u",i*25);text(label,x-(i==4?font()*1.6:4),r.y+r.h+font(),font()*.85);}for(unsigned ch=0;ch<3;++ch){CGContextBeginPath(cg);CGContextMoveToPoint(cg,r.x,r.y+r.h);for(unsigned bin=0;bin<256;++bin)CGContextAddLineToPoint(cg,r.x+bin*r.w/255,r.y+r.h-double(a.histogram[ch][bin])/maximum*r.h);CGContextAddLineToPoint(cg,r.x+r.w,r.y+r.h);CGContextClosePath(cg);CGContextSetRGBFillColor(cg,ch==0?1:.4,ch==1?1:.4,ch==2?1:.4,.55);CGContextSetBlendMode(cg,kCGBlendModePlusLighter);CGContextFillPath(cg);}CGContextSetBlendMode(cg,kCGBlendModeNormal);}
 void vectorscope(const Analysis& a,Rect tile){
  text("Vectorscope 100%",tile.x+12,tile.y+font()+10,font());double par=pixelAspect;double side=std::min((tile.w-28)*par,tile.h-font()-28),cx=tile.x+tile.w/2,cy=tile.y+font()+20+side/2,radius=side*.46;
  CGContextSaveGState(cg);CGContextTranslateCTM(cg,cx,cy);CGContextScaleCTM(cg,1/par,1);CGContextTranslateCTM(cg,-cx,-cy);
  CGContextSetRGBFillColor(cg,.12,.12,.12,1);CGContextFillEllipseInRect(cg,CGRectMake(cx-radius,cy-radius,2*radius,2*radius));CGContextSetRGBStrokeColor(cg,.23,.23,.23,1);CGContextSetLineWidth(cg,2);CGContextStrokeEllipseInRect(cg,CGRectMake(cx-radius-5,cy-radius-5,2*radius+10,2*radius+10));
  // Hue ring follows the same Cb/Cr orientation as the measured trace.
  double kr=a.hd?.2126:.299,kb=a.hd?.0722:.114;
  for(unsigned i=0;i<360;++i){double angle=i*M_PI/180,cb=.5*cos(angle),cr=-.5*sin(angle),red=.5+2*(1-kr)*cr,blue=.5+2*(1-kb)*cb,green=(.5-kr*red-kb*blue)/(1-kr-kb);auto clamp=[](double x){return std::max(0.,std::min(1.,x));};CGContextSetRGBStrokeColor(cg,clamp(red),clamp(green),clamp(blue),1);CGContextSetLineWidth(cg,std::max(2.,side*.007));CGContextBeginPath(cg);CGContextAddArc(cg,cx,cy,radius,angle,angle+M_PI/178,0);CGContextStrokePath(cg);}
  const double colours[6][3]={{1,0,0},{1,0,1},{0,0,1},{0,1,1},{0,1,0},{1,1,0}};const char* labels[]={"R","MG","B","CY","G","YL"};double scale=side*.60;
  CGContextSetRGBStrokeColor(cg,.6,.6,.6,1);CGContextSetLineWidth(cg,1.2);
  for(unsigned c=0;c<6;++c){auto rgb=colours[c];double l=kr*rgb[0]+(1-kr-kb)*rgb[1]+kb*rgb[2],cb=(rgb[2]-l)/(2*(1-kb)),cr=(rgb[0]-l)/(2*(1-kr)),xx=cb*scale,yy=-cr*scale,box=std::max(5.,side*.022);CGContextSaveGState(cg);CGContextTranslateCTM(cg,cx+xx,cy+yy);CGContextRotateCTM(cg,atan2(yy,xx));CGContextStrokeRect(cg,CGRectMake(-box/2,-box/2,box,box));CGContextRestoreGState(cg);text(labels[c],cx+xx*.77-font()*.4,cy+yy*.77+font()*.35,font());}
  double span=256*scale/220.;density(a.vector,256,256,{cx-span/2,cy-span/2,span,span},255,250,235);CGContextRestoreGState(cg);
 }
};
struct Renderer::Impl{Analysis analysis;};
Renderer::Renderer():impl(new Impl){}Renderer::~Renderer()=default;
Raster Renderer::render(const std::vector<uint8_t>& source,unsigned sw,unsigned sh,unsigned width,unsigned height,View view,bool outputPixels){
 if(view==View::Video||width<320||height<240||width>3840||height>2160)throw std::runtime_error("Invalid scope canvas");
 impl->analysis.update(source,sw,sh);Painter p(width,height);if(outputPixels&&sw==720)p.pixelAspect=sh==486?.9:16./15.;p.text(impl->analysis.hd?"Rec. 709":"Rec. 601",12,std::max(14.,height/48.),p.font());double top=std::max(24.,height/30.);Rect all{0,top,double(width),height-top};
 if(view==View::FourUp){double w=width/2.,h=(height-top)/2.;p.wave(impl->analysis,{0,top,w,h},View::Parade);p.histogram(impl->analysis,{w,top,w,h});p.vectorscope(impl->analysis,{0,top+h,w,h});p.wave(impl->analysis,{w,top+h,w,h},View::Luma);p.line(w,top,w,height,.22);p.line(0,top+h,width,top+h,.22);}
 else if(view==View::Histogram)p.histogram(impl->analysis,all);else if(view==View::Vectorscope)p.vectorscope(impl->analysis,all);else p.wave(impl->analysis,all,view);
 return {width,height,std::move(p.bgra)};
}
void Renderer::replace(std::vector<uint8_t>& image,unsigned width,unsigned height,View view){
 if(view==View::Video)return;auto raster=render(image,width,height,width,height,view,true);
 if(!shuttle_idle::convertBGRA(raster.bgra.data(),width*4,width,height,width>720,image))throw std::runtime_error("Cannot convert scope picture");
}
// One coalescing worker per destination. Try-lock submission/cache reads keep
// allocation, analysis, CoreGraphics and colour conversion off USB callbacks.
struct AsyncRenderer::Impl {
 struct Key{unsigned w=0,h=0,rw=0,rh=0;View view=View::Video;bool native=false;bool operator==(const Key& b)const{return w==b.w&&h==b.h&&rw==b.rw&&rh==b.rh&&view==b.view&&native==b.native;}};
 std::mutex mutex;std::condition_variable changed;bool stop=false,pending=false;Key requested,ready;std::vector<uint8_t> source;std::shared_ptr<const Raster> cached,lastGood;Key lastKey;std::thread worker;
 std::atomic<uint64_t> completed{0};std::atomic<double> renderMS{0};
 Impl():worker([this]{run();}){}
 ~Impl(){{std::lock_guard<std::mutex> lock(mutex);stop=true;}changed.notify_one();worker.join();}
 void run(){Renderer renderer;std::unique_lock<std::mutex> lock(mutex);while(!stop){changed.wait(lock,[this]{return stop||pending;});if(stop)break;auto key=requested;auto image=std::move(source);pending=false;lock.unlock();Raster result;@autoreleasepool{auto start=std::chrono::steady_clock::now();try{if(key.native)result=renderer.render(image,key.w,key.h,key.rw,key.rh,key.view);else{renderer.replace(image,key.w,key.h,key.view);result={key.w,key.h,std::move(image)};}}catch(const std::exception& e){fprintf(stderr,"Scope render: %s\n",e.what());}renderMS=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();}lock.lock();if(key==requested&&!result.bgra.empty()){cached=std::make_shared<const Raster>(std::move(result));ready=key;++completed;}}}
 std::shared_ptr<const Raster> request(const std::vector<uint8_t>& image,Key key){
  {std::unique_lock<std::mutex> lock(mutex,std::try_to_lock);if(lock.owns_lock()){requested=key;source=image;pending=true;if(ready==key&&cached){lastGood=cached;lastKey=key;}changed.notify_one();}}
  return lastGood&&lastKey==key?lastGood:nullptr;
 }
};
AsyncRenderer::AsyncRenderer():impl(new Impl){}AsyncRenderer::~AsyncRenderer()=default;
bool AsyncRenderer::replace(std::vector<uint8_t>& image,unsigned w,unsigned h,View view){
 if(view==View::Video)return true;
 auto raster=impl->request(image,{w,h,w,h,view,false});if(raster){image=raster->bgra;return true;}shuttle_idle::black(image,w,h);return false;
}
std::shared_ptr<const Raster> AsyncRenderer::native(const std::vector<uint8_t>& image,unsigned sw,unsigned sh,unsigned width,unsigned height,View view){return impl->request(image,{sw,sh,width,height,view,true});}

uint64_t AsyncRenderer::completed()const{return impl->completed.load();}
double AsyncRenderer::renderMilliseconds()const{return impl->renderMS.load();}
}
