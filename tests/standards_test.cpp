// GPL-2.0-or-later. NTSC field crop and variable-block stereo packet continuity.
#include "FrameProtocol.hpp"
#include "AudioPacketizer.hpp"
#include <cassert>
#include <cstdio>
int main() {
    shuttle::VideoProfile ntsc{true};
    assert(ntsc.height()==480 && ntsc.fieldNom()==60000 && ntsc.rateDen()==1001);
    assert(ntsc.fieldNS(60000)==1001000000000ULL);
    bmusb::VideoFormat v;v.width=720;v.height=480;v.stride=1440;v.has_signal=v.interlaced=true;
    v.extra_lines_top=17;v.second_field_start=280;v.frame_rate_nom=30000;v.frame_rate_den=1001;
    std::vector<uint8_t> raw(525*1440,0);
    for(unsigned y=0;y<240;++y) for(unsigned x=0;x<1440;++x) {
        raw[(17+y)*1440+x]=50;raw[(280+y)*1440+x]=180;
    }
    bmusb::FrameAllocator::Frame frame;frame.data=raw.data();frame.len=raw.size();
    assert(shuttle::complete(frame,0,v,ntsc));assert(!shuttle::complete(frame,0,v));
    for(unsigned f=0;f<2;++f) { auto image=shuttle::fieldImage(raw.data(),v,f);assert(image.size()==720*480*2);for(auto b:image) assert(b==(f?180:50)); }
    shuttle_audio::Packetizer packetizer;unsigned packets=0;uint64_t total=0,base=1000000000ULL,last=0;
    for(unsigned i=0;i<300;++i) {
        unsigned n=(i%5==4 || i%5==1)?1601:1602;
        uint64_t start=base+total*1000000000ULL/48000;
        packetizer.push(n,start,[](unsigned,unsigned ch){return ch?-0.5f:0.25f;},[&](const shuttle_audio::Packet &p){
            assert(shuttle_audio::valid(p,sizeof(p)));assert(!last || p.hostNS-last>=9999999 && p.hostNS-last<=10000001);
            for(unsigned s=0;s<480;++s) assert(p.samples[s*2]==0.25f && p.samples[s*2+1]==-0.5f);
            last=p.hostNS;++packets;
        });total+=n;
    }
    assert(total==480480 && packets==1001);
    puts("PASS: NTSC 480-line field crop, 60000/1001 timing, 1601/1602 audio blocks, 1001 continuous stereo packets");
}
