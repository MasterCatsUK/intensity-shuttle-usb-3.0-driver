// GPL-2.0-or-later. PAL field conversion and diagnostic packet format, little endian, arm64.
#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include <algorithm>
#include "bmusb/bmusb.h"
#include "VideoProfile.hpp"

namespace shuttle {
constexpr uint32_t Width = 720, Height = 576, Stride = Width * 2;
constexpr uint32_t Bytes = Stride * Height;
constexpr uint32_t Magic = 0x31564853; // SHV1
struct Header {
    uint32_t magic = Magic, version = 1, payload = Bytes, width = Width;
    uint32_t height = Height, stride = Stride, field = 0, reserved = 0;
    uint64_t host_ns = 0, sequence = 0;
};
static_assert(sizeof(Header) == 48, "Protocol layout changed");
inline bool valid(const Header &h) {
    return h.magic == Magic && h.version == 1 && h.payload == Bytes &&
        h.width == Width && h.height == Height && h.stride == Stride && h.field < 2;
}
inline bool complete(bmusb::FrameAllocator::Frame frame, size_t offset,
                     const bmusb::VideoFormat &v, VideoProfile profile={}) {
    if (!v.has_signal || !v.interlaced || v.width != Width || v.height != profile.height() ||
        v.stride != Stride || v.frame_rate_nom != profile.rateNom() || v.frame_rate_den != profile.rateDen() ||
        !frame.data || offset > frame.len) return false;
    size_t last = v.second_field_start == 1 ? v.extra_lines_top + profile.height()-1 :
        std::max(v.extra_lines_top, v.second_field_start) + profile.height()/2-1;
    return (last + 1) * v.stride <= frame.len - offset;
}

// One progressive image per captured field. Keep that field's original rows;
// interpolate missing rows from adjacent rows of the SAME field (linear bob).
// This retains 50 distinct motion instants, without blending the two fields.
inline std::vector<uint8_t> fieldImage(const uint8_t *data,
                                      const bmusb::VideoFormat &v, unsigned field) {
    unsigned height=v.height;
    unsigned rows=height/2;
    std::vector<uint8_t> out(Stride*height);
    auto row = [&](int n) {
        n = std::max(0, std::min(int(rows)-1, n));
        size_t source = v.second_field_start == 1 ? v.extra_lines_top + 2*n + field :
            (field ? v.second_field_start : v.extra_lines_top) + n;
        return data + source * Stride;
    };
    for (unsigned y = 0; y < height; ++y) {
        uint8_t *dest = out.data() + y * Stride;
        if ((y & 1) == field) std::memcpy(dest, row(y / 2), Stride);
        else {
            int before = (int(y) - int(field) - 1) / 2;
            if (y == 0 && field == 1) before = -1;
            const uint8_t *a = row(before), *b = row(before + 1);
            for (unsigned x = 0; x < Stride; ++x) dest[x] = (unsigned(a[x]) + b[x] + 1) / 2;
        }
    }
    return out;
}
// Preserve the two captured instants as alternating rows, without bob interpolation.
// Source field zero is the first temporal field used by the existing capture path.
inline std::vector<uint8_t> weaveImage(const uint8_t *data,const bmusb::VideoFormat &v,bool bottomFirst) {
    std::vector<uint8_t> out(Stride*v.height);
    for(unsigned field=0;field<2;++field)for(unsigned row=0;row<v.height/2;++row){
        size_t source=v.second_field_start==1?v.extra_lines_top+2*row+field:(field?v.second_field_start:v.extra_lines_top)+row;
        std::memcpy(out.data()+(2*row+(field^(bottomFirst?1:0)))*Stride,data+source*Stride,Stride);
    }
    return out;
}
} // namespace shuttle
