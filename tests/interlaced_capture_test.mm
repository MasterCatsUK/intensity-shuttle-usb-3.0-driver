// GPL-2.0-or-later. In-memory device and preferences; no USB, provider service or installed extension.
#import <Foundation/Foundation.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <objc/runtime.h>
#include <cassert>
@interface LiveTestDefaults:NSObject
+ (instancetype)standardUserDefaults;
- (NSDictionary*)dictionaryForKey:(NSString*)key;
- (void)setObject:(id)value forKey:(NSString*)key;
@end
static NSDictionary* saved;
@implementation LiveTestDefaults
+ (instancetype)standardUserDefaults{static auto d=[LiveTestDefaults new];return d;}
- (NSDictionary*)dictionaryForKey:(NSString*)key{return saved;}
- (void)setObject:(id)value forKey:(NSString*)key{saved=value;}
@end
#define NSUserDefaults LiveTestDefaults
#define main UnusedCameraServiceMain
#include "../src/CameraExtension.mm"
#undef main
#undef NSUserDefaults
// In-memory raw USB fixtures and intercepted sample delivery; never starts USB/audio.
static std::vector<CMTime> deliveredPTS,deliveredDurations;
static unsigned expectedFields=2;
static void TestSend(id,SEL,CMSampleBufferRef sample,CMIOExtensionStreamDiscontinuityFlags,uint64_t host){
    assert(sample&&host==uint64_t(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))*1e9+0.5));
    auto fmt=CMSampleBufferGetFormatDescription(sample);
    auto fields=(__bridge NSNumber*)CMFormatDescriptionGetExtension(fmt,kCMFormatDescriptionExtension_FieldCount);assert(fields.unsignedIntValue==expectedFields);
    deliveredPTS.push_back(CMSampleBufferGetPresentationTimeStamp(sample));deliveredDurations.push_back(CMSampleBufferGetDuration(sample));
}
@interface ShuttleStream(InterlaceFixture)
- (void)testRawFields:(BOOL)packed;
- (void)testSampleClock;
@end
@implementation ShuttleStream(InterlaceFixture)
- (void)testRawFields:(BOOL)packed {
    bmusb::VideoFormat v;v.width=720;v.height=_profile.height();v.stride=1440;v.interlaced=true;v.has_signal=true;
    v.frame_rate_nom=_profile.rateNom();v.frame_rate_den=_profile.rateDen();v.extra_lines_top=packed?0:(_profile.ntsc?17:22);v.second_field_start=packed?1:(_profile.ntsc?280:335);
    std::vector<uint8_t> raw((packed?v.height:(_profile.ntsc?525:625))*1440,0);
    for(unsigned field=0;field<2;++field)for(unsigned row=0;row<v.height/2;++row){
        size_t source=packed?2*row+field:(field?v.second_field_start:v.extra_lines_top)+row;
        for(unsigned x=0;x<1440;x+=4){auto p=raw.data()+source*1440+x;p[0]=field?80:40;p[1]=p[3]=field?180:50;p[2]=field?160:200;}
    }
    auto woven=shuttle::weaveImage(raw.data(),v,_settings.bottomFirst);
    if(_settings.native())for(unsigned field=0;field<2;++field)for(unsigned row=0;row<v.height/2;++row){
        size_t source=packed?2*row+field:(field?v.second_field_start:v.extra_lines_top)+row;
        assert(!memcmp(woven.data()+(2*row+(field^(_settings.bottomFirst?1:0)))*1440,raw.data()+source*1440,1440));
    }
    bmusb::FrameAllocator::Frame f;f.data=raw.data();f.len=raw.size();assert(shuttle::complete(f,0,v,_profile));
    _pictures.clear();_clock.configure(_profile);_settled=5;_streaming=true;[self acceptFrame:f offset:0 format:v timecode:1];_streaming=false;
    assert(_pictures.size()==1);auto pixel=_pictures[0].pixel;unsigned w=_settings.outputWidth(),h=_settings.outputHeight();
    assert(CVPixelBufferGetWidth(pixel.get())==w&&CVPixelBufferGetHeight(pixel.get())==h);
    CVPixelBufferLockBaseAddress(pixel.get(),kCVPixelBufferLock_ReadOnly);auto base=static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(pixel.get()));size_t stride=CVPixelBufferGetBytesPerRow(pixel.get());
    for(unsigned y=0;y<h;++y){unsigned field=(y&1)^(_settings.bottomFirst?1:0);auto p=base+y*stride+(w/4)*4;assert(abs(int(p[0])-(field?80:40))<=1&&abs(int(p[1])-(field?180:50))<=1&&abs(int(p[2])-(field?160:200))<=1);}
    if(_settings.imageWidth()!=w)for(unsigned y=0;y<h;++y){auto p=base+y*stride;assert(p[0]==128&&p[1]==16&&p[2]==128);}
    CVPixelBufferUnlockBaseAddress(pixel.get(),kCVPixelBufferLock_ReadOnly);
    auto fmt=_formats[0].formatDescription;NSDictionary* tags=(__bridge NSDictionary*)CMFormatDescriptionGetExtensions(fmt);
    assert([tags[(__bridge NSString*)kCVImageBufferFieldCountKey] intValue]==2);
    assert([tags[(__bridge NSString*)kCVImageBufferFieldDetailKey] isEqual:(__bridge NSString*)(_settings.bottomFirst?kCVImageBufferFieldDetailSpatialFirstLineLate:kCVImageBufferFieldDetailSpatialFirstLineEarly)]);
    auto properties=[self streamPropertiesForProperties:[NSSet setWithObjects:CMIOExtensionPropertyStreamFrameDuration,CMIOExtensionPropertyStreamMaxFrameDuration,nil] error:nil];
    assert(CMTimeCompare(CMTimeMakeFromDictionary((__bridge CFDictionaryRef)properties.frameDuration),CMTimeMake(_profile.rateDen(),_settings.sampleRateNom()))==0);
    assert(CMTimeCompare(_formats[0].minFrameDuration,CMTimeMake(_profile.rateDen(),_settings.sampleRateNom()))==0);
}
- (void)testSampleClock {
    _pictures.clear();_lastPicture=[self pixelWithBytes:nullptr];_blackPicture=_lastPicture;
    auto now=hostNS()-shuttle::PlayoutDelayNS;_outputIndex=_settings.sampleTickAt(now)-2;_nextOutputNS=_settings.sampleNS(_outputIndex);
    deliveredPTS.clear();deliveredDurations.clear();expectedFields=_settings.interlaced()?2:1;
    _streaming=true;[self outputTick];_streaming=false;assert(deliveredPTS.size()>=2&&deliveredPTS.size()<=5);
    CMTime duration=CMTimeMake(_profile.rateDen(),_settings.sampleRateNom());
    for(size_t i=0;i<deliveredPTS.size();++i){assert(CMTimeCompare(deliveredDurations[i],duration)==0);if(i){double delta=CMTimeGetSeconds(CMTimeSubtract(deliveredPTS[i],deliveredPTS[i-1]));assert(fabs(delta-CMTimeGetSeconds(duration))<2e-9);}}
}
@end
int main(){@autoreleasepool{
    Method method=class_getInstanceMethod(CMIOExtensionStream.class,@selector(sendSampleBuffer:discontinuity:hostTimeInNanoseconds:));IMP old=method_setImplementation(method,(IMP)TestSend);
    for(bool ntsc:{false,true})for(bool wide:{false,true})for(bool bottom:{false,true})for(auto mode:{shuttle::OutputSize::NativeInterlaced,shuttle::OutputSize::Size1920x1080Interlaced}){
        shuttle::CaptureSettings settings;settings.profile.ntsc=ntsc;settings.widescreen=wide;settings.bottomFirst=bottom;settings.outputSize=mode;
        ShuttleStream* stream=[[ShuttleStream alloc] initWithSettings:settings];assert(stream);[stream testRawFields:NO];[stream testRawFields:YES];[stream testSampleClock];
        printf("PASS: %s %s %s %ux%ui, packed/separated fields, no field blend, metadata, actual sample PTS/duration\n",ntsc?"NTSC":"PAL",wide?"16:9":"4:3",bottom?"BFF":"TFF",settings.outputWidth(),settings.outputHeight());
    }
    for(bool ntsc:{false,true}){shuttle::CaptureSettings s;s.profile.ntsc=ntsc;ShuttleStream* stream=[[ShuttleStream alloc] initWithSettings:s];[stream testSampleClock];}
    for(unsigned h:{480u,576u}){
        shuttle::InterlacedScale422 scale(h,720,h,720,h);std::vector<uint8_t> source(1440*h),out((1440+32)*h+64,0xa5);for(size_t i=0;i<source.size();++i)source[i]=uint8_t(i*37);
        assert(scale.write(source.data(),out.data()+32,1472));for(unsigned y=0;y<h;++y){assert(!memcmp(source.data()+y*1440,out.data()+32+y*1472,1440));for(unsigned x=1440;x<1472;++x)assert(out[32+y*1472+x]==0xa5);}for(unsigned x=0;x<32;++x)assert(out[x]==0xa5&&out[out.size()-1-x]==0xa5);
        assert(!scale.write(source.data(),out.data(),1439));
    }
    method_setImplementation(method,old);puts("PASS: progressive sample cadence remains unchanged; no USB/audio service started");
}}
