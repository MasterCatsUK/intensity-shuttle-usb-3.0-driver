// GPL-2.0-or-later. ScreenCaptureKit desktop video; no virtual display is installed.
#pragma once
#include "OutputPacket.hpp"
#include "FrameSizing.hpp"
#include <memory>
class DesktopSource {
    struct Impl;std::unique_ptr<Impl> impl;
public:
    DesktopSource(uint32_t displayID,shuttle_output::Mode mode,shuttle_output::Sizing sizing=shuttle_output::Sizing::Fit);
    ~DesktopSource();
    bool read(std::vector<uint8_t>& picture);
};
