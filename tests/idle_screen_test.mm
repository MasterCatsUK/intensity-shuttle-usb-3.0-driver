// GPL-2.0-or-later. Isolated preferences; no capture, USB, editor or production preference access.
#include "IdleScreen.hpp"
#include <cassert>
int main(){@autoreleasepool{
    CFStringRef domain=CFSTR("local.shuttle.test.idle36");
    auto set=[&](int value){auto n=CFNumberCreate(nullptr,kCFNumberIntType,&value);CFPreferencesSetAppValue(CFSTR("HDMIIdleScreen"),n,domain);CFRelease(n);CFPreferencesAppSynchronize(domain);};
    auto mode=shuttle_output::Mode::HD1080p25;
    std::vector<uint8_t> frame(1920*1080*2,77),held=frame;
    set(0);shuttle_idle::Screen hold(mode,domain);hold.apply(frame,true);assert(frame==held);hold.apply(frame,false);assert(frame[0]==128&&frame[1]==16);
    set(1);shuttle_idle::Screen black(mode,domain);frame=held;black.apply(frame,true);assert(frame[0]==128&&frame[1]==16);
    set(2);shuttle_idle::Screen bars(mode,domain);bars.apply(frame,true);assert(frame[1]==235&&frame[(1918)*2+1]==16);assert(frame[(300)*2+1]>200);
    set(3);shuttle_idle::Screen missing(mode,domain);missing.apply(frame,true);assert(frame[0]==128&&frame[1]==16);
    // A real imported 4:3 picture must fit a 16:9 HDMI frame, with black sidebars.
    std::vector<uint8_t> redImage(320*240*4);for(size_t i=0;i<redImage.size();i+=4){redImage[i+2]=redImage[i+3]=255;}
    auto colour=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);auto context=CGBitmapContextCreate(redImage.data(),320,240,8,1280,colour,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);auto image=CGBitmapContextCreateImage(context);
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".png"]];auto url=[NSURL fileURLWithPath:path];auto destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,nullptr);CGImageDestinationAddImage(destination,image,nullptr);assert(CGImageDestinationFinalize(destination));CFRelease(destination);CGImageRelease(image);CGContextRelease(context);CGColorSpaceRelease(colour);
    CFPreferencesSetAppValue(CFSTR("HDMIIdlePicture"),(__bridge CFStringRef)path,domain);CFPreferencesAppSynchronize(domain);
    shuttle_idle::Screen picture(mode,domain);picture.apply(frame,false);assert(frame[(540*1920+10)*2+1]==16);assert(abs(int(frame[(540*1920+960)*2+1])-63)<2);
    for(int sizing=1;sizing<3;++sizing){CFPreferencesSetAppValue(CFSTR("HDMIIdleSizing"),(__bridge CFNumberRef)@(sizing),domain);CFPreferencesAppSynchronize(domain);shuttle_idle::Screen filled(mode,domain);filled.apply(frame,false);assert(abs(int(frame[(540*1920+10)*2+1])-63)<2);}
    CFPreferencesSetAppValue(CFSTR("HDMIIdleSizing"),nullptr,domain);
    CFPreferencesSetAppValue(CFSTR("HDMIIdlePicture"),nullptr,domain);[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    // BGRA red -> limited-range BT.709 Y around63, Cb102, Cr240.
    std::vector<uint8_t> red={0,0,255,255,0,0,255,255},converted;assert(shuttle_idle::convertBGRA(red.data(),8,2,1,true,converted));assert(abs(int(converted[0])-102)<2&&abs(int(converted[1])-63)<2&&abs(int(converted[2])-240)<2);
    CFPreferencesSetAppValue(CFSTR("HDMIIdleScreen"),nullptr,domain);CFPreferencesAppSynchronize(domain);
    puts("PASS: hold/black/bars/imported picture Fit/Fill/Stretch/missing picture, HD colour matrix and BGRA channel order; isolated preferences");
}}
