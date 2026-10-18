// Explicit reversible live probe: creates one virtual display and a test window.
// No USB, audio routing, file capture or existing-display configuration changes.
#import <Cocoa/Cocoa.h>
#include "../unified/src/ExtendedDisplay.mm"
#include "DesktopSource.hpp"
#include "ExtendedDisplaySize.hpp"
#include <cstdio>
static void Pump(){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:0.05];NSEvent *event;while((event=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:end inMode:NSDefaultRunLoopMode dequeue:YES]))[NSApp sendEvent:event];[NSApp updateWindows];}
int main(int argc,char**argv){@autoreleasepool{
    [NSApplication sharedApplication].activationPolicy=NSApplicationActivationPolicyAccessory;
    if(![ShuttleExtendedDisplay available]){puts("SKIP: virtual-display selectors unavailable");return 77;}
    if(argc<2){puts("AVAILABLE: virtual-display selectors present; no display created.");return 0;}
    NSMutableSet *before=[NSMutableSet set];for(NSScreen *s in NSScreen.screens)[before addObject:s.deviceDescription[@"NSScreenNumber"]];
    ShuttleExtendedDisplay *display=[ShuttleExtendedDisplay new];NSString *error=nil;
    auto mode=argc>2?shuttle_output::Mode(atoi(argv[2])):shuttle_output::Mode::HD1080p25;auto size=shuttle_output::extendedDisplaySize(mode);auto profile=shuttle_output::profile(mode);
    if(![display startWidth:size.width height:size.height error:&error]){fprintf(stderr,"Virtual display: %s\n",error.UTF8String);return 1;}
    uint32_t identifier=display.displayID;printf("Created virtual display %u at%u×%u\n",identifier,size.width,size.height);fflush(stdout);
    for(unsigned n=0;n<20&&!CGDisplayIsActive(identifier);++n)Pump();
    if(!CGDisplayIsActive(identifier)||CGDisplayMirrorsDisplay(identifier)!=kCGNullDirectDisplay){[display stop];return 2;}
    for(unsigned n=0;n<10;++n)Pump();
    CGRect bounds=CGDisplayBounds(identifier);CGFloat mainHeight=CGRectGetMaxY(CGDisplayBounds(CGMainDisplayID()));
    fprintf(stderr,"CG bounds %.0f %.0f %.0f %.0f\n",bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height);
    if(bounds.size.width!=size.width||bounds.size.height!=size.height){fprintf(stderr,"FAIL: macOS restored an unexpected desktop mode\n");[display stop];return 5;}
    NSRect target=NSMakeRect(bounds.origin.x,mainHeight-CGRectGetMaxY(bounds),bounds.size.width,bounds.size.height);
    NSWindow *window=[[NSWindow alloc] initWithContentRect:target styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];window.backgroundColor=NSColor.redColor;window.hasShadow=NO;window.opaque=YES;window.level=NSStatusWindowLevel;[window orderFront:nil];
    bool captured=false;
    try{DesktopSource source(identifier,mode);std::vector<uint8_t> frame;
        for(unsigned n=0;n<60;++n){Pump();if(source.read(frame)&&frame.size()==size_t(profile.width)*profile.height*2){size_t centre=(size_t(profile.height/2)*profile.width+profile.width/2)*2;if(frame[centre+3]>40&&frame[centre+3]<100&&frame[centre+2]>200){size_t edge=(size_t(profile.height/2)*profile.width+4)*2;fprintf(stderr,"Centre Y/Cr %u/%u; left edge Y/Cr %u/%u\n",frame[centre+3],frame[centre+2],frame[edge+3],frame[edge+2]);size_t top=(size_t(4)*profile.width+profile.width/2)*2;size_t bottom=(size_t(profile.height-5)*profile.width+profile.width/2)*2;captured=frame[edge+2]>160&&frame[top+2]>160&&frame[bottom+2]>160;if(captured)break;}}}
    }catch(const std::exception& e){fprintf(stderr,"Virtual capture: %s\n",e.what());}
    if(argc>3)for(unsigned n=0;n<unsigned(atoi(argv[3]))*20;++n)Pump();
    [window orderOut:nil];window=nil;[display stop];
    bool removed=false;for(unsigned n=0;n<40&&!removed;++n){Pump();CGDirectDisplayID active[32];uint32_t count=0;CGGetOnlineDisplayList(32,active,&count);removed=true;for(unsigned k=0;k<count;++k)if(active[k]==identifier)removed=false;}
    printf("%s: separate extended display, test-window capture=%s; removed=%s\n",captured&&removed?"PASS":"FAIL",captured?"yes":"no",removed?"yes":"no");return captured&&removed?0:4;
}}
