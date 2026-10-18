// GPL-2.0-or-later. SD television standards and rational frame timing.
#pragma once
#include <cstdint>
namespace shuttle {
struct VideoProfile {
    bool ntsc=false;
    unsigned height() const { return ntsc?480:576; }
    unsigned rateNom() const { return ntsc?30000:25; }
    unsigned rateDen() const { return ntsc?1001:1; }
    unsigned fieldNom() const { return ntsc?60000:50; }
    uint64_t frameNS(uint64_t count=1) const { return uint64_t(static_cast<unsigned __int128>(count)*1000000000ULL*rateDen()/rateNom()); }
    uint64_t fieldNS(uint64_t count=1) const { return uint64_t(static_cast<unsigned __int128>(count)*1000000000ULL*rateDen()/fieldNom()); }
    uint64_t tickAt(uint64_t ns) const { return uint64_t(static_cast<unsigned __int128>(ns)*fieldNom()/(1000000000ULL*rateDen())); }
    bool audioFrames(unsigned n) const { return ntsc?(n==1601 || n==1602):n==1920; }
};
enum class OutputSize { Native, SquarePixels, Size1280x960, Size1440x1080 };
struct CaptureSettings {
    VideoProfile profile;
    uint32_t videoInput=0x06000000, audioInput=0x10000000;
    bool blackOnDropout=false;
    OutputSize outputSize=OutputSize::Native;
    unsigned outputWidth() const {
        switch(outputSize) {
            case OutputSize::SquarePixels:return profile.ntsc?640:768;
            case OutputSize::Size1280x960:return 1280;
            case OutputSize::Size1440x1080:return 1440;
            default:return 720;
        }
    }
    unsigned outputHeight() const {
        switch(outputSize) {
            case OutputSize::Size1280x960:return 960;
            case OutputSize::Size1440x1080:return 1080;
            default:return profile.height();
        }
    }
    unsigned aspectH() const { return outputSize==OutputSize::Native?(profile.ntsc?8:16):1; }
    unsigned aspectV() const { return outputSize==OutputSize::Native?(profile.ntsc?9:15):1; }
};
} // namespace shuttle
