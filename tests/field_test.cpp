// GPL-2.0-or-later. Known PAL field fixture: ensure fields never blend together.
#include "FrameProtocol.hpp"
#include <cassert>
#include <cstdio>
int main() {
    bmusb::VideoFormat v;
    v.width=720;v.height=576;v.stride=1440;v.interlaced=true;v.has_signal=true;
    v.frame_rate_nom=25;v.frame_rate_den=1;v.extra_lines_top=22;v.second_field_start=335;
    std::vector<uint8_t> raw(625*1440,0);
    for(unsigned row=0;row<288;++row) {
        for(unsigned x=0;x<1440;x+=4) {
            for(unsigned field=0;field<2;++field) {
                auto *p=raw.data()+((field?335:22)+row)*1440+x;
                p[0]=p[2]=128;p[1]=p[3]=field?180:50;
            }
        }
    }
    bmusb::FrameAllocator::Frame f;f.data=raw.data();f.len=raw.size();
    assert(shuttle::complete(f,0,v));
    f.len=100;assert(!shuttle::complete(f,0,v));
    for(unsigned field=0;field<2;++field) {
        auto pixels=shuttle::fieldImage(raw.data(),v,field);
        assert(pixels.size()==shuttle::Bytes);
        for(size_t x=0;x<pixels.size();x+=4) {
            assert(pixels[x]==128 && pixels[x+2]==128);
            assert(pixels[x+1]==(field?180:50) && pixels[x+3]==(field?180:50));
        }
    }
    shuttle::Header h;assert(shuttle::valid(h));h.payload+=1;assert(!shuttle::valid(h));
    std::puts("PASS: PAL bounds, blanking crop, distinct fields, edge reconstruction, packet validation");
}
