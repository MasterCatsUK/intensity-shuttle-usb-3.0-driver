// GPL-2.0-or-later. Native AVFoundation discovery and short receive test.
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#include <atomic>
#include <cstdio>

@interface Receiver : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate> {
@public std::atomic<unsigned> count;
}
@property(copy) NSString *imagePath;
@end
@implementation Receiver
- (instancetype)init { if((self=[super init])) count=0; return self; }
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection {
    unsigned n=++count;
    CVPixelBufferRef pixel=CMSampleBufferGetImageBuffer(sample);
    if(n==1 && pixel) {
        printf("First frame: %zu x %zu; PTS %.6f\n",CVPixelBufferGetWidth(pixel),CVPixelBufferGetHeight(pixel),CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)));
    }
    if(n==100 && pixel) {
        if(self.imagePath) {
            CIImage *image=[CIImage imageWithCVPixelBuffer:pixel];
            CIContext *context=[CIContext contextWithOptions:nil];
            CGImageRef cg=[context createCGImage:image fromRect:image.extent];
            if(cg) {
                NSURL *url=[NSURL fileURLWithPath:self.imagePath];
                CGImageDestinationRef dest=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,nullptr);
                if(dest) { CGImageDestinationAddImage(dest,cg,nullptr);printf("PNG saved: %s\n",CGImageDestinationFinalize(dest)?"yes":"no");CFRelease(dest); }
                CGImageRelease(cg);
            }
        }
    }
}
@end

int main(int argc,char **argv) {
    @autoreleasepool {
        setvbuf(stdout,nullptr,_IOLBF,0);
        AVCaptureDevice *camera=nil;
        for(AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
            if([d.uniqueID containsString:@"local.shuttle.camera"]) {
                camera=d;printf("Discovered: %s; UID=%s\n",d.localizedName.UTF8String,d.uniqueID.UTF8String);
                for(AVCaptureDeviceFormat *f in d.formats) {
                    CMVideoDimensions size=CMVideoFormatDescriptionGetDimensions(f.formatDescription);
                    for(AVFrameRateRange *r in f.videoSupportedFrameRateRanges)
                        printf("Format: %dx%d, %.2f–%.2f fps\n",size.width,size.height,r.minFrameRate,r.maxFrameRate);
                }
            }
        }
        if(!camera) { puts("Shuttle camera is not discoverable through AVFoundation.");return 2; }
        if(argc==1 || (argc==2 && strcmp(argv[1],"--list")==0)) return 0;
        if(argc!=3 || strcmp(argv[1],"--capture")!=0) return 64;
        AVAuthorizationStatus auth=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        if(auth==AVAuthorizationStatusNotDetermined) {
            puts("Camera permission is required for this native receive test. Please approve the macOS dialog.");
            __block bool finished=false;
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted){ finished=true; }];
            NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:90];
            while(!finished && limit.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        if([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]!=AVAuthorizationStatusAuthorized) {
            puts("Camera access was not authorized.");return 4;
        }
        NSError *error=nil;
        AVCaptureDeviceInput *input=[AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
        if(!input) { printf("Input error: %s\n",error.description.UTF8String);return 5; }
        AVCaptureSession *session=[AVCaptureSession new];
        [NSNotificationCenter.defaultCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification
             object:session queue:nil usingBlock:^(NSNotification *note){ NSLog(@"Capture runtime error: %@",note.userInfo); }];
        [session beginConfiguration];
        if([session canSetSessionPreset:AVCaptureSessionPresetHigh]) session.sessionPreset=AVCaptureSessionPresetHigh;
        if(![session canAddInput:input]) return 6;
        [session addInput:input];
        if([camera lockForConfiguration:&error]) {
            camera.activeFormat=camera.formats.firstObject;
            camera.activeVideoMinFrameDuration=camera.activeFormat.videoSupportedFrameRateRanges.firstObject.minFrameDuration;
            camera.activeVideoMaxFrameDuration=camera.activeVideoMinFrameDuration;
            [camera unlockForConfiguration];
        }
        AVCaptureVideoDataOutput *output=[AVCaptureVideoDataOutput new];
        output.videoSettings=@{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
        output.alwaysDiscardsLateVideoFrames=YES;
        Receiver *receiver=[Receiver new]; receiver.imagePath=[NSString stringWithUTF8String:argv[2]];
        dispatch_queue_t queue=dispatch_queue_create("local.shuttle.video-test",DISPATCH_QUEUE_SERIAL);
        [output setSampleBufferDelegate:receiver queue:queue];
        if(![session canAddOutput:output]) return 7;
        [session addOutput:output];[session commitConfiguration];
        [session startRunning];
        printf("Session running: %s; output connections: %lu\n",session.running?"yes":"no",(unsigned long)output.connections.count);
        for(unsigned second=0;second<10;++second) {
            [NSThread sleepForTimeInterval:1];
            printf("%us: received %u frames\n",second+1,receiver->count.load());
        }
        [session stopRunning];
        dispatch_sync(queue,^{});
        printf("RESULT: %u received camera frames\n",receiver->count.load());
        return receiver->count>0?0:8;
    }
}
