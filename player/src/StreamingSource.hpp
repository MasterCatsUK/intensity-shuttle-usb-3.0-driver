// GPL-2.0-or-later. Bounded streaming decoder, isolated from local-file decoding.
#pragma once
#include "MovieSource.hpp"
class StreamingSource {
    struct Impl;std::unique_ptr<Impl> impl;
public:
    struct State {bool advanced=false,buffering=false,ended=false;double buffered=0,videoSeconds=0,audioSeconds=0;};
    StreamingSource(const std::string& config,shuttle_output::Mode mode,shuttle_output::Sizing sizing,double startSeconds=0);
    ~StreamingSource();
    double duration()const;
    State read(bool paused,uint64_t frame,std::vector<uint8_t>& picture,std::vector<int32_t>& pcm);
};
