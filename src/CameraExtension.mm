// GPL-2.0-or-later. Continuous SD camera with independent stereo audio capture.
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#include "FrameProtocol.hpp"
#include "AudioProtocol.hpp"
#include "CaptureClock.hpp"
#include "Settings.hpp"
#include "AudioPacketizer.hpp"
#include "Scale422.hpp"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <atomic>
#include <cerrno>
#include <unistd.h>
#include <deque>
#include <memory>
#include <type_traits>

using Pixel=std::shared_ptr<std::remove_pointer<CVPixelBufferRef>::type>;
struct ShuttlePicture { uint64_t ns;Pixel pixel; };
static NSString * const DropProperty=@"4cc_drpt_glob_0";
static NSString * const SyncProperty=@"4cc_sync_glob_0";
static uint64_t hostNS() {
    return CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()),1000000000,kCMTimeRoundingMethod_Default).value;
}
static NSError *failure(NSString *message) {
    return [NSError errorWithDomain:@"local.shuttle.camera" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
@interface ShuttleStream : NSObject <CMIOExtensionStreamSource> {
    CMIOExtensionStream *_stream;
    NSArray<CMIOExtensionStreamFormat *> *_formats;
    NSDictionary *_extensions;
    bmusb::BMUSBCapture *_capture;
    std::atomic<bool> _streaming;
    shuttle::CaptureClock _clock;
    shuttle::CaptureSettings _settings;
    shuttle::VideoProfile _profile;
    std::unique_ptr<shuttle::Scale422> _scaler;
    std::unique_ptr<shuttle::InterlacedScale422> _interlacedScaler;
    std::shared_ptr<shuttle::PictureControls> _pictureControls;
    shuttle_audio::Packetizer _packetizer;
    std::atomic<unsigned> _detected;
    std::mutex _picturesLock;
    std::deque<ShuttlePicture> _pictures;
    Pixel _lastPicture,_blackPicture;
    dispatch_queue_t _outputQueue;
    dispatch_source_t _timer;
    uint64_t _nextOutputNS,_outputIndex,_sequence,_held,_lastFreshNS;
    unsigned _users,_settled;
    int _audioFD;
    bool _audioLogged,_audioErrorLogged;
    std::atomic<uint64_t> _dropUntil,_syncUntil;
}
@property(readonly) CMIOExtensionStream *stream;
- (instancetype)initWithSettings:(shuttle::CaptureSettings)settings;
- (BOOL)inUse;
- (NSString *)detectedStandard;
- (void)acceptFrame:(bmusb::FrameAllocator::Frame)frame offset:(size_t)offset format:(bmusb::VideoFormat)format timecode:(uint16_t)timecode;
- (void)acceptAudio:(const bmusb::FrameAllocator::Frame &)audio offset:(size_t)offset timecode:(uint16_t)timecode;
- (Pixel)pixelWithBytes:(const uint8_t *)bytes;
- (void)outputTick;
- (void)updatePicture:(shuttle::PictureSettings)settings;
@end
@implementation ShuttleStream
- (instancetype)initWithSettings:(shuttle::CaptureSettings)settings {
    if((self=[super init])) {
        _settings=settings;_profile=settings.profile;_detected=0;
        _pictureControls=std::make_shared<shuttle::PictureControls>(settings.picture);
        if(settings.interlaced())_interlacedScaler.reset(new shuttle::InterlacedScale422(_profile.height(),settings.outputWidth(),settings.outputHeight(),settings.imageWidth(),settings.imageHeight()));
        else _scaler.reset(new shuttle::Scale422(_profile.height(),settings.outputWidth(),settings.outputHeight(),settings.imageWidth(),settings.imageHeight()));
        _streaming=false;_audioFD=-1;_dropUntil=0;_syncUntil=0;
        _outputQueue=dispatch_queue_create("local.shuttle.camera.playout",DISPATCH_QUEUE_SERIAL);
        _extensions=@{
            (__bridge NSString *)kCMFormatDescriptionExtension_PixelAspectRatio:@{
                (__bridge NSString *)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing:@(_settings.aspectH()),
                (__bridge NSString *)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing:@(_settings.aspectV())},
            (__bridge NSString *)kCMFormatDescriptionExtension_YCbCrMatrix:
                (__bridge NSString *)kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4};
        NSMutableDictionary *tags=[_extensions mutableCopy];
        tags[(__bridge NSString*)kCVImageBufferFieldCountKey]=@(settings.interlaced()?2:1);
        if(settings.interlaced())tags[(__bridge NSString*)kCVImageBufferFieldDetailKey]=(__bridge NSString*)(settings.bottomFirst?kCVImageBufferFieldDetailSpatialFirstLineLate:kCVImageBufferFieldDetailSpatialFirstLineEarly);
        _extensions=[tags copy];
        CMVideoFormatDescriptionRef fmt=nullptr;
        if(CMVideoFormatDescriptionCreate(kCFAllocatorDefault,kCVPixelFormatType_422YpCbCr8,_settings.outputWidth(),_settings.outputHeight(),(__bridge CFDictionaryRef)_extensions,&fmt)) return nil;
        CMTime duration=CMTimeMake(_profile.rateDen(),_settings.sampleRateNom());
        _formats=@[[CMIOExtensionStreamFormat streamFormatWithFormatDescription:fmt maxFrameDuration:duration minFrameDuration:duration validFrameDurations:nil]];
        CFRelease(fmt);
        _stream=[CMIOExtensionStream streamWithLocalizedName:(_settings.interlaced()?[NSString stringWithFormat:@"%ui%@",_settings.outputHeight(),_profile.ntsc?@"59.94":@"50"]:(_profile.ntsc?@"NTSC 59.94p":@"PAL 50p"))
             streamID:[[NSUUID alloc] initWithUUIDString:@"C48BDE00-D3B0-43E1-B576-000000000050"]
             direction:CMIOExtensionStreamDirectionSource clockType:CMIOExtensionStreamClockTypeHostTime source:self];
    }return self;
}
- (CMIOExtensionStream *)stream { return _stream; }
- (BOOL)inUse { return _users>0; }
- (NSString *)detectedStandard { return _detected==1?@"PAL":_detected==2?@"NTSC":@"No SD signal"; }
- (NSArray<CMIOExtensionStreamFormat *> *)formats { return _formats; }
- (NSSet *)availableProperties {
    return [NSSet setWithObjects:CMIOExtensionPropertyStreamActiveFormatIndex,CMIOExtensionPropertyStreamFrameDuration,CMIOExtensionPropertyStreamMaxFrameDuration,DropProperty,SyncProperty,nil];
}
- (CMIOExtensionStreamProperties *)streamPropertiesForProperties:(NSSet *)properties error:(NSError **)error {
    auto *p=[CMIOExtensionStreamProperties streamPropertiesWithDictionary:@{}];
    if([properties containsObject:CMIOExtensionPropertyStreamActiveFormatIndex]) p.activeFormatIndex=@0;
    NSDictionary *duration=CFBridgingRelease(CMTimeCopyAsDictionary(CMTimeMake(_profile.rateDen(),_settings.sampleRateNom()),kCFAllocatorDefault));
    if([properties containsObject:CMIOExtensionPropertyStreamFrameDuration]) p.frameDuration=duration;
    if([properties containsObject:CMIOExtensionPropertyStreamMaxFrameDuration]) p.maxFrameDuration=duration;
    if([properties containsObject:DropProperty]) {
        auto *attributes=[CMIOExtensionPropertyAttributes propertyAttributesWithMinValue:nil maxValue:nil validValues:nil readOnly:NO];
        [p setPropertyState:[CMIOExtensionPropertyState propertyStateWithValue:@"0" attributes:attributes] forProperty:DropProperty];
    }
    if([properties containsObject:SyncProperty])
        [p setPropertyState:[CMIOExtensionPropertyState propertyStateWithValue:@"0"] forProperty:SyncProperty];
    return p;
}
- (BOOL)setStreamProperties:(CMIOExtensionStreamProperties *)p error:(NSError **)error {
    if(p.activeFormatIndex && p.activeFormatIndex.unsignedIntValue!=0) { if(error) *error=failure(@"Only the selected television standard is available.");return NO; }
    for(NSDictionary *d in @[p.frameDuration?:@{},p.maxFrameDuration?:@{}]) {
        if(d.count && CMTimeCompare(CMTimeMakeFromDictionary((__bridge CFDictionaryRef)d),CMTimeMake(_profile.rateDen(),_settings.sampleRateNom()))) {
            if(error) *error=failure(@"Use Shuttle Camera settings to change the television standard.");return NO;
        }
    }
    id value=p.propertiesDictionary[DropProperty].value;
    if(value) {
        // Bounded diagnostic fault injection; never enabled during ordinary use.
        if(![value isKindOfClass:NSString.class] || !std::isfinite([value doubleValue]) || [value doubleValue]<0 || [value doubleValue]>5) return NO;
        _dropUntil=hostNS()+uint64_t([value doubleValue]*1e9);
        NSLog(@"Shuttle diagnostic video dropout: %@ seconds",value);
    }
    id sync=p.propertiesDictionary[SyncProperty].value;
    if(sync) {
        if(![sync isKindOfClass:NSString.class] || !std::isfinite([sync doubleValue]) || [sync doubleValue]<0 || [sync doubleValue]>15) return NO;
        _syncUntil=hostNS()+uint64_t([sync doubleValue]*1e9);
        NSLog(@"Shuttle diagnostic flash/tone: %@ seconds",sync);
    }return YES;
}
- (BOOL)authorizedToStartStreamForClient:(CMIOExtensionClient *)client { return YES; }
- (BOOL)startStreamAndReturnError:(NSError **)error {
    if(_users) { ++_users;return YES; }
    if(_capture) { if(error) *error=failure(@"Previous USB cancellation was incomplete; restart the camera service.");return NO; }
    NSLog(@"Shuttle start stream");
    try {
        if(!bmusb::BMUSBCapture::num_cards()) { if(error) *error=failure(@"USB 3 Intensity Shuttle is not connected.");return NO; }
        _capture=new bmusb::BMUSBCapture(0);auto *engine=_capture;
        __weak ShuttleStream *weakSelf=self;
        engine->set_no_signal_bypass(true);engine->set_video_input(_settings.videoInput);engine->set_audio_input(_settings.audioInput);
        engine->set_pixel_format(bmusb::PixelFormat_8BitYCbCr);
        engine->set_audio_observer([weakSelf](uint16_t tc,const bmusb::FrameAllocator::Frame &a,size_t ao) {
            ShuttleStream *strong=weakSelf;if(strong) [strong acceptAudio:a offset:ao timecode:tc];
        });
        engine->set_frame_callback([weakSelf,engine](uint16_t tc,bmusb::FrameAllocator::Frame v,size_t vo,
            bmusb::VideoFormat vf,bmusb::FrameAllocator::Frame a,size_t,bmusb::AudioFormat) {
            ShuttleStream *strong=weakSelf;if(strong) [strong acceptFrame:v offset:vo format:vf timecode:tc];
            if(v.data) engine->get_video_frame_allocator()->release_frame(v);
            if(a.data) engine->get_audio_frame_allocator()->release_frame(a);
        });
        _clock.configure(_profile);_packetizer.reset();_lastFreshNS=0;_settled=0;_sequence=0;_held=0;_dropUntil=0;_syncUntil=0;
        _lastPicture=[self pixelWithBytes:nullptr];_blackPicture=_lastPicture;
        if(!_lastPicture) throw std::runtime_error("Unable to allocate video surface");
        engine->configure_card();
        _audioFD=socket(AF_INET,SOCK_DGRAM,0);
        if(_audioFD>=0) fcntl(_audioFD,F_SETFL,O_NONBLOCK);
        _audioLogged=false;_audioErrorLogged=false;_streaming=true;
        bmusb::BMUSBCapture::start_bm_thread();engine->start_bm_capture();
        _outputIndex=_settings.sampleTickAt(hostNS()-shuttle::PlayoutDelayNS);_nextOutputNS=_settings.sampleNS(_outputIndex);
        _timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,_outputQueue);
        dispatch_source_set_timer(_timer,dispatch_time(DISPATCH_TIME_NOW,0),_settings.sampleNS(),1000000);
        dispatch_source_set_event_handler(_timer,^{ ShuttleStream *strong=weakSelf;if(strong) [strong outputTick]; });
        dispatch_resume(_timer);_users=1;return YES;
    }catch(const std::exception &e) {
        _streaming=false;
        if(_capture && _capture->shutdown_capture()) { delete _capture;_capture=nullptr; }
        if(_audioFD>=0) { close(_audioFD);_audioFD=-1; }
        if(error) *error=failure([NSString stringWithUTF8String:e.what()]);return NO;
    }
}
- (BOOL)stopStreamAndReturnError:(NSError **)error {
    if(_users && --_users==0) {
        _streaming=false;
        if(_timer) { dispatch_source_cancel(_timer);_timer=nil; }
        dispatch_sync(_outputQueue,^{});
        bool clean=_capture && _capture->shutdown_capture();
        if(_audioFD>=0) { close(_audioFD);_audioFD=-1; }
        { std::lock_guard<std::mutex> guard(_picturesLock);_pictures.clear();_lastPicture.reset();_blackPicture.reset(); }
        NSLog(@"Shuttle USB shutdown: %@; output=%llu; repeated=%llu",clean?@"complete":@"incomplete",_sequence,_held);
        if(clean) { delete _capture;_capture=nullptr; }
        else { if(error) *error=failure(@"USB cancellation did not complete.");return NO; }
    }return YES;
}
- (void)acceptAudio:(const bmusb::FrameAllocator::Frame &)a offset:(size_t)ao timecode:(uint16_t)tc {
    if(!_streaming || _audioFD<0 || !a.data || ao>a.len || (a.len-ao)%24) return;
    unsigned count=unsigned((a.len-ao)/24);if(!_profile.audioFrames(count)) return;
    uint64_t start=_clock.audio(tc,hostNS());bool diagnostic=hostNS()<_syncUntil;
    sockaddr_in address{};address.sin_len=sizeof(address);address.sin_family=AF_INET;
    address.sin_port=htons(shuttle_audio::Port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    _packetizer.push(count,start,[&](unsigned n,unsigned ch) -> float {
        uint64_t phase=(start+n*1000000000ULL/48000)%1000000000ULL;
        return diagnostic?(phase<200000000ULL?0.12f*std::sin(phase*(2.0*3.141592653589793*1000.0/1e9)):0.0f):
            shuttle_audio::pcm24(a.data+ao+n*24+ch*3);
    },[&](const shuttle_audio::Packet &packet){
        ssize_t sent=sendto(_audioFD,&packet,sizeof(packet),0,reinterpret_cast<sockaddr *>(&address),sizeof(address));
        if(sent==sizeof(packet) && !_audioLogged) { NSLog(@"Shuttle publishing independent stereo audio");_audioLogged=true; }
        if(sent<0 && !_audioErrorLogged) { NSLog(@"Shuttle audio send failed: %s",strerror(errno));_audioErrorLogged=true; }
    });
}
- (void)updatePicture:(shuttle::PictureSettings)settings { std::atomic_store(&_pictureControls,std::make_shared<shuttle::PictureControls>(settings)); }
- (Pixel)pixelWithBytes:(const uint8_t *)bytes {
    CVPixelBufferRef pixel=nullptr;
    NSDictionary *attributes=@{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}};
    if(CVPixelBufferCreate(kCFAllocatorDefault,_settings.outputWidth(),_settings.outputHeight(),kCVPixelFormatType_422YpCbCr8,(__bridge CFDictionaryRef)attributes,&pixel)) return {};
    CVPixelBufferLockBaseAddress(pixel,0);
    auto *dest=static_cast<uint8_t *>(CVPixelBufferGetBaseAddress(pixel));size_t stride=CVPixelBufferGetBytesPerRow(pixel);
    bool ok=true;
    std::memset(dest,0,stride*_settings.outputHeight());
    if(bytes) ok=_settings.interlaced()?_interlacedScaler->write(bytes,dest,stride):_scaler->write(bytes,dest,stride);
    else for(unsigned y=0;y<_settings.outputHeight();++y) for(unsigned x=0;x<_settings.outputWidth()*2;x+=4) {
        dest[y*stride+x]=dest[y*stride+x+2]=128;dest[y*stride+x+1]=dest[y*stride+x+3]=16;
    }
    CVPixelBufferUnlockBaseAddress(pixel,0);
    if(!ok) { CVPixelBufferRelease(pixel);return {}; }
    CVBufferSetAttachments(pixel,(__bridge CFDictionaryRef)_extensions,kCVAttachmentMode_ShouldPropagate);
    return Pixel(pixel,[](CVPixelBufferRef p){ CVPixelBufferRelease(p); });
}
- (void)acceptFrame:(bmusb::FrameAllocator::Frame)frame offset:(size_t)offset format:(bmusb::VideoFormat)v timecode:(uint16_t)tc {
    if(v.has_signal) _detected=v.height==576?1:v.height==480?2:0;else _detected=0;
    if(!_streaming || !shuttle::complete(frame,offset,v,_profile)) return;
    if(_settled<5) { ++_settled;return; }
    uint64_t now=hostNS();if(now<_dropUntil) return;
    uint64_t start=_clock.video(tc,now);if(!start) return;
    @autoreleasepool {
        auto controls=std::atomic_load(&_pictureControls);
        if(_settings.interlaced()){
            auto bytes=shuttle::weaveImage(frame.data+offset,v,_settings.bottomFirst);
            controls->apply(bytes.data(),720,_profile.height(),1440);
            if(now<_syncUntil)for(unsigned y=0;y<_profile.height();++y){unsigned temporal=(y&1)^(_settings.bottomFirst?1:0);uint8_t level=(start+temporal*_profile.fieldNS())%1000000000ULL<200000000ULL?235:16;for(unsigned x=0;x<1440;x+=4){auto p=bytes.data()+y*1440+x;p[0]=p[2]=128;p[1]=p[3]=level;}}
            auto pixel=[self pixelWithBytes:bytes.data()];
            if(pixel){std::lock_guard<std::mutex> guard(_picturesLock);while(_pictures.size()>=12)_pictures.pop_front();_pictures.push_back({start,std::move(pixel)});}
        }else for(unsigned field=0;field<2;++field) {
            auto bytes=shuttle::fieldImage(frame.data+offset,v,field);
            controls->apply(bytes.data(),720,_profile.height(),1440);
            if(now<_syncUntil) {
                uint8_t level=(start+field*_profile.fieldNS())%1000000000ULL<200000000ULL?235:16;
                for(size_t n=0;n<bytes.size();n+=4) { bytes[n]=bytes[n+2]=128;bytes[n+1]=bytes[n+3]=level; }
            }
            auto pixel=[self pixelWithBytes:bytes.data()];
            if(!pixel) continue;
            std::lock_guard<std::mutex> guard(_picturesLock);
            while(_pictures.size()>=12) _pictures.pop_front();
            _pictures.push_back({start+field*_profile.fieldNS(),std::move(pixel)});
        }
    }
}
- (void)outputTick {
    if(!_streaming) return;
    @autoreleasepool {
        uint64_t target=_settings.sampleNS(_settings.sampleTickAt(hostNS()-shuttle::PlayoutDelayNS));
        // Preserve timestamps even after a system scheduling stall; bound catch-up work.
        if(target>_nextOutputNS+1000000000ULL) { _outputIndex=_settings.sampleTickAt(target);_nextOutputNS=target; }
        while(_streaming && _nextOutputNS<=target) {
            bool fresh=false;
            { std::lock_guard<std::mutex> guard(_picturesLock);
              while(!_pictures.empty() && _pictures.front().ns<=_nextOutputNS) {
                  _lastFreshNS=_pictures.front().ns;_lastPicture=std::move(_pictures.front().pixel);_pictures.pop_front();fresh=true;
              }
            }
            if(!fresh) ++_held;
            Pixel picture=(_settings.blackOnDropout && (!_lastFreshNS || _nextOutputNS>_lastFreshNS+100000000ULL))?_blackPicture:_lastPicture;
            CMVideoFormatDescriptionRef fmt=nullptr;CMSampleBufferRef sample=nullptr;
            OSStatus rc=CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,picture.get(),&fmt);
            // Core Audio exposes the buffered input at its playout timestamp.
            // Tag video at the same playout instant, keeping both devices aligned.
            uint64_t presentationNS=_nextOutputNS+shuttle::PlayoutDelayNS;
            CMSampleTimingInfo timing{CMTimeMake(_profile.rateDen(),_settings.sampleRateNom()),CMTimeMake(presentationNS,1000000000),kCMTimeInvalid};
            if(!rc) rc=CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,picture.get(),fmt,&timing,&sample);
            if(fmt) CFRelease(fmt);
            if(!rc) {
                [_stream sendSampleBuffer:sample discontinuity:CMIOExtensionStreamDiscontinuityFlagNone hostTimeInNanoseconds:presentationNS];
                CFRelease(sample);++_sequence;
            }
            _nextOutputNS=_settings.sampleNS(++_outputIndex);
        }
    }
}
@end
@interface ShuttleDevice : NSObject <CMIOExtensionDeviceSource>
@property(strong) CMIOExtensionDevice *device;
@property(strong) ShuttleStream *video;
@property(copy) NSDictionary *configuration;
@property(copy) BOOL (^applyConfiguration)(NSDictionary *,NSError **);
- (instancetype)initWithConfiguration:(NSDictionary *)configuration;
@end
@implementation ShuttleDevice
- (instancetype)initWithConfiguration:(NSDictionary *)configuration {
    if((self=[super init])) {
        shuttle::CaptureSettings settings;
        if(!parseSettings(configuration,settings)) return nil;
        NSMutableDictionary *canonical=[defaultSettings() mutableCopy];
        for(NSString *key in defaultSettings()) if(configuration[key]) canonical[key]=configuration[key];
        _configuration=[canonical copy];
        NSString *name=[NSString stringWithFormat:@"Intensity Shuttle — %@ %@",configuration[@"standard"],configuration[@"video_input"]];
        _device=[CMIOExtensionDevice deviceWithLocalizedName:name
             deviceID:[[NSUUID alloc] initWithUUIDString:@"C48BDE00-D3B0-43E1-B576-000000000001"]
             legacyDeviceID:@"local.shuttle.camera.pal" source:self];
        _video=[[ShuttleStream alloc] initWithSettings:settings];
        NSError *error=nil;
        if(!_video || ![_device addStream:_video.stream error:&error]) { NSLog(@"Stream setup failed: %@",error);return nil; }
    }return self;
}
- (NSSet *)availableProperties {
    return [NSSet setWithObjects:CMIOExtensionPropertyDeviceModel,CMIOExtensionPropertyDeviceTransportType,
        CMIOExtensionPropertyDeviceLinkedCoreAudioDeviceUID,SettingsProperty,nil];
}
- (CMIOExtensionDeviceProperties *)devicePropertiesForProperties:(NSSet *)properties error:(NSError **)error {
    auto *p=[CMIOExtensionDeviceProperties devicePropertiesWithDictionary:@{}];
    if([properties containsObject:CMIOExtensionPropertyDeviceModel]) p.model=@"Intensity Shuttle USB 3 (experimental)";
    if([properties containsObject:CMIOExtensionPropertyDeviceTransportType]) p.transportType=@(0x76697274);
    if([properties containsObject:CMIOExtensionPropertyDeviceLinkedCoreAudioDeviceUID]) p.linkedCoreAudioDeviceUID=@"local.shuttle.audio.stereo";
    if([properties containsObject:SettingsProperty]) {
        NSMutableDictionary *state=[_configuration mutableCopy];state[@"detected_standard"]=_video.detectedStandard;
        state[@"capturing"]=@(_video.inUse);state[@"picture_live"]=@YES;state[@"capture_aspect"]=@YES;state[@"capture_interlace"]=@YES;
        auto *attributes=[CMIOExtensionPropertyAttributes propertyAttributesWithMinValue:nil maxValue:nil validValues:nil readOnly:NO];
        [p setPropertyState:[CMIOExtensionPropertyState propertyStateWithValue:settingsJSON(state) attributes:attributes] forProperty:SettingsProperty];
    }return p;
}
- (BOOL)setDeviceProperties:(CMIOExtensionDeviceProperties *)p error:(NSError **)error {
    id value=p.propertiesDictionary[SettingsProperty].value;
    if(!value) return YES;
    NSMutableDictionary *incoming=[settingsDictionary(value) mutableCopy];
    if(incoming && !incoming[@"output_size"]) incoming[@"output_size"]=_configuration[@"output_size"]?:@"Native";
    if(incoming && !incoming[@"input_aspect"]) incoming[@"input_aspect"]=_configuration[@"input_aspect"]?:@"4:3";
    if(incoming && !incoming[@"field_order"])incoming[@"field_order"]=_configuration[@"field_order"]?:@"Top first";
    for(NSString *key in @[@"brightness",@"contrast",@"colour",@"sharpness"]) if(incoming && !incoming[key]) incoming[key]=_configuration[key]?:defaultSettings()[key];
    shuttle::CaptureSettings settings;
    if(!parseSettings(incoming,settings)) { if(error) *error=failure(@"Invalid capture settings.");return NO; }
    NSMutableDictionary *clean=[NSMutableDictionary dictionary];
    for(NSString *key in defaultSettings()) clean[key]=incoming[key]?:defaultSettings()[key];
    if([clean isEqual:_configuration]) return YES;
    BOOL pictureOnly=YES;
    for(NSString *key in @[@"standard",@"video_input",@"audio_input",@"dropout",@"output_size",@"input_aspect",@"field_order"])
        if(![clean[key] isEqual:_configuration[key]])pictureOnly=NO;
    if(pictureOnly){
        // Swap immutable control settings at a frame boundary. The USB engine,
        // stream identity, frame cadence and independent audio keep running.
        [_video updatePicture:settings.picture];_configuration=[clean copy];
        [NSUserDefaults.standardUserDefaults setObject:_configuration forKey:@"ShuttleCaptureSettings"];
        NSMutableDictionary *state=[clean mutableCopy];state[@"capturing"]=@(_video.inUse);state[@"picture_live"]=@YES;state[@"capture_aspect"]=@YES;state[@"capture_interlace"]=@YES;state[@"detected_standard"]=_video.detectedStandard;
        [_device notifyPropertiesChanged:@{SettingsProperty:[CMIOExtensionPropertyState propertyStateWithValue:settingsJSON(state)]}];
        return YES;
    }
    if(_video.inUse) { if(error) *error=failure(@"Close all movie recording and camera windows before changing inputs or format.");return NO; }
    return _applyConfiguration?_applyConfiguration(clean,error):NO;
}
@end

@interface ShuttleProvider : NSObject <CMIOExtensionProviderSource>
@property(strong) CMIOExtensionProvider *provider;
@property(strong) ShuttleDevice *camera;
- (void)attachControls:(ShuttleDevice *)device;
@end
@implementation ShuttleProvider
- (void)attachControls:(ShuttleDevice *)device {
    __weak ShuttleProvider *weakSelf=self;
    device.applyConfiguration=^BOOL(NSDictionary *configuration,NSError **error) {
        ShuttleProvider *strong=weakSelf;if(!strong) return NO;
        ShuttleDevice *old=strong.camera;
        if(old.video.inUse) { if(error) *error=failure(@"Close all camera windows first.");return NO; }
        ShuttleDevice *candidate=[[ShuttleDevice alloc] initWithConfiguration:configuration];
        if(!candidate) { if(error) *error=failure(@"Unable to create the selected format.");return NO; }
        [strong attachControls:candidate];
        if(![strong.provider removeDevice:old.device error:error]) return NO;
        if(![strong.provider addDevice:candidate.device error:error]) {
            [strong.provider addDevice:old.device error:nil];return NO;
        }
        strong.camera=candidate;
        [NSUserDefaults.standardUserDefaults setObject:configuration forKey:@"ShuttleCaptureSettings"];
        NSLog(@"Shuttle settings applied: %@",configuration);return YES;
    };
}
- (instancetype)init {
    if((self=[super init])) {
        _provider=[CMIOExtensionProvider providerWithSource:self clientQueue:dispatch_get_main_queue()];
        NSDictionary *configuration=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ShuttleCaptureSettings"];
        shuttle::CaptureSettings parsed;if(!parseSettings(configuration,parsed)) configuration=defaultSettings();
        _camera=[[ShuttleDevice alloc] initWithConfiguration:configuration];[self attachControls:_camera];
        NSError *error=nil;
        if(!_camera || ![_provider addDevice:_camera.device error:&error]) { NSLog(@"Device setup failed: %@",error);return nil; }
    }return self;
}
- (NSSet *)availableProperties { return [NSSet setWithObjects:CMIOExtensionPropertyProviderName,CMIOExtensionPropertyProviderManufacturer,nil]; }
- (BOOL)connectClient:(CMIOExtensionClient *)client error:(NSError **)error { return YES; }
- (void)disconnectClient:(CMIOExtensionClient *)client {}
- (CMIOExtensionProviderProperties *)providerPropertiesForProperties:(NSSet *)properties error:(NSError **)error {
    auto *p=[CMIOExtensionProviderProperties providerPropertiesWithDictionary:@{}];
    if([properties containsObject:CMIOExtensionPropertyProviderName]) p.name=@"Shuttle Camera";
    if([properties containsObject:CMIOExtensionPropertyProviderManufacturer]) p.manufacturer=@"Local development build";
    return p;
}
- (BOOL)setProviderProperties:(CMIOExtensionProviderProperties *)p error:(NSError **)error { return YES; }
@end
int main(int argc,char **argv) {
    @autoreleasepool {
        ShuttleProvider *source=[ShuttleProvider new];if(!source) return 1;
        if(argc==2 && std::strcmp(argv[1],"--validate")==0) {
            std::printf("Provider: %s\nCamera: %s\nStreams: %lu; formats: %lu\nSettings: %s\n",
                source.provider.source?"OK":"missing",source.camera.device.localizedName.UTF8String,
                (unsigned long)source.camera.device.streams.count,(unsigned long)source.camera.video.formats.count,
                settingsJSON(source.camera.configuration).UTF8String);return 0;
        }
        [CMIOExtensionProvider startServiceWithProvider:source.provider];[[NSRunLoop currentRunLoop] run];
    }return 0;
}
