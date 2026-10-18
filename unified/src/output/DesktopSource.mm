// GPL-2.0-or-later. Bounded latest-frame screen mirror with explicit macOS permission.
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include "DesktopSource.hpp"
#include "IdleScreen.hpp"
#include <mutex>
#include <stdexcept>
struct DesktopFrames {std::mutex lock;std::vector<uint8_t> latest;std::string error;bool active=true;unsigned width=0,height=0;};
@interface ShuttleDesktopReceiver : NSObject <SCStreamOutput,SCStreamDelegate>
@property std::shared_ptr<DesktopFrames> frames;
@end
@implementation ShuttleDesktopReceiver
- (void)stream:(SCStream*)stream didStopWithError:(NSError*)error{auto s=self.frames;if(s){std::lock_guard<std::mutex> lock(s->lock);s->error=error.localizedDescription.UTF8String?:"Screen capture stopped";}}
- (void)stream:(SCStream*)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type{
    if(type!=SCStreamOutputTypeScreen||!CMSampleBufferIsValid(sample))return;
    auto image=CMSampleBufferGetImageBuffer(sample);if(!image)return;auto s=self.frames;if(!s)return;
    if(CVPixelBufferGetPixelFormatType(image)!=kCVPixelFormatType_32BGRA||CVPixelBufferGetWidth(image)!=s->width||CVPixelBufferGetHeight(image)!=s->height)return;
    std::vector<uint8_t> picture;CVPixelBufferLockBaseAddress(image,kCVPixelBufferLock_ReadOnly);
    bool ok=shuttle_idle::convertBGRA(static_cast<const uint8_t*>(CVPixelBufferGetBaseAddress(image)),CVPixelBufferGetBytesPerRow(image),s->width,s->height,s->width>720,picture);
    CVPixelBufferUnlockBaseAddress(image,kCVPixelBufferLock_ReadOnly);
    if(ok){std::lock_guard<std::mutex> lock(s->lock);if(s->active)s->latest=std::move(picture);}
}
@end
struct DesktopSource::Impl {
    SCStream *stream;ShuttleDesktopReceiver *receiver;dispatch_queue_t queue;
    std::shared_ptr<DesktopFrames> frames=std::make_shared<DesktopFrames>();
    ~Impl(){auto s=frames;{std::lock_guard<std::mutex> lock(s->lock);s->active=false;}[stream stopCaptureWithCompletionHandler:^(NSError*){}];}
};
DesktopSource::DesktopSource(uint32_t displayID,shuttle_output::Mode mode,shuttle_output::Sizing sizing):impl(new Impl){@autoreleasepool{
    if(!CGPreflightScreenCaptureAccess())throw std::runtime_error("Allow Shuttle Camera in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app.");
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block SCShareableContent* content=nil;__block NSError* error=nil;
    SCDisplay* selected=nil;
    // WindowServer may publish a new extended display before ScreenCaptureKit sees it.
    for(unsigned attempt=0;attempt<20&&!selected;++attempt){
        done=dispatch_semaphore_create(0);content=nil;error=nil;
        [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES completionHandler:^(SCShareableContent* result,NSError* e){content=result;error=e;dispatch_semaphore_signal(done);}];
        if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)))throw std::runtime_error("Screen capture permission timed out; restart output after granting access.");
        if(!content)throw std::runtime_error(error.localizedDescription.UTF8String?:"No screen capture permission");
        for(SCDisplay* display in content.displays)if(display.displayID==displayID)selected=display;
        if(!selected)[NSThread sleepForTimeInterval:0.1];
    }
    if(!selected)throw std::runtime_error("Selected display is disconnected. Choose another display.");
    fprintf(stderr,"Desktop source dimensions: %zu×%zu; mode %u\n",size_t(selected.width),size_t(selected.height),unsigned(mode));
    auto p=shuttle_output::profile(mode);auto& s=*impl;s.frames->width=p.width;s.frames->height=p.height;
    SCContentFilter* filter=[[SCContentFilter alloc] initWithDisplay:selected excludingWindows:@[]];
    SCStreamConfiguration* config=[SCStreamConfiguration new];config.width=p.width;config.height=p.height;config.pixelFormat=kCVPixelFormatType_32BGRA;config.colorSpaceName=kCGColorSpaceSRGB;config.minimumFrameInterval=CMTimeMake(p.rateDen,p.rateNom);config.queueDepth=3;config.showsCursor=YES;config.capturesAudio=NO;
    config.backgroundColor=CGColorGetConstantColor(kCGColorBlack);
    if(sizing!=shuttle_output::Sizing::Stretch){
        auto crop=shuttle_output::crop(selected.width,selected.height,p.width,p.height,p.pixelAspect(),sizing);
        auto fit=shuttle_output::destination(selected.width,selected.height,p.width,p.height,p.pixelAspect(),sizing==shuttle_output::Sizing::Fill?shuttle_output::Sizing::Stretch:sizing);
        config.sourceRect=CGRectMake(crop.x,crop.y,crop.width,crop.height);config.destinationRect=CGRectMake(fit.x,fit.y,fit.width,fit.height);
    }
    // Stretch leaves source/destination rectangles unset: the entire current display
    // maps to the whole fixed output surface, including live desktop mode changes.
    // Fit/Fill geometry already includes non-square PAL/NTSC output pixels.
    // SCK's own square-pixel aspect correction would add unwanted borders.
    config.preservesAspectRatio=NO;
    s.receiver=[ShuttleDesktopReceiver new];s.receiver.frames=s.frames;s.queue=dispatch_queue_create("local.shuttle.desktop",DISPATCH_QUEUE_SERIAL);
    s.stream=[[SCStream alloc] initWithFilter:filter configuration:config delegate:s.receiver];
    if(![s.stream addStreamOutput:s.receiver type:SCStreamOutputTypeScreen sampleHandlerQueue:s.queue error:&error])throw std::runtime_error(error.localizedDescription.UTF8String?:"Cannot attach desktop capture");
    done=dispatch_semaphore_create(0);error=nil;
    [s.stream startCaptureWithCompletionHandler:^(NSError* e){error=e;dispatch_semaphore_signal(done);}];
    if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)))throw std::runtime_error("Desktop capture did not start in time.");
    if(error)throw std::runtime_error(error.localizedDescription.UTF8String?:"Desktop capture failed");
    fprintf(stderr,"Desktop mirror ready — display %u; cursor visible; sizing %s.\n",displayID,sizing==shuttle_output::Sizing::Stretch?"Stretch":sizing==shuttle_output::Sizing::Fill?"Fill":"Fit");
}}
DesktopSource::~DesktopSource()=default;
bool DesktopSource::read(std::vector<uint8_t>& picture){std::lock_guard<std::mutex> lock(impl->frames->lock);if(!impl->frames->error.empty())throw std::runtime_error(impl->frames->error);if(impl->frames->latest.empty())return false;picture=impl->frames->latest;return true;}
