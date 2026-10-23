// GPL-2.0-or-later. USB playback framing; see validation for tested modes.
#pragma once
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace shuttle_output {
enum class Mode { PAL576i50, HD1080i50, HD1080p25, NTSC480i5994, HD1080i5994, HD1080p2997 };
struct Profile {
    unsigned width, height, totalLines, firstActive, secondActive, localAddress;
    bool interlaced, firstOdd;
    unsigned rateNom,rateDen;
    uint64_t audioStart(uint64_t frame)const{return frame*48000*rateDen/rateNom;}
    unsigned audioFrames(uint64_t frame)const{return unsigned(audioStart(frame+1)-audioStart(frame));}
    unsigned maxAudio()const{return (48000*rateDen+rateNom-1)/rateNom;}
    double pixelAspect()const{return width==720?(height==486?9.0/10.0:16.0/15.0):1.0;}
};
inline Profile profile(Mode mode) {
    switch(mode) {
    case Mode::PAL576i50: return {720,576,625,23,336,0x0120,true,false,25,1};
    case Mode::HD1080i50: return {1920,1080,1125,21,584,0x4220,true,false,25,1};
    case Mode::HD1080p25: return {1920,1080,1125,42,0,0x4320,false,false,25,1};
    case Mode::NTSC480i5994: return {720,486,525,18,280,0x0020,true,true,30000,1001};
    case Mode::HD1080i5994: return {1920,1080,1125,21,584,0x8120,true,false,30000,1001};
    case Mode::HD1080p2997: return {1920,1080,1125,42,0,0x8f20,false,false,30000,1001};
    }
    throw std::invalid_argument("Unsupported output mode");
}
inline void put32(std::vector<uint8_t>& out, uint32_t value) {
    for(unsigned n=0;n<4;++n) out.push_back(uint8_t(value>>(8*n)));
}

// Produces a full wire frame with vertical blanking and silent eight-channel
// PCM24 audio. Input is exactly one progressive-raster UYVY image. The wire
// field ordering follows the USB protocol; capture bob images need conversion
// to the chosen interlaced/progressive cadence before calling this encoder.
inline std::vector<uint8_t> encode(Mode mode, const uint8_t* image,
                                  size_t imageBytes, size_t stride,
                                  const int32_t* audio=nullptr, size_t audioSamples=0,
                                  uint64_t frameIndex=0) {
    const auto p=profile(mode);
    const size_t rowBytes=p.width*2;
    if(!image || stride<rowBytes || imageBytes<rowBytes ||
       (p.height-1)>((imageBytes-rowBytes)/stride))
        throw std::invalid_argument("Invalid image size or stride");
    const unsigned actual=p.audioFrames(frameIndex);
    if(audio && audioSamples!=actual*8) throw std::invalid_argument("Unexpected PCM sample count");
    const unsigned groups=p.totalLines/5, samples=p.maxAudio();
    std::vector<uint8_t> out;
    out.reserve(16+rowBytes*p.totalLines+groups*8+samples*24);
    put32(out,0xffff0000);put32(out,0x6b636544);put32(out,0x6b6e694c);
    put32(out,0x56640000|p.localAddress);
    for(unsigned line=1;line<=p.totalLines;++line) {
        if((line-1)%5==0) {
            const unsigned group=(line-1)/5;
            const unsigned count=((group+1)*samples/groups)-(group*samples/groups);
            put32(out,0xffff0000);put32(out,(0x64754101+count)|((group+1==groups&&actual<samples)?0x80:0));
            const unsigned first=group*samples/groups;
            for(unsigned sample=first;sample<first+count;++sample) for(unsigned channel=0;channel<8;++channel) {
                uint32_t value=audio&&sample<actual?uint32_t(audio[sample*8+channel]):0;
                for(unsigned byte=0;byte<3;++byte)out.push_back(uint8_t(value>>(byte*8)));
            }
        }
        int sourceRow=-1;
        if(p.interlaced) {
            if(line>=p.firstActive && line<p.firstActive+p.height/2)
                sourceRow=int((line-p.firstActive)*2+unsigned(p.firstOdd));
            else if(line>=p.secondActive && line<p.secondActive+p.height/2)
                sourceRow=int((line-p.secondActive)*2+unsigned(!p.firstOdd));
        } else if(line>=p.firstActive && line<p.firstActive+p.height)
            sourceRow=int(line-p.firstActive);
        if(sourceRow>=0) {
            auto row=image+size_t(sourceRow)*stride;
            out.insert(out.end(),row,row+rowBytes);
        } else {
            for(unsigned pair=0;pair<p.width/2;++pair) put32(out,0x10801080);
        }
    }
    return out;
}
}
