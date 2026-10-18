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
// Exercise the actual acceptFrame -> bob -> controls -> scaler -> CVPixelBuffer
// path with a synthetic field pair, without calling startStream or opening USB.
@interface ShuttleStream (Fixture)
- (NSArray*)testUniformFrame;
@end
@implementation ShuttleStream (Fixture)
- (NSArray*)testUniformFrame {
    bmusb::VideoFormat v;v.width=720;v.height=576;v.stride=1440;v.interlaced=true;v.has_signal=true;v.frame_rate_nom=25;v.frame_rate_den=1;v.extra_lines_top=22;v.second_field_start=335;
    std::vector<uint8_t> bytes(625*1440);for(size_t n=0;n<bytes.size();n+=4){bytes[n]=40;bytes[n+1]=90;bytes[n+2]=200;bytes[n+3]=90;}
    bmusb::FrameAllocator::Frame frame;frame.data=bytes.data();frame.len=bytes.size();
    _pictures.clear();_clock.configure(_profile);_settled=5;_streaming=true;[self acceptFrame:frame offset:0 format:v timecode:0];_streaming=false;assert(_pictures.size()==2);
    auto pixel=_pictures.back().pixel;CVPixelBufferLockBaseAddress(pixel.get(),kCVPixelBufferLock_ReadOnly);auto p=static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(pixel.get()));NSArray* result=@[@(p[0]),@(p[1]),@(p[2]),@(CVPixelBufferGetWidth(pixel.get()))];CVPixelBufferUnlockBaseAddress(pixel.get(),kCVPixelBufferLock_ReadOnly);return result;
}
@end
static BOOL TestInUse(id,SEL){return YES;}
static unsigned notifications=0;
static void TestNotify(id,SEL,NSDictionary*){++notifications;}
int main(){@autoreleasepool{
    Method use=class_getInstanceMethod(ShuttleStream.class,@selector(inUse));IMP oldUse=method_setImplementation(use,(IMP)TestInUse);
    Method notify=class_getInstanceMethod(CMIOExtensionDevice.class,@selector(notifyPropertiesChanged:));IMP oldNotify=method_setImplementation(notify,(IMP)TestNotify);
    auto d=[defaultSettings() mutableCopy];d[@"video_input"]=@"Composite";d[@"output_size"]=@"Square pixels";
    ShuttleDevice* device=[[ShuttleDevice alloc] initWithConfiguration:d];assert(device);auto stream=device.video;auto identity=device.device;
    __block unsigned rebuilds=0;device.applyConfiguration=^BOOL(NSDictionary*,NSError**){++rebuilds;return NO;};
    auto write=[&](NSDictionary* settings){auto state=[CMIOExtensionPropertyState propertyStateWithValue:settingsJSON(settings)];auto properties=[CMIOExtensionDeviceProperties devicePropertiesWithDictionary:@{SettingsProperty:state}];NSError* error=nil;return [device setDeviceProperties:properties error:&error];};
    NSArray *before=[device.video testUniformFrame];assert([before[0] intValue]==40&&[before[1] intValue]==90&&[before[2] intValue]==200&&[before[3] intValue]==768);
    d[@"brightness"]=@25;d[@"colour"]=@0;assert(write(d));assert(device.video==stream&&device.device==identity&&rebuilds==0&&notifications==1);
    assert([device.configuration[@"brightness"] intValue]==25&&[saved[@"colour"] intValue]==0);
    NSArray *after=[device.video testUniformFrame];assert([after[0] intValue]==128&&[after[1] intValue]==145&&[after[2] intValue]==128&&[after[3] intValue]==768);
    // An old settings client omitting new keys must preserve current picture values.
    auto old=[d mutableCopy];for(NSString* key in @[@"brightness",@"contrast",@"colour",@"sharpness"])[old removeObjectForKey:key];assert(write(old));assert([device.configuration[@"brightness"] intValue]==25&&[device.configuration[@"colour"] intValue]==0);
    auto changed=[d mutableCopy];changed[@"standard"]=@"NTSC";assert(!write(changed));assert([device.configuration[@"standard"] isEqual:@"PAL"]&&rebuilds==0);
    changed=[d mutableCopy];changed[@"brightness"]=@101;assert(!write(changed));assert([device.configuration[@"brightness"] intValue]==25);
    method_setImplementation(use,oldUse);method_setImplementation(notify,oldNotify);
    puts("PASS: actual frame pipeline changes luma90→145 and chroma→128; live updates preserve stream/device, save preferences, notify clients; legacy fields preserved; format changes/invalid values rejected");
}}
