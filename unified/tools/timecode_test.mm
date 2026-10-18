// No USB or apps. Real CMSampleBuffer attachments and isolated loopback.
#import <Foundation/Foundation.h>
#include "LoopbackTestPort.hpp"
#include "../src/output/SharedOutput.hpp"
#undef htons
#include "../src/output/TimecodeSample.hpp"
#include <cassert>
#include <thread>
#include <fstream>
static shuttle_sink::Timecode Expected(unsigned n){
    if(n%3==0)return {};
    // Nonmonotonic timeline values model scrubbing and seeks, not elapsed time.
    return {1,uint8_t(n%24),uint8_t((90-n)%60),uint8_t(n%60),uint8_t((73-n)%30),uint8_t(n%2),30,0};
}
int main(int argc,char**argv){@autoreleasepool{
    using namespace shuttle_sink;
    CVPixelBufferRef image=nullptr;assert(!CVPixelBufferCreate(nullptr,32,16,kCVPixelFormatType_422YpCbCr8,nullptr,&image));
    CMVideoFormatDescriptionRef format=nullptr;assert(!CMVideoFormatDescriptionCreateForImageBuffer(nullptr,image,&format));
    CMSampleTimingInfo timing{CMTimeMake(1,25),CMTimeMake(123,1),kCMTimeInvalid};CMSampleBufferRef sample=nullptr;
    assert(!CMSampleBufferCreateForImageBuffer(nullptr,image,true,nullptr,nullptr,format,&timing,&sample));assert(!sampleTimecode(sample).valid);
    SMPTETime smpte{};smpte.mFlags=kSMPTETimeValid;smpte.mHours=1;smpte.mMinutes=2;smpte.mSeconds=3;smpte.mFrames=4;
    for(unsigned type=0;type<=11;++type){
        smpte.mType=static_cast<SMPTETimeType>(type);CFDataRef data=CFDataCreate(nullptr,reinterpret_cast<UInt8*>(&smpte),sizeof(smpte));
        CMSetAttachment(sample,kCMIOSampleBufferAttachmentKey_SMPTETime,data,kCMAttachmentMode_ShouldPropagate);CFRelease(data);
        auto code=sampleTimecode(sample);assert(validTimecode(code));char text[16];timecodeText(code,text);
        assert(!strncmp(text,"01:02:03:04",11));assert(code.drop==(type==2||type==5||type==8||type==9));
    }
    smpte.mFrames=60;CFDataRef bad=CFDataCreate(nullptr,reinterpret_cast<UInt8*>(&smpte),sizeof(smpte));
    CMSetAttachment(sample,kCMIOSampleBufferAttachmentKey_SMPTETime,bad,kCMAttachmentMode_ShouldPropagate);CFRelease(bad);assert(!sampleTimecode(sample).valid);
    CMSetAttachment(sample,kCMIOSampleBufferAttachmentKey_SMPTETime,CFSTR("bad"),kCMAttachmentMode_ShouldPropagate);assert(!sampleTimecode(sample).valid);
    CFRelease(sample);CFRelease(format);CVPixelBufferRelease(image);
    char text[16];timecodeText({},text);assert(!strcmp(text,"--:--:--:--"));
    Timecode df{1,0,1,0,2,1,30,0};timecodeText(df,text);assert(!strcmp(text,"00:01:00:02 DF"));
    for(auto size:std::vector<std::pair<unsigned,unsigned>>{{720,576},{720,486},{1920,1080}}){
        auto w=size.first,h=size.second;std::vector<uint8_t> pixels(size_t(w)*h*2,80),original=pixels;
        overlayTimecode(pixels,w,h,df);unsigned changed=0,white=0;
        for(size_t i=0;i<pixels.size();++i)if(pixels[i]!=original[i]){++changed;if(i%2)assert(pixels[i]>=48&&pixels[i]<=235);else assert(pixels[i]>=104&&pixels[i]<=128);if(pixels[i]==235)++white;}
        assert(changed&&white); // drawn, in bounds and legal-range UYVY
        if(argc==2&&w==1920){
            std::ofstream ppm(argv[1],std::ios::binary);ppm<<"P6\n"<<w<<" "<<h<<"\n255\n";
            for(size_t n=0;n<size_t(w)*h;++n){uint8_t gray=pixels[n*2+1];char rgb[3]={char(gray),char(gray),char(gray)};ppm.write(rgb,3);}
        }
    }
    ChooseLoopbackTestPort();Mapping map;map.open(true);Reader reader(2);unsigned sent=0,received=0;std::vector<uint8_t> pixels;
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(4);
    while(received<60&&std::chrono::steady_clock::now()<deadline){
        map.pump();reader.pump(32,16);
        if(map.data().consumer&&sent<60&&map.data().written-map.data().read<Count){
            auto w=map.data().written.load();auto& frame=map.data().slots[w%Count];frame.sequence=sent;frame.hostNS=sent*33333333ULL;frame.width=32;frame.height=16;frame.timecode=Expected(sent);memset(frame.image,sent,1024);map.data().written=w+1;++sent;
        }
        reader.read(pixels,32,16);if(reader.acknowledge){
            assert(reader.sequence==received);auto expected=Expected(received);assert(!memcmp(&reader.timecode,&expected,sizeof(expected)));
            for(auto byte:pixels)assert(byte==received);
            reader.played(reader.sequence,1000+received,reader.generation);++received;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(received==60);auto held=reader.timecode;reader.read(pixels,32,16);assert(!reader.acknowledge&&!memcmp(&held,&reader.timecode,sizeof(held)));
    puts("PASS: 12 SMPTE types; exact colon formatting/DF label; missing/malformed metadata; PAL/NTSC/HD legal-range overlay; 60 frame-bound metadata roundtrips, seeks, missing metadata clears and held-picture association");
    return 0;
}}
