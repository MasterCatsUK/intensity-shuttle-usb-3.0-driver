// GPL-2.0-or-later. Continuous 48-kHz audio windows for a paced video output.
#pragma once
#include <cstdint>

namespace shuttle_output_audio {

// ptsNS must already be in the audio buffer clock's time domain. Presentation
// latency belongs in the caller's clock conversion, not in this cursor.
class AudioCursor {
    using Wide = unsigned __int128;
    uint64_t generation_ = 0, next_ = 0, lastPTS_ = 0;
    unsigned rateNom_ = 0, rateDen_ = 0;
    bool haveGeneration_ = false, anchored_ = false;

    static uint64_t sampleAtNS(uint64_t ns) {
        return uint64_t((Wide(ns) * 48000 + 500000000) / 1000000000);
    }

    static uint64_t distance(uint64_t a, uint64_t b) {
        return a > b ? a - b : b - a;
    }

    static bool normalPTSStep(uint64_t previous, uint64_t current,
                              unsigned rateNom, unsigned rateDen) {
        if (current < previous) return false;
        const Wide actual = Wide(current - previous) * rateNom;
        const Wide expected = Wide(1000000000) * rateDen;
        const Wide difference = actual > expected ? actual - expected : expected - actual;
        return difference * 4 <= expected;
    }

    static bool nearCursor(uint64_t target, uint64_t cursor,
                           unsigned rateNom, unsigned rateDen) {
        const uint64_t difference = distance(target, cursor);
        // One sample is always harmless rounding. Otherwise allow a quarter
        // frame, independently of the physical fractional-rate cadence phase.
        return difference <= 1 || Wide(difference) * 4 * rateNom <= Wide(48000) * rateDen;
    }

public:
    // A generation or format change invalidates held video until a fresh frame
    // anchors it. Fresh PTS zero is valid. A normal frame or held image consumes
    // exactly audioFrames from one cursor, avoiding per-frame rounding gaps.
    // Invalid rates clear anchoring and return false without changing firstSample.
    bool take(bool fresh, uint64_t ptsNS, uint64_t generation,
              unsigned audioFrames, unsigned rateNom, unsigned rateDen,
              uint64_t& firstSample) {
        if (!rateNom || !rateDen) {
            anchored_ = false;
            return false;
        }
        if (!haveGeneration_ || generation != generation_ ||
            rateNom != rateNom_ || rateDen != rateDen_) {
            generation_ = generation;
            rateNom_ = rateNom;
            rateDen_ = rateDen;
            haveGeneration_ = true;
            anchored_ = false;
        }
        if (fresh) {
            const uint64_t target = sampleAtNS(ptsNS);
            // Check the target too: after held video, a normally spaced new
            // PTS can still lag the audio cursor by one or more whole frames.
            if (!anchored_ || !normalPTSStep(lastPTS_, ptsNS, rateNom, rateDen) ||
                !nearCursor(target, next_, rateNom, rateDen)) {
                next_ = target;
            }
            lastPTS_ = ptsNS;
            anchored_ = true;
        }
        if (!anchored_) return false;
        firstSample = next_;
        next_ += audioFrames;
        return true;
    }
};

} // namespace shuttle_output_audio
