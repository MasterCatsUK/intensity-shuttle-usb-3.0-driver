// GPL-2.0-or-later. Actual Core Image preview conversion and non-square-pixel display aspect, no devices.
#import <AppKit/AppKit.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMedia/CoreMedia.h>
#include <vector>
#include <cassert>
static NSDictionary *readSettings(){return nil;}
static CMIODeviceID cameraID(){assert(false);return 0;}
#include "../unified/src/capture/Preview.mm"
@interface FixturePreview:CapturePreview
- (void)check;
@end
@implementation FixturePreview
- (void)check {
 assert(!CMSimpleQueueCreate(nullptr,4,&_queue));_context=[CIContext contextWithOptions:nil];
 for(bool wide:{false,true}){CVPixelBufferRef pixel=nullptr;assert(!CVPixelBufferCreate(nullptr,720,576,kCVPixelFormatType_422YpCbCr8,nullptr,&pixel));CVPixelBufferLockBaseAddress(pixel,0);for(int y=0;y<576;y++){auto row=(uint8_t*)CVPixelBufferGetBaseAddress(pixel)+y*CVPixelBufferGetBytesPerRow(pixel);for(int x=0;x<720;x+=2){row[2*x]=128;row[2*x+1]=200;row[2*x+2]=128;row[2*x+3]=200;}}CVPixelBufferUnlockBaseAddress(pixel,0);CVBufferSetAttachment(pixel,kCVImageBufferPixelAspectRatioKey,(__bridge CFDictionaryRef)@{(id)kCVImageBufferPixelAspectRatioHorizontalSpacingKey:wide?@64:@16,(id)kCVImageBufferPixelAspectRatioVerticalSpacingKey:wide?@45:@15},kCVAttachmentMode_ShouldPropagate);CMVideoFormatDescriptionRef format=nullptr;assert(!CMVideoFormatDescriptionCreateForImageBuffer(nullptr,pixel,&format));CMSampleBufferRef s=nullptr;CMSampleTimingInfo t{CMTimeMake(1,25),kCMTimeZero,kCMTimeInvalid};assert(!CMSampleBufferCreateReadyWithImageBuffer(nullptr,pixel,format,&t,&s));assert(!CMSimpleQueueEnqueue(_queue,s));[self displayLatest];assert(self.view.image);double aspect=self.view.image.size.width/self.view.image.size.height;assert(fabs(aspect-(wide?16./9:4./3))<.001);auto image=[self.view.image CGImageForProposedRect:nullptr context:nil hints:nil];assert(image&&CGImageGetWidth(image)==720&&CGImageGetHeight(image)==576);CFRelease(format);CFRelease(pixel);}
 CFRelease(_queue);_queue=nullptr;_context=nil;
}
@end
int main(){@autoreleasepool{[NSApplication sharedApplication];auto p=[FixturePreview new];[p check];assert(p.view.imageScaling==NSImageScaleProportionallyUpOrDown);puts("PASS: direct UYVY preview conversion, PAL 4:3 / 16:9 pixel aspect, whole-frame fit, no camera/settings/audio access.");}}
