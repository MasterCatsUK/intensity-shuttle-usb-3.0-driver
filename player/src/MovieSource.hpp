#pragma once
#include "OutputPacket.hpp"
#include "FrameSizing.hpp"
#include <memory>
#include <string>
class MovieSource {
    struct Impl;std::unique_ptr<Impl> impl;
public:
    MovieSource(const std::string& file,shuttle_output::Mode mode,shuttle_output::Sizing sizing=shuttle_output::Sizing::Fit,bool withAudio=true,double startSeconds=0);
    ~MovieSource();
    double duration() const;
    void read(unsigned frame,std::vector<uint8_t>& picture,std::vector<int32_t>& audio);
};
