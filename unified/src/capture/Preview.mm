// GPL-2.0-or-later. Direct CMIO preview; never changes camera settings or recording samples.
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
@interface CapturePreview : NSObject {
    CMIODeviceID _device;CMIOStreamID _stream;CMSimpleQueueRef _queue;CIContext *_context;
}
@property NSImageView *view;
@property NSTextField *message;
@property NSTimer *timer;
@property BOOL wantsPreview,permissionPending;
@property double displayAspect;
@property NSView *metersView;
- (void)setPreviewAspect:(double)aspect;
@property NSTimeInterval lastStatus;
- (void)start;
- (void)stop;
@end
@implementation CapturePreview
- (instancetype)init {if((self=[super init])){_view=[[NSImageView alloc] initWithFrame:NSMakeRect(22,286,542,200)];_view.imageScaling=NSImageScaleProportionallyUpOrDown;_view.wantsLayer=YES;_view.layer.backgroundColor=NSColor.blackColor.CGColor;_view.layer.cornerRadius=6;_view.layer.masksToBounds=YES;_view.accessibilityLabel=@"Live capture preview";_message=[NSTextField labelWithString:@"Live input"];_message.frame=NSMakeRect(34,290,518,20);_message.textColor=NSColor.whiteColor;_message.font=[NSFont systemFontOfSize:11];}return self;}
- (void)setPreviewAspect:(double)aspect {
    if(!std::isfinite(aspect)||aspect<=0||fabs(self.displayAspect-aspect)<.000001)return;self.displayAspect=aspect;NSRect box=NSMakeRect(22,286,542,200);double h=std::min(double(box.size.height),double(box.size.width)/aspect),w=h*aspect;self.view.frame=NSMakeRect(325-(w+86)/2,NSMidY(box)-h/2,w,h);self.metersView.frame=NSMakeRect(NSMaxX(self.view.frame)+14,286,72,200);self.message.frame=NSMakeRect(self.view.frame.origin.x+8,self.view.frame.origin.y+5,w-16,32);
}
- (void)start {
    self.wantsPreview=YES;if(_queue||self.permissionPending)return;
    AVAuthorizationStatus auth=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if(auth==AVAuthorizationStatusNotDetermined){self.permissionPending=YES;self.message.stringValue=@"Allow Camera access to show the Shuttle input.";__weak CapturePreview *weakSelf=self;[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted){dispatch_async(dispatch_get_main_queue(),^{CapturePreview *p=weakSelf;if(!p)return;p.permissionPending=NO;if(granted&&p.wantsPreview)[p start];else if(p.wantsPreview)p.message.stringValue=@"Allow Shuttle Camera in System Settings → Privacy & Security → Camera.";});}];return;}
    if(auth!=AVAuthorizationStatusAuthorized){self.message.stringValue=@"Allow Shuttle Camera in System Settings → Privacy & Security → Camera.";return;}
    _device=cameraID();if(!_device){self.message.stringValue=@"Enable the Shuttle camera in Help → Driver Setup.";return;}
    CMIOObjectPropertyAddress a{kCMIODevicePropertyStreams,kCMIODevicePropertyScopeInput,0};UInt32 size=0;OSStatus rc=CMIOObjectGetPropertyDataSize(_device,&a,0,nullptr,&size);std::vector<CMIOStreamID> streams(size/sizeof(CMIOStreamID));if(!rc&&size)rc=CMIOObjectGetPropertyData(_device,&a,0,nullptr,size,&size,streams.data());_stream=streams.empty()?0:streams.front();if(!rc&&_stream)rc=CMIOStreamCopyBufferQueue(_stream,[](CMIOStreamID,void*,void*){},nullptr,&_queue);
    if(rc||!_queue){self.message.stringValue=@"Camera unavailable. Check the driver and USB connection.";[self stop];return;}
    rc=CMIODeviceStartStream(_device,_stream);if(rc){CFRelease(_queue);_queue=nullptr;self.message.stringValue=@"Input unavailable. Stop video output, then return to Capture.";return;}
    _context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];self.message.stringValue=@"Waiting for input…";__weak CapturePreview *weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1.0/30 repeats:YES block:^(NSTimer*){[weakSelf displayLatest];}];
}
- (void)displayLatest {
    if(!_queue)return;CMSampleBufferRef latest=nullptr;for(int i=0;i<32;i++){auto s=(CMSampleBufferRef)CMSimpleQueueDequeue(_queue);if(!s)break;if(latest)CFRelease(latest);latest=s;}if(!latest)return;
    auto pixel=CMSampleBufferGetImageBuffer(latest);if(pixel){CIImage *image=[CIImage imageWithCVPixelBuffer:pixel];CGImageRef cg=[_context createCGImage:image fromRect:image.extent];if(cg){double ratio=1;auto f=CMSampleBufferGetFormatDescription(latest);auto par=(__bridge NSDictionary*)CMFormatDescriptionGetExtension(f,kCMFormatDescriptionExtension_PixelAspectRatio);double h=[par[(id)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] doubleValue],v=[par[(id)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] doubleValue];if(h>0&&v>0)ratio=h/v;[self setPreviewAspect:CGImageGetWidth(cg)*ratio/CGImageGetHeight(cg)];self.view.image=[[NSImage alloc] initWithCGImage:cg size:NSMakeSize(CGImageGetWidth(cg)*ratio,CGImageGetHeight(cg))];CGImageRelease(cg);}}CFRelease(latest);
    if(NSDate.timeIntervalSinceReferenceDate-self.lastStatus>1){self.lastStatus=NSDate.timeIntervalSinceReferenceDate;NSDictionary *state=readSettings();NSString *actual=state[@"detected_standard"],*chosen=state[@"standard"];if(([actual isEqual:@"PAL"]||[actual isEqual:@"NTSC"])&&![actual isEqual:chosen])self.message.stringValue=[NSString stringWithFormat:@"Input reports %@; selected %@. Check the source standard and input.",actual,chosen];else if([actual isEqual:@"No SD signal"])self.message.stringValue=@"No input signal. Check the cable, selected input and VCR playback.";else self.message.stringValue=@"";}

}
- (void)stop { self.wantsPreview=NO;[self.timer invalidate];self.timer=nil;if(_queue){CMIODeviceStopStream(_device,_stream);while(CMSimpleQueueGetCount(_queue)){auto s=CMSimpleQueueDequeue(_queue);if(s)CFRelease(s);}CFRelease(_queue);_queue=nullptr;}_context=nil;self.view.image=nil;self.message.stringValue=@"Live input";}
- (void)dealloc {if(_queue){CMIODeviceStopStream(_device,_stream);while(CMSimpleQueueGetCount(_queue)){auto s=CMSimpleQueueDequeue(_queue);if(s)CFRelease(s);}CFRelease(_queue);}}
@end
