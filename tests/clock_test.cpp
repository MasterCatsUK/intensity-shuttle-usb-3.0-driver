// GPL-2.0-or-later. Missing video cannot change the shared source timeline.
#include "CaptureClock.hpp"
#include <cassert>
#include <cstdio>
int main() {
    shuttle::CaptureClock clock;
    uint64_t base=10000000000ULL;
    uint64_t first=clock.audio(65520,base+shuttle::FrameNS);
    assert(first==base);
    uint64_t lastVideo=0;
    unsigned audio=1,video=1;lastVideo=first;
    for(unsigned i=1;i<10000;++i) {
        uint16_t tc=uint16_t(65520+i);
        uint64_t now=base+(i+1)*shuttle::FrameNS;
        uint64_t a=clock.audio(tc,now);++audio;
        assert(a==base+i*shuttle::FrameNS);
        // Two seconds of video disappear; audio continues through the gap.
        if(i>=50 && i<100) continue;
        uint64_t v=clock.video(tc,now+1000000ULL);++video;
        assert(v==a);assert(!lastVideo || v>lastVideo);lastVideo=v;
    }
    assert(audio==10000 && video==9950);
    // Both inputs disappear for two seconds, then the hardware counter resets.
    uint64_t later=base+10002*shuttle::FrameNS;
    uint64_t recovered=clock.audio(0,later+shuttle::FrameNS);
    assert(recovered==later);assert(clock.video(0,later+shuttle::FrameNS)==recovered);
    assert(recovered>lastVideo);
    // A delayed video callback must not move the audio anchor backward.
    assert(clock.video(65535,later+shuttle::FrameNS)==recovered-shuttle::FrameNS);
    assert(clock.audio(1,later+2*shuttle::FrameNS)==recovered+shuttle::FrameNS);
    // A stalled VIDEO counter must not stop valid PCM blocks or close a gap.
    clock.reset();
    assert(clock.audio(10,base+shuttle::FrameNS)==base);
    assert(clock.audio(10,base+2*shuttle::FrameNS)==base+shuttle::FrameNS);
    assert(clock.audio(10,base+3*shuttle::FrameNS)==base+2*shuttle::FrameNS);
    uint64_t afterSilence=clock.audio(10,base+100*shuttle::FrameNS);
    assert(afterSilence==base+99*shuttle::FrameNS);
    assert(clock.video(10,base+100*shuttle::FrameNS)==afterSilence);
    puts("PASS: shared A/V timestamps, two-second video gap, counter wrap, hardware reset, delayed video, 400-second timeline");
}
