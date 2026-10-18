// GPL-2.0-or-later. Bound total consumed-but-not-output video, across all queues.
#pragma once
#include <cstdint>
#include <deque>
namespace shuttle_sink {
class OutputCredits {
    std::deque<uint64_t> pending;
public:
    // Six full frames exceed the 128-ms USB transfer pipeline at every mode
    // (200.2 ms at 29.97 fps). This budget includes transport and reader queues;
    // moving a frame between those queues must not create another credit.
    static constexpr unsigned Limit=6;
    bool available() const {return pending.size()<Limit;}
    unsigned count() const {return unsigned(pending.size());}
    bool consumed(uint64_t sequence) {
        if(!available())return false;
        pending.push_back(sequence);return true;
    }
    bool completed(uint64_t sequence) {
        if(pending.empty()||pending.front()!=sequence)return false;
        pending.pop_front();return true;
    }
    void clear(){pending.clear();}
};
}
