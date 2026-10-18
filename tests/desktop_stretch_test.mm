// GPL-2.0-or-later. Explicit live test; owns only a temporary virtual display.
// No USB, capture provider, audio route or production preference changes.
#import <Cocoa/Cocoa.h>
#include "../unified/src/ExtendedDisplay.mm"
#include "DesktopSource.hpp"
#include <cstdio>
#include <vector>
static void Pump(){NSEvent *e;NSDate *end=[NSDate dateWithTimeIntervalSinceNow:.04];while((e=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:end inMode:NSDefaultRunLoopMode dequeue:YES]))[NSApp sendEvent:e];[NSApp updateWindows];}
@interface Quadrants:NSView
@property BOOL phase;
@end
@implementation Quadrants
- (void)drawRect:(NSRect)dirty{CGFloat w=self.bounds.size.width/2,h=self.bounds.size.height/2;[NSColor.blueColor setFill];NSRectFill(NSMakeRect(0,0,w,h));[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(w,0,w,h));[(self.phase?NSColor.greenColor:NSColor.redColor) setFill];NSRectFill(NSMakeRect(0,h,w,h));[(self.phase?NSColor.redColor:NSColor.greenColor) setFill];NSRectFill(NSMakeRect(w,h,w,h));}
@end
static bool Red(const std::vector<uint8_t>& f,unsigned w,unsigned h,unsigned x,unsigned y){size_t p=(size_t(h*y/8)*w+(w*x/8&~1U))*2;return f[p+2]>200&&f[p+1]>40&&f[p+1]<100;}
static bool Green(const std::vector<uint8_t>& f,unsigned w,unsigned h,unsigned x,unsigned y){size_t p=(size_t(h*y/8)*w+(w*x/8&~1U))*2;return f[p+2]<70&&f[p+1]>120;}
static bool Blue(const std::vector<uint8_t>& f,unsigned w,unsigned h,unsigned x,unsigned y){size_t p=(size_t(h*y/8)*w+(w*x/8&~1U))*2;return f[p]>200&&f[p+1]<70;}
static bool White(const std::vector<uint8_t>& f,unsigned w,unsigned h,unsigned x,unsigned y){size_t p=(size_t(h*y/8)*w+(w*x/8&~1U))*2;return f[p+1]>210;}
int main(int argc,char**argv){@autoreleasepool{
 auto outputMode=argc>1?shuttle_output::Mode(atoi(argv[1])):shuttle_output::Mode::HD1080p25;auto profile=shuttle_output::profile(outputMode);
 [NSApplication sharedApplication].activationPolicy=NSApplicationActivationPolicyAccessory;
 ShuttleExtendedDisplay *display=[ShuttleExtendedDisplay new];NSString *error=nil;if(![display startWidth:1920 height:1080 error:&error]){fprintf(stderr,"%s\n",error.UTF8String);return 1;}
 unsigned identifier=display.displayID;for(int k=0;k<15;++k)Pump();
 CGRect initial=CGDisplayBounds(identifier);CGFloat initialMainHeight=CGRectGetMaxY(CGDisplayBounds(CGMainDisplayID()));
 NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(initial.origin.x,initialMainHeight-CGRectGetMaxY(initial),initial.size.width,initial.size.height) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];window.level=NSStatusWindowLevel;window.hasShadow=NO;window.opaque=YES;Quadrants *view=[Quadrants new];window.contentView=view;[window orderFront:nil];
 const unsigned widths[]={1920,1600,1600,1344,1344,1280,1280,1024,1024,960,800};const unsigned heights[]={1080,1200,900,1008,756,960,720,768,576,540,600};
 unsigned passed=0,missing=0;bool ok=true;
 CFArrayRef modes=CGDisplayCopyAllDisplayModes(identifier,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGDisplayShowDuplicateLowResolutionModes:@YES});
 try{
  DesktopSource source(identifier,outputMode,shuttle_output::Sizing::Stretch);
  for(unsigned i=0;i<11;++i){
   CGDisplayModeRef selected=nullptr;for(CFIndex m=0;m<CFArrayGetCount(modes);++m){auto candidate=(CGDisplayModeRef)CFArrayGetValueAtIndex(modes,m);if(CGDisplayModeGetWidth(candidate)==widths[i]&&CGDisplayModeGetHeight(candidate)==heights[i]){selected=candidate;break;}}
   if(!selected){printf("UNAVAILABLE: %u×%u\n",widths[i],heights[i]);++missing;continue;}
   if(CGDisplaySetDisplayMode(identifier,selected,nullptr)!=kCGErrorSuccess){ok=false;break;}
   for(int n=0;n<10;++n)Pump();CGRect b=CGDisplayBounds(identifier);CGFloat mainHeight=CGRectGetMaxY(CGDisplayBounds(CGMainDisplayID()));[window setFrame:NSMakeRect(b.origin.x,mainHeight-CGRectGetMaxY(b),b.size.width,b.size.height) display:YES];view.phase=i%2;[view setNeedsDisplay:YES];
   bool frameOK=false;for(unsigned n=0;n<70;++n){Pump();std::vector<uint8_t> frame;if(!source.read(frame))continue;if(frame.size()!=size_t(profile.width)*profile.height*2){ok=false;break;}bool top=view.phase?(Green(frame,profile.width,profile.height,1,1)&&Red(frame,profile.width,profile.height,7,1)):(Red(frame,profile.width,profile.height,1,1)&&Green(frame,profile.width,profile.height,7,1));if(top&&Blue(frame,profile.width,profile.height,1,7)&&White(frame,profile.width,profile.height,7,7)){frameOK=true;break;}}
   printf("%s: live desktop%u×%u →%u×%u Stretch, all quadrants present\n",frameOK?"PASS":"FAIL",widths[i],heights[i],profile.width,profile.height);fflush(stdout);if(!frameOK){ok=false;break;}++passed;
  }
 }catch(const std::exception& e){fprintf(stderr,"%s\n",e.what());ok=false;}
 if(modes)CFRelease(modes);[window orderOut:nil];window=nil;[display stop];bool removed=false;for(int n=0;n<50&&!removed;++n){Pump();CGDirectDisplayID ids[32];uint32_t count=0;CGGetOnlineDisplayList(32,ids,&count);removed=true;for(unsigned k=0;k<count;++k)if(ids[k]==identifier)removed=false;}
 printf("RESULT: %u modes passed; %u unavailable; display removed=%s\n",passed,missing,removed?"yes":"no");return ok&&passed==11&&removed?0:2;
}}
