// GPL-2.0-or-later. Native CMIO output-client probe and moving-pattern test.
#import <Foundation/Foundation.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMediaIO/CMIOSampleBuffer.h>
#import <CoreVideo/CoreVideo.h>
#include <vector>
#include <chrono>
#include "../src/output/OutputPacket.hpp"
static int modeForFormat(CMFormatDescriptionRef format, CFIndex count, unsigned index) {
    CFTypeRef value=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FormatName);
    if(value&&CFGetTypeID(value)==CFStringGetTypeID()){
        const CFStringRef names[]={CFSTR("576i50"),CFSTR("1080i50"),CFSTR("1080p25"),CFSTR("480i59.94"),CFSTR("1080i59.94"),CFSTR("1080p29.97")};
        for(unsigned mode=0;mode<6;++mode)if(CFEqual(value,names[mode]))return int(mode);
    }
    // Legacy extension 7 exposed all six modes in a stable order. Singleton
    // extension 8 must identify its actual mode; index zero is not always PAL.
    return count==6&&index<6?int(index):-1;
}
static OSStatus read(CMIOObjectID object,CMIOObjectPropertySelector selector,UInt32 scope,void* value,UInt32 bytes){CMIOObjectPropertyAddress address{selector,scope,0};return CMIOObjectGetPropertyData(object,&address,0,nullptr,bytes,&bytes,value);}
int main(int argc,char**argv){@autoreleasepool{
    CMIOObjectPropertyAddress address{kCMIOHardwarePropertyDevices,kCMIOObjectPropertyScopeGlobal,0};UInt32 size=0;
    if(CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject,&address,0,nullptr,&size))return 1;
    std::vector<CMIOObjectID> devices(size/4);if(CMIOObjectGetPropertyData(kCMIOObjectSystemObject,&address,0,nullptr,size,&size,devices.data()))return 1;
    CMIOObjectID device=0,stream=0;
    for(auto d:devices){CFStringRef uid=nullptr;if(read(d,kCMIODevicePropertyDeviceUID,kCMIOObjectPropertyScopeGlobal,&uid,sizeof(uid)))continue;bool match=uid&&CFEqual(uid,CFSTR("local.shuttle.output.cmio"));if(uid)CFRelease(uid);if(match){device=d;break;}}
    if(!device){puts("Shuttle HDMI output device not found");return 2;}
    for(auto selector:{kCMIODevicePropertyLinkedCoreAudioDeviceUID,kCMIODevicePropertyLinkedAndSyncedCoreAudioDeviceUID}){CFStringRef uid=nullptr;OSStatus status=read(device,selector,kCMIOObjectPropertyScopeGlobal,&uid,sizeof(uid));printf("Linked audio selector %08x: status %d; UID %s\n",selector,int(status),uid?[(__bridge NSString*)uid UTF8String]:"(none)");if(uid)CFRelease(uid);}
    UInt32 eligible=0;OSStatus eligibility=read(device,kCMIODevicePropertyDeviceCanBeDefaultDevice,kCMIODevicePropertyScopeOutput,&eligible,sizeof(eligible));printf("Eligible as default output: %u (status %d)\n",eligible,int(eligibility));
    address={kCMIODevicePropertyStreams,kCMIODevicePropertyScopeOutput,0};size=0;
    if(CMIOObjectGetPropertyDataSize(device,&address,0,nullptr,&size)||!size)return 3;
    std::vector<CMIOObjectID> streams(size/4);if(CMIOObjectGetPropertyData(device,&address,0,nullptr,size,&size,streams.data()))return 3;stream=streams.front();
    address={kCMIOStreamPropertyInitialPresentationTimeStampForLinkedAndSyncedAudio,kCMIOObjectPropertyScopeGlobal,0};printf("Synced-audio initial PTS property present: %d\n",int(CMIOObjectHasProperty(stream,&address)));
    CFTypeRef clock=nullptr;if(!read(stream,kCMIOStreamPropertyClock,kCMIOObjectPropertyScopeGlobal,&clock,sizeof(clock))&&clock){CMTime t=CMIOStreamClockConvertHostTimeToDeviceTime(CVGetCurrentHostTime(),clock);printf("Stream clock now: %.6f s (flags %u)\n",CMTimeGetSeconds(t),t.flags);CFRelease(clock);}
    CFArrayRef formats=nullptr;if(read(stream,kCMIOStreamPropertyFormatDescriptions,kCMIOObjectPropertyScopeGlobal,&formats,sizeof(formats))||!formats)return 4;
    CMFormatDescriptionRef active=nullptr;if(!read(stream,kCMIOStreamPropertyFormatDescription,kCMIOObjectPropertyScopeGlobal,&active,sizeof(active))&&active){for(CFIndex n=0;n<CFArrayGetCount(formats);++n)if(CMFormatDescriptionEqual(active,static_cast<CMFormatDescriptionRef>(CFArrayGetValueAtIndex(formats,n))))printf("Active format index: %ld\n",n);CFRelease(active);}
    printf("CMIO output device %u; stream %u; formats %ld\n",device,stream,CFArrayGetCount(formats));
    for(CFIndex n=0;n<CFArrayGetCount(formats);++n){auto f=static_cast<CMVideoFormatDescriptionRef>(CFArrayGetValueAtIndex(formats,n));auto d=CMVideoFormatDescriptionGetDimensions(f);printf("Format %ld: %dx%d; name %s; field metadata %s\n",n,d.width,d.height,[(__bridge id)CMFormatDescriptionGetExtension(f,kCMFormatDescriptionExtension_FormatName) description].UTF8String,[(__bridge id)CMFormatDescriptionGetExtension(f,kCMFormatDescriptionExtension_FieldCount) description].UTF8String);}
    if(argc==1||!strcmp(argv[1],"--list")){CFRelease(formats);return 0;}
    bool configure=argc==3&&!strcmp(argv[1],"--set-format");unsigned index=unsigned(atoi(argv[configure?2:1]));if(index>=unsigned(CFArrayGetCount(formats)))return 64;
    unsigned seconds=configure?1:argc>=3?unsigned(atoi(argv[2])):10;if(!seconds||seconds>60)return 64;
    auto format=static_cast<CMVideoFormatDescriptionRef>(CFArrayGetValueAtIndex(formats,index));
    int mode=modeForFormat(format,CFArrayGetCount(formats),index);if(mode<0){fputs("Cannot identify output mode from singleton format name\n",stderr);CFRelease(formats);return 4;}
    auto p=shuttle_output::profile(static_cast<shuttle_output::Mode>(mode));
    auto dimensions=CMVideoFormatDescriptionGetDimensions(format);if(dimensions.width!=int(p.width)||dimensions.height!=int(p.height)){fputs("Output format name/dimensions disagree\n",stderr);CFRelease(formats);return 4;}
    printf("Selected list index %u maps to wire mode %d (%ux%u at %.9f fps)\n",index,mode,p.width,p.height,double(p.rateNom)/p.rateDen);
    address={kCMIOStreamPropertyFormatDescription,kCMIOObjectPropertyScopeGlobal,0};OSStatus rc=CMIOObjectSetPropertyData(stream,&address,0,nullptr,sizeof(format),&format);if(rc){printf("Set format: %d\n",int(rc));return 5;}
    Float64 rate=double(p.rateNom)/p.rateDen;address={kCMIOStreamPropertyFrameRate,kCMIOObjectPropertyScopeGlobal,0};rc=CMIOObjectSetPropertyData(stream,&address,0,nullptr,sizeof(rate),&rate);if(rc){printf("Set frame rate: %d\n",int(rc));return 5;}
    if(configure){CFRelease(formats);puts("Output format selected; stream not started");return 0;}
    CMSimpleQueueRef queue=nullptr;rc=CMIOStreamCopyBufferQueue(stream,[](CMIOStreamID,void*,void*){},nullptr,&queue);if(rc||!queue){printf("Copy output queue: %d\n",int(rc));return 6;}
    rc=CMIODeviceStartStream(device,stream);if(rc){printf("Start output: %d\n",int(rc));return 7;}
    auto start=std::chrono::steady_clock::now();CMTime first=getenv("SHUTTLE_TEST_RELATIVE_PTS")?kCMTimeZero:CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),CMTimeMake(1,10));unsigned count=0;
    while(std::chrono::steady_clock::now()-start<std::chrono::seconds(seconds)){
        double time=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
        if(CMSimpleQueueGetCount(queue)>=CMSimpleQueueGetCapacity(queue)||double(count)*p.rateDen/p.rateNom>time){CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.002,true);continue;}
        CVPixelBufferRef image=nullptr;CVPixelBufferCreate(kCFAllocatorDefault,p.width,p.height,kCVPixelFormatType_422YpCbCr8,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey:@{}},&image);if(!image)break;
        CVPixelBufferLockBaseAddress(image,0);unsigned left=count*12%(p.width-160);
        for(unsigned y=0;y<p.height;++y){auto* row=static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(image))+y*CVPixelBufferGetBytesPerRow(image);for(unsigned x=0;x<p.width;x+=2){bool block=y>p.height/3&&y<p.height/3+100&&x>=left&&x<left+160;row[x*2]=block?128:240;row[x*2+1]=block?235:41;row[x*2+2]=block?128:110;row[x*2+3]=block?235:41;}}
        CVPixelBufferUnlockBaseAddress(image,0);CMSampleTimingInfo timing{CMTimeMake(p.rateDen,p.rateNom),CMTimeAdd(first,CMTimeMake(int64_t(count)*p.rateDen,p.rateNom)),kCMTimeInvalid};CMSampleBufferRef sample=nullptr;
        CVBufferSetAttachments(image,CMFormatDescriptionGetExtensions(format),kCVAttachmentMode_ShouldPropagate);
        CMVideoFormatDescriptionRef sampleFormat=nullptr;rc=CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,image,&sampleFormat);
        if(!rc)rc=CMIOSampleBufferCreateForImageBuffer(kCFAllocatorDefault,image,sampleFormat,&timing,count,0,&sample);if(sampleFormat)CFRelease(sampleFormat);CFRelease(image);if(rc)break;
        rc=CMSimpleQueueEnqueue(queue,sample);if(rc){CFRelease(sample);break;}++count;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.3,false);CMIODeviceStopStream(device,stream);
    while(CMSimpleQueueGetCount(queue)){auto sample=CMSimpleQueueDequeue(queue);if(sample)CFRelease(sample);}
    CFRelease(queue);CFRelease(formats);printf("Sent %u frames; last enqueue status %d\n",count,int(rc));return count>seconds*20&&rc==0?0:8;
}return 0;}
