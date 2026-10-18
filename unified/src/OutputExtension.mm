// GPL-2.0-or-later. Experimental CMIO sink; no USB access from the extension.
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#include "output/OutputPacket.hpp"
#include "output/SharedOutputCMIO.hpp" // Frozen qualified FCP transport; Premiere uses a separate port.
#include "output/OutputCredits.hpp"
#include "output/TimecodeSample.hpp"
#include <memory>
#include <cmath>
static NSError* outputError(NSString* text){return [NSError errorWithDomain:@"local.shuttle.output" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
@interface SinkStream : NSObject <CMIOExtensionStreamSource> {
    CMIOExtensionStream* _stream;NSArray* _formats;unsigned _index;BOOL _running,_pulling,_ended;
    CMIOExtensionClient* _client;dispatch_source_t _timer;uint64_t _generation,_underruns,_received,_scheduled;
    std::shared_ptr<shuttle_sink::Mapping> _map;
    shuttle_sink::PublicationGuard _publication;
    shuttle_sink::OutputCredits _credits;
}
@property(readonly) CMIOExtensionStream* stream;
@property(readonly) unsigned mode;
@property(readonly) BOOL running;
- (instancetype)initWithMode:(unsigned)mode mapping:(std::shared_ptr<shuttle_sink::Mapping>)mapping;
- (void)poll;
- (void)disconnected:(CMIOExtensionClient*)client;
- (BOOL)keepPublishedWithSenderReady:(BOOL)ready mode:(unsigned)mode;
@end
@implementation SinkStream
- (instancetype)initWithMode:(unsigned)mode mapping:(std::shared_ptr<shuttle_sink::Mapping>)mapping{if((self=[super init])){
    if(mode>=6||!mapping)return nil;_index=mode;_map=std::move(mapping);
    NSMutableArray* formats=[NSMutableArray array];
    // A stream's format list is immutable. Publish a new singleton stream for
    // the actual USB mode, so clients cannot select an unprepared mode.
    {unsigned i=mode;auto p=shuttle_output::profile(static_cast<shuttle_output::Mode>(i));
        NSArray* names=@[@"576i50",@"1080i50",@"1080p25",@"480i59.94",@"1080i59.94",@"1080p29.97"];
        NSMutableDictionary* extensions=[@{(__bridge NSString*)kCMFormatDescriptionExtension_FormatName:names[i],(__bridge NSString*)kCMFormatDescriptionExtension_FieldCount:@(p.interlaced?2:1),
          (__bridge NSString*)kCMFormatDescriptionExtension_YCbCrMatrix:(__bridge NSString*)(p.width==720?kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4:kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2),
          (__bridge NSString*)kCMFormatDescriptionExtension_PixelAspectRatio:@{(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing:@(p.width==720?(p.height==486?9:16):1),(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing:@(p.width==720?(p.height==486?10:15):1)}} mutableCopy];
        if(p.interlaced)extensions[(__bridge NSString*)kCMFormatDescriptionExtension_FieldDetail]=(__bridge NSString*)(i==0||i==3?kCMFormatDescriptionFieldDetail_TemporalBottomFirst:kCMFormatDescriptionFieldDetail_TemporalTopFirst);
        CMVideoFormatDescriptionRef description=nullptr;
        if(CMVideoFormatDescriptionCreate(kCFAllocatorDefault,kCVPixelFormatType_422YpCbCr8,p.width,p.height,(__bridge CFDictionaryRef)extensions,&description))return nil;
        CMTime duration=CMTimeMake(p.rateDen,p.rateNom);
        [formats addObject:[CMIOExtensionStreamFormat streamFormatWithFormatDescription:description maxFrameDuration:duration minFrameDuration:duration validFrameDurations:@[CFBridgingRelease(CMTimeCopyAsDictionary(duration,kCFAllocatorDefault))]]];CFRelease(description);
    }
    _formats=[formats copy];
    // The USB sender reports presentation against host time. Audio is exposed
    // separately and linked by UID; it need not master this software stream.
    _stream=[CMIOExtensionStream streamWithLocalizedName:@"Shuttle HDMI Output (video)" streamID:[[NSUUID alloc] initWithUUIDString:@"C48BDE00-D3B0-43E1-B576-000000000090"] direction:CMIOExtensionStreamDirectionSink clockType:CMIOExtensionStreamClockTypeHostTime source:self];
}return self;}
- (CMIOExtensionStream*)stream{return _stream;}
- (unsigned)mode{return _index;}
- (BOOL)running{return _running;}
- (NSArray*)formats{return _formats;}
- (NSSet*)availableProperties{return [NSSet setWithObjects:CMIOExtensionPropertyStreamActiveFormatIndex,CMIOExtensionPropertyStreamFrameDuration,CMIOExtensionPropertyStreamMaxFrameDuration,CMIOExtensionPropertyStreamSinkBufferQueueSize,CMIOExtensionPropertyStreamSinkBuffersRequiredForStartup,CMIOExtensionPropertyStreamSinkBufferUnderrunCount,CMIOExtensionPropertyStreamSinkEndOfData,CMIOExtensionPropertyStreamLatency,nil];}
- (CMIOExtensionStreamProperties*)streamPropertiesForProperties:(NSSet*)properties error:(NSError**)error{
    auto* result=[CMIOExtensionStreamProperties streamPropertiesWithDictionary:@{}];
    auto p=shuttle_output::profile(static_cast<shuttle_output::Mode>(_index));
    NSDictionary* duration=CFBridgingRelease(CMTimeCopyAsDictionary(CMTimeMake(p.rateDen,p.rateNom),kCFAllocatorDefault));
    if([properties containsObject:CMIOExtensionPropertyStreamActiveFormatIndex])result.activeFormatIndex=@0;
    if([properties containsObject:CMIOExtensionPropertyStreamFrameDuration])result.frameDuration=duration;
    if([properties containsObject:CMIOExtensionPropertyStreamMaxFrameDuration])result.maxFrameDuration=duration;
    if([properties containsObject:CMIOExtensionPropertyStreamSinkBufferQueueSize])result.sinkBufferQueueSize=@8;
    if([properties containsObject:CMIOExtensionPropertyStreamSinkBuffersRequiredForStartup])result.sinkBuffersRequiredForStartup=@2;
    if([properties containsObject:CMIOExtensionPropertyStreamSinkBufferUnderrunCount])result.sinkBufferUnderrunCount=@(_underruns);
    if([properties containsObject:CMIOExtensionPropertyStreamSinkEndOfData])result.sinkEndOfData=@(_ended);
    if([properties containsObject:CMIOExtensionPropertyStreamLatency]){
        // The framework's client queue is reported separately. This is the
        // additional, bounded budget from consume through physical USB output.
        [result setPropertyState:[CMIOExtensionPropertyState propertyStateWithValue:@(shuttle_sink::OutputCredits::Limit)] forProperty:CMIOExtensionPropertyStreamLatency];
    }
    return result;
}
- (BOOL)setStreamProperties:(CMIOExtensionStreamProperties*)properties error:(NSError**)error{
    if(properties.activeFormatIndex&&properties.activeFormatIndex.unsignedIntValue!=0){if(error)*error=outputError(@"Choose the USB output format in Shuttle Camera before enabling A/V Output.");return NO;}
    auto base=shuttle_output::profile(static_cast<shuttle_output::Mode>(_index));
    for(NSDictionary* d in @[properties.frameDuration?:@{},properties.maxFrameDuration?:@{}])if(d.count){
        CMTime requested=CMTimeMakeFromDictionary((__bridge CFDictionaryRef)d);
        if(!CMTIME_IS_NUMERIC(requested)||CMTimeGetSeconds(requested)<=0||std::fabs(1.0/CMTimeGetSeconds(requested)-double(base.rateNom)/base.rateDen)>=0.001){if(error)*error=outputError(@"Frame rate does not match the ready USB output format.");return NO;}
    }
    return YES;
}
- (BOOL)authorizedToStartStreamForClient:(CMIOExtensionClient*)client{if(_running)return NO;_client=client;return YES;}
- (BOOL)startStreamAndReturnError:(NSError**)error{
    if(_running||!_client){if(error)*error=outputError(@"Output already has a client.");return NO;}
    auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(150);
    do{_map->pump();if(_map->data().consumer.load()&&_map->data().mode.load()==_index)break;usleep(1000);}while(std::chrono::steady_clock::now()<deadline);
    if(!_map->data().consumer.load()||_map->data().mode.load()!=_index){_client=nil;if(error)*error=outputError(@"Start timeline output in Shuttle Camera with the matching format before enabling A/V Output in the editor.");NSLog(@"Shuttle output start refused: USB sender is not ready in matching format");return NO;}
    auto& ring=_map->data();if(!ring.consumer.load())ring.read=ring.written.load();ring.mode=_index;ring.producer=1;_received=_scheduled=0;
    _publication.clear();_credits.clear();_running=YES;_pulling=NO;_ended=NO;++_generation;_underruns=0;
    _timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(_timer,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_MSEC,NSEC_PER_MSEC/4);
    __weak SinkStream* weakSelf=self;dispatch_source_set_event_handler(_timer,^{[weakSelf poll];});dispatch_resume(_timer);
    NSLog(@"Shuttle CMIO output started; format %u",_index);return YES;
}
- (BOOL)stopStreamAndReturnError:(NSError**)error{if(_running){
    // Check for a genuine sender EOF before allowing the expected reconnect.
    // A normal client stop resets transport generations, not physical USB.
    _map->pump();BOOL matchingSenderReady=_map->data().consumer.load()&&_map->data().mode.load()==_index;
    _publication.normalStreamStopped(matchingSenderReady);
    _running=NO;++_generation;if(_timer){dispatch_source_cancel(_timer);_timer=nil;}_map->reset();_map->data().mode=_index;_client=nil;_pulling=NO;_credits.clear();
    NSLog(@"Shuttle CMIO output stopped; %llu frames received, %llu scheduled notifications; preserving device during expected sender reconnect: %@",_received,_scheduled,matchingSenderReady?@"yes":@"no");
}return YES;}
- (void)disconnected:(CMIOExtensionClient*)client{if(client==_client)[self stopStreamAndReturnError:nil];}
- (BOOL)keepPublishedWithSenderReady:(BOOL)ready mode:(unsigned)mode{return _publication.keepPublished(ready,mode,_index);}
- (void)poll{
    if(!_running)return;_map->pump();auto& ring=_map->data();
    if(!ring.consumer.load()&&!_ended){_ended=YES;[_stream notifyPropertiesChanged:@{CMIOExtensionPropertyStreamSinkEndOfData:[CMIOExtensionPropertyState propertyStateWithValue:@YES]}];NSLog(@"Shuttle USB sender disconnected; reporting output end of data");}
    if(_ended)return;
    // USB completions can be delivered in batches. Each buffer needs its own
    // scheduled-output event; a latest-only counter silently loses events.
    shuttle_sink::Ack event;
    while(_map->popCompletion(event)){
        if(!_credits.completed(event.sequence)){
            NSLog(@"Shuttle output completion does not match the current outstanding frame; ending stream");
            _ended=YES;[_stream notifyPropertiesChanged:@{CMIOExtensionPropertyStreamSinkEndOfData:[CMIOExtensionPropertyState propertyStateWithValue:@YES]}];return;
        }
        [_stream notifyScheduledOutputChanged:[CMIOExtensionScheduledOutput scheduledOutputWithSequenceNumber:event.sequence hostTimeInNanoseconds:event.hostNS]];
        ++_scheduled;
    }
    if(_pulling||!_credits.available()||ring.written.load()-ring.read.load(std::memory_order_acquire)>=shuttle_sink::Count)return;
    _pulling=YES;uint64_t generation=_generation;__weak SinkStream* weakSelf=self;
    [_stream consumeSampleBufferFromClient:_client completionHandler:^(CMSampleBufferRef sample,uint64_t sequence,CMIOExtensionStreamDiscontinuityFlags flags,BOOL more,NSError* error){
        id owned=sample?CFBridgingRelease(CFRetain(sample)):nil;
        dispatch_async(dispatch_get_main_queue(),^{CMSampleBufferRef sample=(__bridge CMSampleBufferRef)owned;SinkStream* strong=weakSelf;if(!strong||!strong->_running||generation!=strong->_generation)return;
        strong->_pulling=NO;if(!sample){if(error)NSLog(@"Shuttle sink consume: %@",error);return;}
        auto image=CMSampleBufferGetImageBuffer(sample);auto p=shuttle_output::profile(static_cast<shuttle_output::Mode>(strong->_index));
        if(!image||CVPixelBufferGetPixelFormatType(image)!=kCVPixelFormatType_422YpCbCr8||CVPixelBufferGetWidth(image)!=p.width||CVPixelBufferGetHeight(image)!=p.height){NSLog(@"Shuttle sink received unsupported image");return;}
        auto& r=strong->_map->data();uint64_t write=r.written.load();if(write-r.read.load(std::memory_order_acquire)>=shuttle_sink::Count)return;
        auto& slot=r.slots[write%shuttle_sink::Count];slot.sequence=sequence;slot.width=p.width;slot.height=p.height;
        slot.timecode=shuttle_sink::sampleTimecode(sample);
        CMTime pts=CMSampleBufferGetPresentationTimeStamp(sample);slot.hostNS=CMTIME_IS_NUMERIC(pts)?CMTimeConvertScale(pts,1000000000,kCMTimeRoundingMethod_Default).value:0;
        CVPixelBufferLockBaseAddress(image,kCVPixelBufferLock_ReadOnly);
        for(unsigned y=0;y<p.height;++y)memcpy(slot.image+size_t(y)*p.width*2,static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(image))+size_t(y)*CVPixelBufferGetBytesPerRow(image),p.width*2);
        CVPixelBufferUnlockBaseAddress(image,kCVPixelBufferLock_ReadOnly);
        if(!strong->_credits.consumed(sequence))return;
        r.written.store(write+1,std::memory_order_release);++strong->_received;
        });
    }];
}
@end
@interface SinkDevice : NSObject <CMIOExtensionDeviceSource>
@property CMIOExtensionDevice* device;@property SinkStream* video;
- (instancetype)initWithMode:(unsigned)mode mapping:(std::shared_ptr<shuttle_sink::Mapping>)mapping;
@end
@implementation SinkDevice
- (instancetype)initWithMode:(unsigned)mode mapping:(std::shared_ptr<shuttle_sink::Mapping>)mapping{if((self=[super init])){self.video=[[SinkStream alloc] initWithMode:mode mapping:std::move(mapping)];if(!self.video)return nil;self.device=[CMIOExtensionDevice deviceWithLocalizedName:@"Intensity Shuttle — HDMI Output" deviceID:[[NSUUID alloc] initWithUUIDString:@"C48BDE00-D3B0-43E1-B576-000000000091"] legacyDeviceID:@"local.shuttle.output.cmio" source:self];if(![self.device addStream:self.video.stream error:nil])return nil;}return self;}
- (NSSet*)availableProperties{return [NSSet setWithObjects:CMIOExtensionPropertyDeviceModel,CMIOExtensionPropertyDeviceTransportType,CMIOExtensionPropertyDeviceLinkedCoreAudioDeviceUID,nil];}
- (CMIOExtensionDeviceProperties*)devicePropertiesForProperties:(NSSet*)properties error:(NSError**)error{auto* p=[CMIOExtensionDeviceProperties devicePropertiesWithDictionary:@{}];if([properties containsObject:CMIOExtensionPropertyDeviceModel])p.model=@"Intensity Shuttle HDMI Output — experimental";if([properties containsObject:CMIOExtensionPropertyDeviceTransportType])p.transportType=@(0x76697274);if([properties containsObject:CMIOExtensionPropertyDeviceLinkedCoreAudioDeviceUID])p.linkedCoreAudioDeviceUID=@"local.shuttle.audio.hdmi";return p;}
- (BOOL)setDeviceProperties:(CMIOExtensionDeviceProperties*)properties error:(NSError**)error{return YES;}
@end
@interface SinkProvider : NSObject <CMIOExtensionProviderSource> {
    std::shared_ptr<shuttle_sink::Mapping> _map;
    dispatch_source_t _readinessTimer;
}
@property CMIOExtensionProvider* provider;@property SinkDevice* output;
- (void)checkUSBReadiness;
@end
@implementation SinkProvider
- (instancetype)init{if((self=[super init])){
    self.provider=[CMIOExtensionProvider providerWithSource:self clientQueue:dispatch_get_main_queue()];
    _map=std::make_shared<shuttle_sink::Mapping>();
    try{_map->open(true);}catch(const std::exception& e){NSLog(@"Shuttle sink transport: %s",e.what());return nil;}
    // Enumerating the provider starts this service even when it has no devices.
    // The hello is released only after a successful physical USB transfer.
    _readinessTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(_readinessTimer,dispatch_time(DISPATCH_TIME_NOW,0),10*NSEC_PER_MSEC,NSEC_PER_MSEC);
    __weak SinkProvider* weakSelf=self;dispatch_source_set_event_handler(_readinessTimer,^{[weakSelf checkUSBReadiness];});dispatch_resume(_readinessTimer);
}return self;}
- (void)checkUSBReadiness {
    _map->pump(!self.output.video.running);
    auto& ring=_map->data();BOOL ready=ring.consumer.load();unsigned mode=ring.mode.load();
    if(self.output&&![self.output.video keepPublishedWithSenderReady:ready mode:mode]){
        NSError* error=nil;
        if(![self.provider removeDevice:self.output.device error:&error]){NSLog(@"Shuttle could not withdraw HDMI output: %@",error);return;}
        [self.output.video stopStreamAndReturnError:nil];self.output=nil;
        NSLog(@"Shuttle HDMI output withdrawn: USB sender is not ready.");
        ready=_map->data().consumer.load();mode=_map->data().mode.load();
    }
    if(!self.output&&ready&&mode<6){
        SinkDevice* output=[[SinkDevice alloc] initWithMode:mode mapping:_map];NSError* error=nil;
        if(!output||![self.provider addDevice:output.device error:&error]){NSLog(@"Shuttle could not publish ready HDMI output: %@",error);return;}
        self.output=output;NSLog(@"Shuttle HDMI output ready and published; USB format %u",mode);
    }
}
- (void)dealloc{if(_readinessTimer)dispatch_source_cancel(_readinessTimer);}
- (NSSet*)availableProperties{return [NSSet setWithObjects:CMIOExtensionPropertyProviderName,CMIOExtensionPropertyProviderManufacturer,nil];}
- (BOOL)connectClient:(CMIOExtensionClient*)client error:(NSError**)error{return YES;}
- (void)disconnectClient:(CMIOExtensionClient*)client{[self.output.video disconnected:client];}
- (CMIOExtensionProviderProperties*)providerPropertiesForProperties:(NSSet*)properties error:(NSError**)error{auto* p=[CMIOExtensionProviderProperties providerPropertiesWithDictionary:@{}];if([properties containsObject:CMIOExtensionPropertyProviderName])p.name=@"Shuttle HDMI Output";if([properties containsObject:CMIOExtensionPropertyProviderManufacturer])p.manufacturer=@"Local development build";return p;}
- (BOOL)setProviderProperties:(CMIOExtensionProviderProperties*)properties error:(NSError**)error{return YES;}
@end
int main(int argc,char**argv){@autoreleasepool{if(argc==2&&!strcmp(argv[1],"--validate")){
    auto mapping=std::make_shared<shuttle_sink::Mapping>();mapping->open(true);NSMutableArray* descriptions=[NSMutableArray array];
    for(unsigned i=0;i<6;++i){SinkStream* stream=[[SinkStream alloc] initWithMode:i mapping:mapping];NSArray* formats=stream.formats;if(formats.count!=1)return 2;CMIOExtensionStreamFormat* f=formats[0];auto p=shuttle_output::profile(static_cast<shuttle_output::Mode>(i));if(f.validFrameDurations.count!=1||CMTimeCompare(CMTimeMakeFromDictionary((__bridge CFDictionaryRef)f.validFrameDurations[0]),CMTimeMake(p.rateDen,p.rateNom)))return 3;for(id other in descriptions)if(CMFormatDescriptionEqual(f.formatDescription,(__bridge CMFormatDescriptionRef)other))return 4;[descriptions addObject:(__bridge id)f.formatDescription];if([stream streamPropertiesForProperties:[NSSet setWithObject:CMIOExtensionPropertyStreamActiveFormatIndex] error:nil].activeFormatIndex.unsignedIntValue)return 5;}
    for(unsigned i=0;i<6;++i){SinkStream* stream=[[SinkStream alloc] initWithMode:i mapping:mapping];auto* props=[stream streamPropertiesForProperties:[NSSet setWithObject:CMIOExtensionPropertyStreamLatency] error:nil];CMIOExtensionPropertyState* state=props.propertiesDictionary[CMIOExtensionPropertyStreamLatency];if(![stream.availableProperties containsObject:CMIOExtensionPropertyStreamLatency]||![state.value isEqual:@(shuttle_sink::OutputCredits::Limit)])return 6;}
    puts("PASS: Six singleton USB-ready output formats with exact discrete PAL/NTSC durations and bounded six-frame stream latency");return 0;
}SinkProvider* source=[SinkProvider new];if(!source)return 1;[CMIOExtensionProvider startServiceWithProvider:source.provider];[[NSRunLoop currentRunLoop] run];}return 0;}
