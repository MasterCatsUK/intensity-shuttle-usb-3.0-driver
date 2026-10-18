// GPL-2.0-or-later. Pure timing tests: no Core Audio, CMIO, sockets, or USB.
#include "../src/output/AudioCursor.hpp"
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <limits>

using shuttle_output_audio::AudioCursor;

static unsigned fractionalFrames(uint64_t physicalFrame) {
    const unsigned cadence[] = {1601, 1602, 1601, 1602, 1602};
    return cadence[physicalFrame % 5];
}

static void fractionalContinuity() {
    // Every wire-cadence phase can be present when an independently started
    // editor first connects. Vary PTS quantization and add sub-sample jitter.
    const uint64_t baseNS = 1000000000000ULL;
    for (unsigned phase = 0; phase < 5; ++phase) {
        for (unsigned rounded = 0; rounded < 2; ++rounded) {
            AudioCursor cursor;
            uint64_t expected = 48000000, first = 0;
            for (uint64_t frame = 0; frame < 100000; ++frame) {
                uint64_t delta = (frame * 1001000000000ULL + (rounded ? 15000 : 0)) / 30000;
                // No jitter on the first frame: the expected anchor is exact.
                int64_t jitter = frame ? int64_t(frame % 3) * 5000 - 5000 : 0;
                uint64_t pts = uint64_t(int64_t(baseNS + delta) + jitter);
                unsigned count = fractionalFrames(frame + phase);
                assert(cursor.take(true, pts, 7, count, 30000, 1001, first));
                assert(first == expected); // Every window begins at the previous end.
                expected += count;
            }
        }
    }
    AudioCursor cursor;
    const uint64_t starts[] = {0, 1601, 3203, 4804, 6406, 8008};
    for (uint64_t frame = 0; frame < 6; ++frame) {
        uint64_t first = 99;
        uint64_t pts = (frame * 1001000000000ULL + 15000) / 30000;
        assert(cursor.take(true, pts, 1, fractionalFrames(frame), 30000, 1001, first));
        assert(first == starts[frame]);
    }
}

static void repeatedVideoAndResume() {
    AudioCursor cursor;
    uint64_t first = 123;
    assert(!cursor.take(false, 9000000000ULL, 1, 1920, 25, 1, first));
    assert(first == 123);
    assert(cursor.take(true, 1000000000, 1, 1920, 25, 1, first) && first == 48000);
    assert(cursor.take(true, 1040000000, 1, 1920, 25, 1, first) && first == 49920);
    assert(cursor.take(false, 0, 1, 1920, 25, 1, first) && first == 51840);
    assert(cursor.take(false, std::numeric_limits<uint64_t>::max(), 1,
                       1920, 25, 1, first) && first == 53760);
    // Fresh PTS only advances once despite two repeated images. Target/cursor
    // divergence must reanchor even though the two real PTS are normally spaced.
    assert(cursor.take(true, 1080000000, 1, 1920, 25, 1, first) && first == 51840);
    assert(cursor.take(true, 1120000000, 1, 1920, 25, 1, first) && first == 53760);
    assert(cursor.take(false, 0, 1, 1920, 25, 1, first) && first == 55680);
    assert(cursor.take(false, 0, 1, 1920, 25, 1, first) && first == 57600);
    // If the next PTS catches up to elapsed physical time, resume at that time.
    assert(cursor.take(true, 1240000000, 1, 1920, 25, 1, first) && first == 59520);
    assert(cursor.take(true, 1280000000, 1, 1920, 25, 1, first) && first == 61440);
}

static void generationAndFormatRestart() {
    AudioCursor cursor;
    uint64_t first = 77;
    assert(cursor.take(true, 1000000000, 11, 1920, 25, 1, first) && first == 48000);
    first = 77;
    assert(!cursor.take(false, 1000000000, 12, 1920, 25, 1, first) && first == 77);
    assert(!cursor.take(false, 0, 12, 1920, 25, 1, first) && first == 77);
    assert(cursor.take(true, 0, 12, 1920, 25, 1, first) && first == 0);
    assert(cursor.take(false, 0, 12, 1920, 25, 1, first) && first == 1920);
    assert(cursor.take(true, 500000000, 13, 1920, 25, 1, first) && first == 24000);
    // A format switch must not reuse an anchor with a different frame duration.
    first = 77;
    assert(!cursor.take(false, 0, 13, 1601, 30000, 1001, first) && first == 77);
    assert(cursor.take(true, 1000000000, 13, 1601, 30000, 1001, first) && first == 48000);
}

static void discontinuitiesAndTolerance() {
    AudioCursor cursor;
    uint64_t first;
    assert(cursor.take(true, 1000000000, 1, 1920, 25, 1, first) && first == 48000);
    // A 5-ms PTS error is within the quarter-frame bound and must not shift audio.
    assert(cursor.take(true, 1045000000, 1, 1920, 25, 1, first) && first == 49920);
    assert(cursor.take(true, 1080000000, 1, 1920, 25, 1, first) && first == 51840);
    assert(cursor.take(true, 1200000000, 1, 1920, 25, 1, first) && first == 57600);
    assert(cursor.take(true, 1240000000, 1, 1920, 25, 1, first) && first == 59520);
    assert(cursor.take(true, 800000000, 1, 1920, 25, 1, first) && first == 38400);
    assert(cursor.take(true, 840000000, 1, 1920, 25, 1, first) && first == 40320);
    // Detect a dropped frame and an unchanged timestamp on a new input frame.
    assert(cursor.take(true, 920000000, 1, 1920, 25, 1, first) && first == 44160);
    assert(cursor.take(true, 920000000, 1, 1920, 25, 1, first) && first == 44160);

    // Individually small timing errors must not accumulate without bound.
    AudioCursor drifting;
    assert(drifting.take(true, 0, 2, 1920, 25, 1, first) && first == 0);
    for (uint64_t frame = 1; frame <= 5; ++frame) {
        assert(drifting.take(true, frame * 42000000, 2, 1920, 25, 1, first));
        assert(first == frame * 1920);
    }
    assert(drifting.take(true, 252000000, 2, 1920, 25, 1, first) && first == 12096);
}

static void integerBoundsAndInvalidRates() {
    AudioCursor cursor;
    uint64_t first = 99;
    assert(!cursor.take(true, 0, 0, 1920, 0, 1, first) && first == 99);
    assert(!cursor.take(false, 0, 0, 1920, 25, 1, first) && first == 99);
    assert(cursor.take(true, std::numeric_limits<uint64_t>::max(), 0,
                       1920, 25, 1, first));
    assert(first == 885443715538058ULL);
    assert(cursor.take(true, 0, 0, 1920, 25, 1, first) && first == 0);
    first = 99;
    assert(!cursor.take(false, 0, 0, 1920, 25, 0, first) && first == 99);
    assert(!cursor.take(false, 0, 0, 1920, 25, 1, first) && first == 99);
}

int main() {
    fractionalContinuity();
    repeatedVideoAndResume();
    generationAndFormatRestart();
    discontinuitiesAndTolerance();
    integerBoundsAndInvalidRates();
    std::puts("PASS: 1,000,000 fractional-rate windows without gaps/overlap; held video; restart; discontinuity; jitter; bounds");
}
