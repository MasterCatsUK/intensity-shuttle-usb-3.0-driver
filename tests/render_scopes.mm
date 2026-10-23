// GPL-2.0-or-later. Original synthetic demonstration, no user footage/devices.
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#include "../unified/src/output/Scopes.hpp"
#include <cassert>
#include <cmath>
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=2)return 64;unsigned w=1920,h=1080;std::vector<uint8_t> f(w*h*2);
 for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;x+=2){double r=double(x)/(w-1),g=double(y)/(h-1),b=.5+.45*sin(x*.008+y*.004);double l=.2126*r+.7152*g+.0722*b;auto n=(size_t(y)*w+x)*2;f[n]=uint8_t(lround(128+224*(b-l)/1.8556));f[n+1]=f[n+3]=uint8_t(lround(16+219*l));f[n+2]=uint8_t(lround(128+224*(r-l)/1.5748));}
 shuttle_scopes::Renderer renderer;auto raster=renderer.render(f,w,h,2560,1440,shuttle_scopes::View::FourUp);
 CGDataProviderRef provider=CGDataProviderCreateWithData(nullptr,raster.bgra.data(),raster.bgra.size(),nullptr);CGColorSpaceRef colour=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);CGImageRef cg=CGImageCreate(raster.width,raster.height,8,32,raster.width*4,colour,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little,provider,nullptr,false,kCGRenderingIntentDefault);CGColorSpaceRelease(colour);CGDataProviderRelease(provider);assert(cg);
 NSURL* url=[NSURL fileURLWithPath:@(argv[1])];CGImageDestinationRef out=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,nullptr);assert(out);CGImageDestinationAddImage(out,cg,nullptr);assert(CGImageDestinationFinalize(out));CFRelease(out);CGImageRelease(cg);return 0;
}}
