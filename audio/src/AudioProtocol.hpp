// GPL-2.0-or-later. Local-only stereo transport from the camera capture service.
#pragma once
#include <cstdint>
#include <cstring>
#include <cmath>
namespace shuttle_audio {
#ifndef SHUTTLE_AUDIO_PORT
#define SHUTTLE_AUDIO_PORT 49381
#endif
constexpr uint16_t Port=SHUTTLE_AUDIO_PORT;
constexpr uint32_t Rate=48000, Channels=2, Frames=480, Magic=0x31414853;
struct Packet {
    uint32_t magic=Magic, version=1, frames=Frames, rate=Rate;
    uint64_t hostNS=0;
    float samples[Frames*Channels];
};
static_assert(sizeof(Packet)==3864,"Audio packet layout changed");
inline bool valid(const Packet &p,size_t size) {
    if(size!=sizeof(p) || p.magic!=Magic || p.version!=1 || p.frames!=Frames || p.rate!=Rate || !p.hostNS) return false;
    for(float x:p.samples) if(!std::isfinite(x) || x < -1.0f || x > 1.0f) return false;
    return true;
}
inline float pcm24(const uint8_t *p) {
    int32_t n=int32_t(uint32_t(p[0]) | uint32_t(p[1])<<8 | uint32_t(p[2])<<16);
    if(n & 0x800000) n-=0x1000000;
    return float(n)*(1.0f/8388608.0f);
}
inline uint64_t sampleAt(uint64_t ns) {
    return uint64_t((static_cast<unsigned __int128>(ns)*Rate+500000000ULL)/1000000000ULL);
}
} // namespace shuttle_audio
