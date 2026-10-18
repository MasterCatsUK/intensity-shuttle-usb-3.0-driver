// GPL-2.0-or-later. Construct the real stream/pixels without opening USB or publishing a service.
#define main ShuttleServiceMain
#include "../src/CameraExtension.mm"
#undef main
#include <cassert>
#include <chrono>
int main() { @autoreleasepool {
    for(NSString *standard in @[@"PAL",@"NTSC"]) for(NSString *size in @[@"Native",@"Square pixels",@"1280x960",@"1440x1080"]) { @autoreleasepool {
        NSMutableDictionary *d=[defaultSettings() mutableCopy];d[@"standard"]=standard;d[@"output_size"]=size;
        shuttle::CaptureSettings s;assert(parseSettings(d,s));ShuttleDevice *device=[[ShuttleDevice alloc] initWithConfiguration:d];assert(device);
        auto *format=device.video.formats.firstObject;auto dimensions=CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        assert(dimensions.width==int(s.outputWidth()) && dimensions.height==int(s.outputHeight()));
        assert(!CMTimeCompare(format.minFrameDuration,CMTimeMake(s.profile.rateDen(),s.profile.fieldNom())));
        std::vector<uint8_t> bytes(1440*s.profile.height());for(size_t n=0;n<bytes.size();n+=4) { bytes[n]=60;bytes[n+1]=100;bytes[n+2]=200;bytes[n+3]=100; }
        auto pixel=[device.video pixelWithBytes:bytes.data()];assert(pixel && CVPixelBufferGetWidth(pixel.get())==s.outputWidth() && CVPixelBufferGetHeight(pixel.get())==s.outputHeight());
        assert(CMVideoFormatDescriptionMatchesImageBuffer(format.formatDescription,pixel.get()));
        NSDictionary *aspect=(__bridge NSDictionary *)CMFormatDescriptionGetExtension(format.formatDescription,kCMFormatDescriptionExtension_PixelAspectRatio);
        assert([aspect[(__bridge NSString *)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] unsignedIntValue]==s.aspectH());
        assert([aspect[(__bridge NSString *)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] unsignedIntValue]==s.aspectV());
        auto black=[device.video pixelWithBytes:nullptr];assert(black && CMVideoFormatDescriptionMatchesImageBuffer(format.formatDescription,black.get()));
        auto start=std::chrono::steady_clock::now();for(unsigned n=0;n<50;++n) { auto image=[device.video pixelWithBytes:bytes.data()];assert(image); }
        double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()/50;
        printf("PASS: %s %ux%u; PAR %u:%u; stream/pixel formats match; mean scale+surface %.3f ms\n",standard.UTF8String,s.outputWidth(),s.outputHeight(),s.aspectH(),s.aspectV(),ms);
    }}
    puts("No USB device was opened; no installed service or capture was changed.");
} }
