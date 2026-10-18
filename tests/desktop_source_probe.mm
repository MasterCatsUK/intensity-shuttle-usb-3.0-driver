// Explicit live screen read, no USB/audio or permission request. Does not save the screen.
#include "DesktopSource.hpp"
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <thread>
#include <cstdio>
int main(){@autoreleasepool{
    if(!CGPreflightScreenCaptureAccess()){puts("SKIP: screen-recording permission has not been granted; no request was made.");return 77;}
    try{DesktopSource source(CGMainDisplayID(),shuttle_output::Mode::HD1080p25);std::vector<uint8_t> picture;
        for(unsigned n=0;n<100;++n){if(source.read(picture)){if(picture.size()!=1920*1080*2)return 2;puts("PASS: selected desktop delivered a full 1920×1080 UYVY frame; no screen image was saved.");return 0;}std::this_thread::sleep_for(std::chrono::milliseconds(50));}
        puts("FAIL: screen capture started but no frame arrived.");return 1;
    }catch(const std::exception& e){fprintf(stderr,"Desktop probe: %s\n",e.what());return 1;}
}}
