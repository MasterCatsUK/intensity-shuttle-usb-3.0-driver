// GPL-2.0-or-later. Desktop size is separate from the physical video raster.
#pragma once
#include "OutputPacket.hpp"
namespace shuttle_output {
struct DesktopSize {unsigned width,height;};
inline DesktopSize extendedDisplaySize(Mode mode){
    // Low-resolution virtual screens can be omitted from macOS Displays.
    // Use a usable 4:3 desktop, then ScreenCaptureKit scales into the SD raster.
    return mode==Mode::PAL576i50||mode==Mode::NTSC480i5994?DesktopSize{1024,768}:DesktopSize{1920,1080};
}
}
