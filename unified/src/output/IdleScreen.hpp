// GPL-2.0-or-later. Default HDMI picture while no editor frame is available.
#pragma once
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <Accelerate/Accelerate.h>
#include "OutputPacket.hpp"
#include "IdleTimer.hpp"
#include "MovieSource.hpp"
#include <memory>
#include <climits>
namespace shuttle_idle {
inline bool convertBGRA(const uint8_t* bytes,size_t stride,unsigned width,unsigned height,bool hd,std::vector<uint8_t>& picture){
    picture.resize(size_t(width)*height*2);
    vImage_ARGBToYpCbCr info{};vImage_YpCbCrPixelRange range={16,128,235,240,255,0,255,0};
    auto rc=vImageConvert_ARGBToYpCbCr_GenerateConversion(hd?kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2:kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4,&range,&info,kvImageARGB8888,kvImage422CbYpCrYp8,kvImageNoFlags);
    if(rc)return false;
    vImage_Buffer in{const_cast<uint8_t*>(bytes),height,width,stride},out{picture.data(),height,width,size_t(width)*2};
    const uint8_t map[4]={3,2,1,0};
    return vImageConvert_ARGB8888To422CbYpCrYp8(&in,&out,&info,map,kvImageNoFlags)==kvImageNoError;
}
inline void black(std::vector<uint8_t>& image,unsigned w,unsigned h){image.resize(size_t(w)*h*2);for(size_t i=0;i<image.size();i+=4){image[i]=image[i+2]=128;image[i+1]=image[i+3]=16;}}
inline void bars(std::vector<uint8_t>& image,unsigned w,unsigned h){
    static const uint8_t rgb[8][3]={{255,255,255},{255,255,0},{0,255,255},{0,255,0},{255,0,255},{255,0,0},{0,0,255},{0,0,0}};
    std::vector<uint8_t> bgra(size_t(w)*h*4);
    for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x){auto c=rgb[x*8/w];auto* p=bgra.data()+(size_t(y)*w+x)*4;p[0]=c[2];p[1]=c[1];p[2]=c[0];p[3]=255;}
    if(!convertBGRA(bgra.data(),size_t(w)*4,w,h,w>720,image))black(image,w,h);
}

class Screen {
    NSInteger choice=0;
    std::vector<uint8_t> still;
    Timer timer;
    std::unique_ptr<MovieSource> movie;std::string moviePath;shuttle_output::Mode movieMode;shuttle_output::Sizing sizing=shuttle_output::Sizing::Fit;unsigned movieFrame=0,movieFrames=1;
public:
    explicit Screen(shuttle_output::Mode mode,CFStringRef domain=CFSTR("local.shuttle.camera")){@autoreleasepool{
        CFPreferencesAppSynchronize(domain);
        auto raw=CFPreferencesCopyAppValue(CFSTR("HDMIIdleScreen"),domain);
        if(raw){if(CFGetTypeID(raw)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)raw,kCFNumberNSIntegerType,&choice);CFRelease(raw);}
        if(choice<0||choice>4)choice=0;
        long sizingRaw=0;auto sizeValue=CFPreferencesCopyAppValue(CFSTR("HDMIIdleSizing"),domain);if(sizeValue){if(CFGetTypeID(sizeValue)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)sizeValue,kCFNumberLongType,&sizingRaw);CFRelease(sizeValue);}sizing=shuttle_output::sizingValue(sizingRaw);movieMode=mode;
        int delay=120;
        auto delayRaw=CFPreferencesCopyAppValue(CFSTR("HDMIIdleDelaySeconds"),domain);
        if(delayRaw){if(CFGetTypeID(delayRaw)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)delayRaw,kCFNumberIntType,&delay);CFRelease(delayRaw);}
        if(delay!=-1&&delay!=0&&delay!=30&&delay!=60&&delay!=120&&delay!=300&&delay!=600)delay=120;
        timer=Timer(delay);
        auto p=shuttle_output::profile(mode);black(still,p.width,p.height);
        if(choice==2)bars(still,p.width,p.height);
        if(choice==4){
            auto value=CFPreferencesCopyAppValue(CFSTR("HDMIIdleMovie"),domain);
            if(value&&CFGetTypeID(value)==CFStringGetTypeID())moviePath=[(__bridge NSString*)value UTF8String];if(value)CFRelease(value);
            try{if(moviePath.empty())return;movie.reset(new MovieSource(moviePath,mode,sizing,false));movieFrames=std::max(1U,unsigned(std::min(double(UINT_MAX),std::ceil(movie->duration()*p.rateNom/p.rateDen))));std::vector<int32_t> silent;movie->read(0,still,silent);movieFrame=0;}catch(const std::exception& e){movie.reset();black(still,p.width,p.height);fprintf(stderr,"Idle movie unavailable: %s\n",e.what());}
            return;
        }
        if(choice!=3)return;
        auto pathRaw=CFPreferencesCopyAppValue(CFSTR("HDMIIdlePicture"),domain);
        NSString* path=pathRaw&&CFGetTypeID(pathRaw)==CFStringGetTypeID()?(__bridge NSString*)pathRaw:nil;
        NSData* data=path?[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil]:nil;
        if(data.length&&data.length<=4*1024*1024){
            CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,nullptr);
            CGImageRef image=source?CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize:@1920}):nullptr;
            if(image){
                std::vector<uint8_t> bgra(size_t(p.width)*p.height*4,0);CGColorSpaceRef colour=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                CGContextRef context=CGBitmapContextCreate(bgra.data(),p.width,p.height,8,p.width*4,colour,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
                if(context){
                    CGContextSetRGBFillColor(context,0,0,0,1);CGContextFillRect(context,CGRectMake(0,0,p.width,p.height));
                    double w=CGImageGetWidth(image),h=CGImageGetHeight(image),par=p.pixelAspect();
                    auto fitted=shuttle_output::destination(w,h,p.width,p.height,par,sizing);
                    CGContextSetInterpolationQuality(context,kCGInterpolationHigh);CGContextDrawImage(context,CGRectMake(fitted.x,fitted.y,fitted.width,fitted.height),image);
                    if(!convertBGRA(bgra.data(),p.width*4,p.width,p.height,p.width>720,still))black(still,p.width,p.height);
                    CGContextRelease(context);
                }
                CGColorSpaceRelease(colour);CGImageRelease(image);
            }
            if(source)CFRelease(source);
        }
        if(pathRaw)CFRelease(pathRaw);
    }}
    void apply(std::vector<uint8_t>& picture,bool hasLast){
        if(movie){try{std::vector<int32_t> silent;if(movieFrame){if(movieFrame>=movieFrames){movie.reset(new MovieSource(moviePath,movieMode,sizing,false));movieFrame=0;}movie->read(movieFrame,still,silent);}++movieFrame;}catch(const std::exception& e){movie.reset();auto p=shuttle_output::profile(movieMode);black(still,p.width,p.height);fprintf(stderr,"Idle movie stopped: %s\n",e.what());}}
        if(choice!=0||!hasLast)picture=still;
    }
    bool update(std::vector<uint8_t>& picture,bool freshFrame,bool hasLast,Timer::Clock::time_point now=Timer::Clock::now()){
        bool expired=timer.idle(freshFrame,now);if(expired)apply(picture,hasLast);return expired;
    }

};
}
