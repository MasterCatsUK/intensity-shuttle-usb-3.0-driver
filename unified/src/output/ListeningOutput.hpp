// GPL-2.0-or-later. 23 October 2026: optional speaker monitoring of outgoing PCM.
#pragma once
#include <cstdint>
#include <vector>
#include <memory>
namespace shuttle_listen {
class Output {
    struct Impl;std::unique_ptr<Impl> impl;
public:
    explicit Output(bool enabled=true);
    ~Output();
    // Reads outgoing stereo before monitor gain; never mutates TV/editor PCM.
    void push(const std::vector<int32_t>& pcm);
};
}
