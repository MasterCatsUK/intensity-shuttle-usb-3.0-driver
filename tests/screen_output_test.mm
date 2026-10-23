// GPL-2.0-or-later. Offline pixel conversion/rendering; no window or device activation.
#define main UnusedScreenOutputMain
#include "../unified/src/output/ScreenOutput.mm"
#undef main
#include <cassert>
#import <objc/runtime.h>
static unsigned stopRequests=0;
static void fakeTerminate(id,SEL,id){++stopRequests;}
static std::vector<uint8_t> solid(unsigned w,unsigned h,uint8_t u,uint8_t y,uint8_t v){std::vector<uint8_t> pixels(size_t(w)*h*2);for(size_t n=0;n<pixels.size();n+=4){pixels[n]=u;pixels[n+1]=y;pixels[n+2]=v;pixels[n+3]=y;}return pixels;}
int main(){@autoreleasepool{
 [NSApplication sharedApplication];CIContext* context=[CIContext contextWithOptions:nil];
 for(unsigned m=0;m<6;++m){auto p=shuttle_output::profile(shuttle_output::Mode(m));
  auto red=solid(p.width,p.height,90,81,240),blue=solid(p.width,p.height,240,41,110);
  NSImage* first=monitorImage(context,red,p);assert(first);auto firstRep=[[NSBitmapImageRep alloc] initWithCGImage:[first CGImageForProposedRect:nullptr context:nil hints:nil]];
  NSColor* a=[[firstRep colorAtX:p.width/2 y:p.height/2] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];assert(a.redComponent>a.blueComponent+.3);
  NSImage* second=monitorImage(context,blue,p);assert(second);auto rep=[[NSBitmapImageRep alloc] initWithCGImage:[second CGImageForProposedRect:nullptr context:nil hints:nil]];
  NSColor* b=[[rep colorAtX:p.width/2 y:p.height/2] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];assert(b.blueComponent>b.redComponent+.3);
  // Old buffers remain owned independently when a freshly rendered edit arrives.
  red.assign(red.size(),0);a=[[firstRep colorAtX:3 y:3] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];assert(a.redComponent>a.blueComponent+.3);
  assert(CGImageGetWidth([second CGImageForProposedRect:nullptr context:nil hints:nil])==p.width);assert(fabs(second.size.width/second.size.height-(p.width*p.pixelAspect()/p.height))<.001);
  TimelineView* view=[[TimelineView alloc] initWithFrame:NSMakeRect(0,0,960,600)];view.picture=second;
  for(unsigned sizing=0;sizing<3;++sizing){view.sizing=sizing;auto bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];assert(bitmap.pixelsWide>=960&&fabs(double(bitmap.pixelsWide)/bitmap.pixelsHigh-1.6)<.001);auto centre=[[bitmap colorAtX:bitmap.pixelsWide/2 y:bitmap.pixelsHigh/2] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];assert(centre.blueComponent>centre.redComponent+.3);}
 }
 // Native scope RGB canvas is independent of the HDMI wire size.
 auto input=solid(1920,1080,128,235,128);shuttle_scopes::Renderer scopes;
 for(auto size:{std::make_pair(2560u,1440u),std::make_pair(3840u,2160u)}){
  auto raster=std::make_shared<shuttle_scopes::Raster>(scopes.render(input,1920,1080,size.first,size.second,shuttle_scopes::View::FourUp));
  NSImage* picture=nativeScopeImage(raster);assert(picture);raster.reset();
  CGImageRef cg=[picture CGImageForProposedRect:nullptr context:nil hints:nil];assert(CGImageGetWidth(cg)==size.first&&CGImageGetHeight(cg)==size.second);
 }
 // A monitor window covers frame (not visibleFrame), above menu-bar level,
 // with no global presentation/focus changes or fullscreen Space transition.
 auto presentation=NSApp.presentationOptions;NSScreen* display=NSScreen.screens.lastObject;
 if(display){TimelineWindow* window=fullscreenMonitorWindow(display);assert(NSEqualRects(window.frame,display.frame)&&window.styleMask==NSWindowStyleMaskBorderless&&window.level>NSMainMenuWindowLevel&&!window.hasShadow&&!window.isVisible&&!window.isKeyWindow);assert(window.canBecomeKeyWindow&&!window.canBecomeMainWindow&&NSApp.presentationOptions==presentation);
 Method stopMethod=class_getInstanceMethod(NSApplication.class,@selector(terminate:));IMP saved=method_setImplementation(stopMethod,(IMP)fakeTerminate);
 NSEvent* escape=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"\x1b" charactersIgnoringModifiers:@"\x1b" isARepeat:NO keyCode:53];[window keyDown:escape];assert(stopRequests==1);
 TimelineView* outputView=[[TimelineView alloc] initWithFrame:display.frame];NSMenu* menu=[outputView menuForEvent:nil];assert(menu.numberOfItems==1&&[menu.itemArray[0].title isEqual:@"Stop Virtual Shuttle"]&&menu.itemArray[0].target==NSApp&&menu.itemArray[0].action==@selector(terminate:));
 method_setImplementation(stopMethod,saved);[window close];}
 std::vector<int32_t> pcm(1920*8);for(unsigned f=0;f<1920;++f){pcm[f*8]=4194303;pcm[f*8+1]=1048576;}auto original=pcm;shuttle_listen::Output off(false);off.push(pcm);shuttle_output_audio::StereoMeters meters;meters.update(pcm,.04);assert(pcm==original&&fabs(meters.channel(0).levelDB+6.0206)<.001&&fabs(meters.channel(1).levelDB+18.0618)<.001);
 puts("PASS: all six modes refresh rendered pixels with independent ownership, SD pixel aspect, Fit/Fill/Stretch and L/R metering with local listening disabled; no USB or route writes.");
}}
