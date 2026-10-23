// GPL-2.0-or-later. 23 October 2026: a direct FCP timeline monitor on a Mac display.
// No USB, display reconfiguration or screen capture is performed by this helper.
#import <Cocoa/Cocoa.h>
#import <CoreImage/CoreImage.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include "OutputPacket.hpp"
#include "FrameSizing.hpp"
#include "SharedOutput.hpp"
#include "OutputAudio.hpp"
#include "AudioCursor.hpp"
#include "WireClock.hpp"
#include "AudioSyncPreference.hpp"
#include "IdleScreen.hpp"
#include "ListeningOutput.hpp"
#include "MirrorFrame.hpp"
#include "Scopes.hpp"
#include <csignal>
#include <memory>
#include <chrono>
static volatile sig_atomic_t screenInterrupted=0;
static void interruptScreen(int){screenInterrupted=1;}
static uint64_t screenHostNS(){return CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()),1000000000,kCMTimeRoundingMethod_Default).value;}
static int virtualPreferences(){
    shuttle_output_audio::readVirtualMonitorPreferences();
    Boolean exists=false;long offset=CFPreferencesGetAppIntegerValue(CFSTR("VirtualAudioOffsetMS"),CFSTR("local.shuttle.camera"),&exists);
    return shuttle_output_audio::clampAudioOffset(exists?int(offset):0);
}
static NSScreen* screenForID(CGDirectDisplayID id){for(NSScreen* screen in NSScreen.screens)if([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==id)return screen;return nil;}
// A dedicated monitor window covers only its selected display. Do not change
// NSApplication presentation options: Final Cut keeps its own menu bar/focus.
@interface TimelineWindow : NSWindow
@end
@implementation TimelineWindow
- (BOOL)canBecomeKeyWindow{return YES;}
- (BOOL)canBecomeMainWindow{return NO;}
- (NSRect)constrainFrameRect:(NSRect)frame toScreen:(NSScreen*)screen{return frame;}
- (void)keyDown:(NSEvent*)event{if(event.keyCode==53)[NSApp terminate:nil];else [super keyDown:event];}
- (void)cancelOperation:(id)sender{[NSApp terminate:nil];}
@end
static TimelineWindow* fullscreenMonitorWindow(NSScreen* selected){
    auto* window=[[TimelineWindow alloc] initWithContentRect:selected.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO screen:selected];
    window.title=@"Virtual Shuttle";window.backgroundColor=NSColor.blackColor;window.hasShadow=NO;window.movable=NO;window.restorable=NO;window.animationBehavior=NSWindowAnimationBehaviorNone;
    window.level=NSMainMenuWindowLevel+1;
    window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary|NSWindowCollectionBehaviorIgnoresCycle;
    window.ignoresMouseEvents=NO;window.releasedWhenClosed=NO;[window setFrame:selected.frame display:NO];return window;
}
@interface TimelineView : NSView
@property NSImage* picture;
@property NSInteger sizing;
@end
@implementation TimelineView
- (BOOL)isOpaque{return YES;}
- (void)mouseDown:(NSEvent*)event{[self.window makeKeyWindow];}
- (NSMenu*)menuForEvent:(NSEvent*)event{NSMenu* menu=[[NSMenu alloc] initWithTitle:@"Virtual Shuttle"];NSMenuItem* stop=[[NSMenuItem alloc] initWithTitle:@"Stop Virtual Shuttle" action:@selector(terminate:) keyEquivalent:@""];stop.target=NSApp;[menu addItem:stop];return menu;}
- (void)drawRect:(NSRect)dirty{
    [NSColor.blackColor setFill];NSRectFill(self.bounds);if(!self.picture)return;
    auto size=self.picture.size;auto r=shuttle_output::destination(size.width,size.height,self.bounds.size.width,self.bounds.size.height,1,shuttle_output::sizingValue(self.sizing));
    [self.picture drawInRect:NSMakeRect(r.x,r.y,r.width,r.height) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation:@(NSImageInterpolationHigh)}];
}
@end
static NSImage* monitorImage(CIContext* context,std::vector<uint8_t> pixels,shuttle_output::Profile p){
    if(pixels.size()!=size_t(p.width)*p.height*2)return nil;
    auto* storage=new std::vector<uint8_t>(std::move(pixels));CVPixelBufferRef buffer=nullptr;
    CVReturn status=CVPixelBufferCreateWithBytes(nullptr,p.width,p.height,kCVPixelFormatType_422YpCbCr8,storage->data(),p.width*2,[](void* ref,const void*){delete static_cast<std::vector<uint8_t>*>(ref);},storage,nullptr,&buffer);
    if(status){delete storage;return nil;}
    CVBufferSetAttachment(buffer,kCVImageBufferYCbCrMatrixKey,p.width==720?kCVImageBufferYCbCrMatrix_ITU_R_601_4:kCVImageBufferYCbCrMatrix_ITU_R_709_2,kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(buffer,kCVImageBufferColorPrimariesKey,p.width==720?(p.height==576?kCVImageBufferColorPrimaries_EBU_3213:kCVImageBufferColorPrimaries_SMPTE_C):kCVImageBufferColorPrimaries_ITU_R_709_2,kCVAttachmentMode_ShouldPropagate);
    CIImage* image=[CIImage imageWithCVPixelBuffer:buffer];CGImageRef cg=[context createCGImage:image fromRect:CGRectMake(0,0,p.width,p.height)];CVPixelBufferRelease(buffer);
    if(!cg)return nil;NSImage* result=[[NSImage alloc] initWithCGImage:cg size:NSMakeSize(p.width*p.pixelAspect(),p.height)];CGImageRelease(cg);return result;
}
// Native scope graphics never pass through HDMI's 8-bit 4:2:2 raster.
// The CG provider owns the completed worker frame for as long as NSImage needs it.
static NSImage* nativeScopeImage(std::shared_ptr<const shuttle_scopes::Raster> raster){
    if(!raster)return nil;auto* owned=new std::shared_ptr<const shuttle_scopes::Raster>(raster);
    CGDataProviderRef provider=CGDataProviderCreateWithData(owned,raster->bgra.data(),raster->bgra.size(),[](void* p,const void*,size_t){delete static_cast<std::shared_ptr<const shuttle_scopes::Raster>*>(p);});
    CGColorSpaceRef colour=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);CGImageRef cg=CGImageCreate(raster->width,raster->height,8,32,raster->width*4,colour,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little,provider,nullptr,false,kCGRenderingIntentDefault);CGColorSpaceRelease(colour);CGDataProviderRelease(provider);
    if(!cg)return nil;NSImage* result=[[NSImage alloc] initWithCGImage:cg size:NSMakeSize(raster->width,raster->height)];CGImageRelease(cg);return result;
}
static std::pair<unsigned,unsigned> scopeCanvas(NSView* view){
    double scale=view.window.backingScaleFactor?:1,w=view.bounds.size.width*scale,h=view.bounds.size.height*scale;
    double limit=std::min(1.,std::min(3840./std::max(1.,w),2160./std::max(1.,h)));
    return {std::max(320u,unsigned(std::lround(w*limit))),std::max(240u,unsigned(std::lround(h*limit)))};
}
@interface ScreenOutput : NSObject<NSApplicationDelegate> {
    std::unique_ptr<shuttle_sink::Reader> _video;
    std::unique_ptr<shuttle_output_audio::Reader> _audio;
    std::unique_ptr<shuttle_output_audio::LiveAudioOffset> _offset;
    std::unique_ptr<shuttle_idle::Screen> _idle;
    std::unique_ptr<shuttle_listen::Output> _listening;
    shuttle_output_audio::AudioCursor _audioCursor;
    shuttle_output_audio::StereoMeters _meters;
    shuttle_output_audio::VideoClockDomain _clock;
    uint64_t _generation,_nextNS,_startNS,_launchedNS,_frame;
    std::unique_ptr<shuttle_mirror::Feed> _mirror;shuttle_mirror::Frame _held;std::deque<shuttle_mirror::Frame> _pending;
    shuttle_scopes::AsyncRenderer _scopes;
}
@property unsigned mode;
@property BOOL premiere;
@property NSString* mirrorPath;
@property CGDirectDisplayID displayID;
@property NSWindow* window;
@property TimelineView* view;
@property CIContext* context;
@property NSTimer* timer;
@property int exitCode;
@property double testSeconds;
- (void)screenChanged:(id)sender;
@end
@implementation ScreenOutput
- (void)applicationDidFinishLaunching:(NSNotification*)note{
    NSScreen* selected=screenForID(self.displayID);if(!selected){fputs("Selected Mac display is unavailable. Choose another display.\n",stderr);exit(2);}
    try{
        if(self.mirrorPath.length)_mirror.reset(new shuttle_mirror::Feed(self.mirrorPath.UTF8String,false,self.mode));
        else {_video.reset(new shuttle_sink::Reader(self.mode,false,self.premiere?shuttle_sink::PremierePort:shuttle_sink::VirtualPort));_audio.reset(new shuttle_output_audio::Reader);}_offset.reset(new shuttle_output_audio::LiveAudioOffset(virtualPreferences(),virtualPreferences));
        _idle.reset(new shuttle_idle::Screen(shuttle_output::Mode(self.mode)));if(!_mirror)_listening.reset(new shuttle_listen::Output);
        shuttle_sink::prepareTimecodeOverlay();
    }catch(const std::exception& e){fprintf(stderr,"Virtual Shuttle: %s\n",e.what());exit(3);}
    self.context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];
    self.window=fullscreenMonitorWindow(selected);
    self.view=[[TimelineView alloc] initWithFrame:NSMakeRect(0,0,selected.frame.size.width,selected.frame.size.height)];self.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    Boolean exists=false;self.view.sizing=CFPreferencesGetAppIntegerValue(CFSTR("PlaybackSizing"),CFSTR("local.shuttle.camera"),&exists);
    self.window.contentView=self.view;[self.window orderFrontRegardless];[self.window displayIfNeeded];
    // Publish readiness only after the requested destination window exists.
    if(_mirror)_mirror->setReady(true);else _video->markOutputReady();_generation=UINT64_MAX;_nextNS=_startNS=_launchedNS=screenHostNS();
    self.timer=[NSTimer timerWithTimeInterval:.002 target:self selector:@selector(tick:) userInfo:nil repeats:YES];self.timer.tolerance=.0005;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    fprintf(stdout,self.premiere?"Premiere Mac ready on display %u; mode %u. Enable Mercury Transmit.\n":"Virtual Shuttle ready on Mac display %u; mode %u. Select Virtual Shuttle in Final Cut A/V Output.\n",self.displayID,self.mode);fflush(stdout);
}
- (void)screenChanged:(id)sender{
    NSScreen* selected=screenForID(self.displayID);
    if(!selected){fputs("Virtual Shuttle stopped: selected display was disconnected.\n",stderr);self.exitCode=2;[NSApp terminate:nil];return;}
    [self.window setFrame:selected.frame display:YES];
}
- (void)tick:(id)sender{@autoreleasepool{
    if(self.mirrorPath.length&&getppid()==1){[NSApp terminate:nil];return;}
    if(screenInterrupted){[NSApp terminate:nil];return;}
    uint64_t now=screenHostNS();if(self.testSeconds>0&&now-_launchedNS>=uint64_t(self.testSeconds*1e9)){[NSApp terminate:nil];return;}
    auto p=shuttle_output::profile(shuttle_output::Mode(self.mode));
    try{
        if(_mirror){if(!_mirror->alive()){[NSApp terminate:nil];return;}shuttle_mirror::Frame latest;if(_mirror->read(latest)){if(_pending.size()>=8)_pending.pop_front();_pending.push_back(std::move(latest));}}
        else {_video->pump(p.width,p.height);_audio->pump();}if(now<_nextNS)return;
        uint64_t step=1000000000ULL*p.rateDen/p.rateNom;
        if(now>_nextNS+2*step){_startNS=now;_frame=0;}
        _nextNS=_startNS+uint64_t(static_cast<unsigned __int128>(++_frame)*1000000000*p.rateDen/p.rateNom);
        std::vector<uint8_t> image;std::vector<int32_t> pcm;bool idle=false;shuttle_sink::Timecode code{};
        if(_mirror){
            while(!_pending.empty()&&(!_pending.front().hostNS||_pending.front().hostNS<=now)){_held=std::move(_pending.front());_pending.pop_front();}
            if(_held.image.empty())shuttle_idle::black(image,p.width,p.height);else {image=_held.image;pcm=_held.pcm;idle=_held.idle;code=_held.timecode;}
        }else {_video->read(image,p.width,p.height);
        if(_generation!=_video->generation){_generation=_video->generation;_clock=shuttle_output_audio::VideoClockDomain::Unknown;_meters.reset();}
        if(_video->acknowledge&&_clock==shuttle_output_audio::VideoClockDomain::Unknown)_clock=shuttle_output_audio::classifyPTS(_video->hostNS,now);
        bool relative=_clock==shuttle_output_audio::VideoClockDomain::Wire;
        uint64_t presentation=relative?now:_video->hostNS;
        uint64_t pts=presentation>shuttle_output_audio::OutputLatencyNS?presentation-shuttle_output_audio::OutputLatencyNS:0;
        uint64_t first=0;
        if(_clock!=shuttle_output_audio::VideoClockDomain::Unknown&&_audioCursor.take(relative||_video->acknowledge,pts,_video->generation,p.audioFrames(_frame),p.rateNom,p.rateDen,first))
            _audio->read(shuttle_output_audio::offsetAudioSample(first,_offset->milliseconds()),p.audioFrames(_frame),pcm);
        else pcm.assign(p.audioFrames(_frame)*8,0);
        idle=_idle->update(image,_video->acknowledge,_video->hasPicture());code=_video->timecode;
        if(_listening)_listening->push(pcm);
        }
        _meters.update(pcm,double(p.rateDen)/p.rateNom);
        const auto scopeView=shuttle_scopes::validView(shuttle_output_audio::monitorView.load());
        const bool pictureView=scopeView==shuttle_scopes::View::Video;
        if(!pictureView&&!idle){
            auto canvas=scopeCanvas(self.view);
            self.view.picture=nativeScopeImage(_scopes.native(image,p.width,p.height,canvas.first,canvas.second,scopeView));
        }else{
            if(pictureView){
                shuttle_sink::overlaySafeZones(image,p.width,p.height,shuttle_output_audio::titleSafeEnabled.load(),shuttle_output_audio::actionSafeEnabled.load());
                bool timecode=!idle&&shuttle_output_audio::timecodeOverlayEnabled.load();shuttle_sink::TimecodeBox avoid{};
                if(timecode){auto position=shuttle_output_audio::timecodeOverlayPosition.load();avoid=shuttle_sink::timecodeOverlayBox(p.width,p.height,code,position);shuttle_sink::overlayTimecode(image,p.width,p.height,code,position);}
                if(shuttle_output_audio::audioMetersEnabled.load())shuttle_sink::overlayAudioMeters(image,p.width,p.height,_meters,shuttle_output_audio::audioMetersPosition.load(),avoid);
            }
            self.view.picture=monitorImage(self.context,std::move(image),p);
        }
        self.view.needsDisplay=YES;[self.view displayIfNeeded];
        if(_video&&_video->acknowledge)_video->played(_video->sequence,screenHostNS(),_video->generation);
    }catch(const std::exception& e){fprintf(stderr,"Virtual Shuttle: %s\n",e.what());self.exitCode=1;[NSApp terminate:nil];}
}}
- (void)applicationWillTerminate:(NSNotification*)note{
    [self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];[self.window orderOut:nil];if(_mirror)_mirror->setReady(false);_mirror.reset();_video.reset();_audio.reset();_offset.reset();_listening.reset();_idle.reset();
}
@end
int main(int argc,const char**argv){@autoreleasepool{
    if(argc==2&&!strcmp(argv[1],"--list-displays")){for(NSScreen* screen in NSScreen.screens)printf("%u\t%s\t%.0fx%.0f\n",[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue],screen.localizedName.UTF8String,screen.frame.size.width,screen.frame.size.height);return 0;}
    bool tap=argc==5&&!strcmp(argv[1],"--tap");bool premiere=argc==4&&!strcmp(argv[1],"--premiere");if(tap||premiere){++argv;--argc;}
    if(argc<3||argc>4){fputs("Usage: ShuttleScreenOutput MODE_INDEX(0-5) DISPLAY_ID [TEST_SECONDS]\n",stderr);return 64;}
    char* end=nullptr;long mode=strtol(argv[1],&end,10);if(*end||mode<0||mode>=6)return 64;
    unsigned long id=strtoul(argv[2],&end,10);if(*end||!id||id>UINT32_MAX)return 64;
    signal(SIGINT,interruptScreen);signal(SIGTERM,interruptScreen);
    NSApplication* app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;
    ScreenOutput* output=[ScreenOutput new];output.mode=unsigned(mode);output.premiere=premiere;output.displayID=CGDirectDisplayID(id);if(tap)output.mirrorPath=@(argv[3]);else if(argc==4)output.testSeconds=std::max(0.,atof(argv[3]));app.delegate=output;[app run];return output.exitCode;
}}
