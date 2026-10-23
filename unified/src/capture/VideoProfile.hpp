// GPL-2.0-or-later. SD television standards and rational frame timing.
#pragma once
#include <cstdint>
#include "PictureControls.hpp"
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
enum class OutputSize { Native, SquarePixels, Size1280x960, Size1440x1080, Size1280x720, Size1920x1080, NativeInterlaced, Size1920x1080Interlaced };
struct CaptureSettings {
    VideoProfile profile;
    PictureSettings picture;
    uint32_t videoInput=0x06000000, audioInput=0x10000000;
    bool blackOnDropout=false;
    bool widescreen=false;
    bool bottomFirst=false;
    OutputSize outputSize=OutputSize::Native;
    unsigned outputWidth() const {
        switch(outputSize) {
            case OutputSize::SquarePixels:return widescreen?(profile.ntsc?854:1024):(profile.ntsc?640:768);
            case OutputSize::Size1280x960:case OutputSize::Size1280x720:return 1280;
            case OutputSize::Size1920x1080:case OutputSize::Size1920x1080Interlaced:return 1920;
            case OutputSize::Size1440x1080:return 1440;
            default:return 720;
        }
    }
    unsigned outputHeight() const {
        switch(outputSize) {
            case OutputSize::Size1280x960:return 960;
            case OutputSize::Size1440x1080:case OutputSize::Size1920x1080:case OutputSize::Size1920x1080Interlaced:return 1080;
            case OutputSize::Size1280x720:return 720;
            default:return profile.height();
        }
    }
    bool native() const { return outputSize==OutputSize::Native||outputSize==OutputSize::NativeInterlaced; }
    bool interlaced() const { return outputSize==OutputSize::NativeInterlaced||outputSize==OutputSize::Size1920x1080Interlaced; }
    unsigned sampleRateNom() const { return interlaced()?profile.rateNom():profile.fieldNom(); }
    uint64_t sampleNS(uint64_t n=1) const { return interlaced()?profile.frameNS(n):profile.fieldNS(n); }
    uint64_t sampleTickAt(uint64_t ns) const { return profile.tickAt(ns)/(interlaced()?2:1); }
    unsigned aspectH() const { return native()?(widescreen?(profile.ntsc?32:64):(profile.ntsc?8:16)):1; }
    unsigned aspectV() const { return native()?(widescreen?(profile.ntsc?27:45):(profile.ntsc?9:15)):1; }
    unsigned imageWidth() const {
        if(native()||outputSize==OutputSize::SquarePixels)return outputWidth();
        unsigned w=outputWidth(),h=outputHeight(),n=widescreen?16:4,d=widescreen?9:3;
        return uint64_t(w)*d>uint64_t(h)*n?((h*n/d)&~1u):w;
    }
    unsigned imageHeight() const {
        if(native()||outputSize==OutputSize::SquarePixels)return outputHeight();
        unsigned w=outputWidth(),h=outputHeight(),n=widescreen?16:4,d=widescreen?9:3;
        return uint64_t(w)*d<uint64_t(h)*n?w*d/n:h;
    }
};
} // namespace shuttle
