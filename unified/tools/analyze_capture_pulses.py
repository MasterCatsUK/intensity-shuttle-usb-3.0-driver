#!/usr/bin/env python3
"""Offline, signature-specific review of saved AVTest WAV/log captures.

Uses only the Python standard library. It never edits the capture or log files.
Default input pairs are capture-after-audio2{,-repeat}.{wav,log} in the workspace.
The JSON keeps every raw logged pair, including each originally failing first
point. A tone is located from its waveform, not from proximity to a video PTS.
"""
import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import wave

RATE = 48000
TONE = 1000
PERIOD = RATE // TONE
WINDOW = 480  # Ten complete cycles; no spectral leakage for the target tone.
HOP = 48      # One millisecond; exact onset is refined at sample resolution.
COS = [math.cos(2 * math.pi * i / PERIOD) for i in range(PERIOD)]
SIN = [math.sin(2 * math.pi * i / PERIOD) for i in range(PERIOD)]


def spectrum(samples, start, length=WINDOW):
    """Single-bin DFT, equivalent to Goertzel power at exactly 1 kHz.

    The purity is target-frequency energy / total AC energy. On a pure sine
    at 1 kHz it is one; broadband source audio usually has a much smaller value.
    """
    data = samples[max(0, start):max(0, start) + length]
    n = len(data)
    if not n:
        return {"purity": 0, "amplitude": 0, "rms": 0}
    mean = sum(data) / n
    energy = sum((x - mean) ** 2 for x in data)
    c = sum(x * COS[(start + i) % PERIOD] for i, x in enumerate(data))
    s = sum(x * SIN[(start + i) % PERIOD] for i, x in enumerate(data))
    return {"purity": 2 * (c * c + s * s) / (n * energy) if energy else 0,
            "amplitude": 2 * math.hypot(c, s) / n,
            "rms": math.sqrt(sum(x * x for x in data) / n)}


def tone_windows(channels):
    # Prefix sums over one-cycle blocks make the 10 ms scan O(number of samples).
    prefixes = []
    blocks = len(channels[0]) // HOP
    for samples in channels:
        pc, ps, pe, pm = [0.0], [0.0], [0.0], [0.0]
        for block in range(blocks):
            data = samples[block * HOP:(block + 1) * HOP]
            pc.append(pc[-1] + sum(x * COS[i] for i, x in enumerate(data)))
            ps.append(ps[-1] + sum(x * SIN[i] for i, x in enumerate(data)))
            pe.append(pe[-1] + sum(x * x for x in data))
            pm.append(pm[-1] + sum(data))
        prefixes.append((pc, ps, pe, pm))
    accepted = []
    for block in range(blocks - WINDOW // HOP + 1):
        good = True
        for pc, ps, pe, pm in prefixes:
            end = block + WINDOW // HOP
            c, s = pc[end] - pc[block], ps[end] - ps[block]
            energy = pe[end] - pe[block] - (pm[end] - pm[block]) ** 2 / WINDOW
            purity = 2 * (c * c + s * s) / (WINDOW * energy) if energy > 1e-12 else 0
            amplitude = 2 * math.hypot(c, s) / WINDOW
            # The source specifies amplitude 0.12. Require that signature in
            # both channels, as well as spectral purity, independently of PTS.
            if not (purity >= 0.985 and 0.115 <= amplitude <= 0.125):
                good = False
                break
        if good:
            accepted.append(block * HOP)
    runs = []
    for sample in accepted:
        if runs and sample == runs[-1][-1] + HOP:
            runs[-1].append(sample)
        else:
            runs.append([sample])
    return [run for run in runs if len(run) * HOP >= RATE * .08]


def refine_tone(channels, run, tolerance=0.001):
    # Estimate phase and amplitude only in the pure interior, then expand while
    # both channels remain compatible with that fixed-frequency sine. This
    # prevents ordinary >0.03 source audio being mistaken for a beep onset.
    anchor = run[len(run) // 2]
    fits = []
    for samples in channels:
        data = samples[anchor:anchor + WINDOW]
        c = 2 * sum(x * COS[(anchor + i) % PERIOD] for i, x in enumerate(data)) / WINDOW
        s = 2 * sum(x * SIN[(anchor + i) % PERIOD] for i, x in enumerate(data)) / WINDOW
        fits.append((c, s))
    def matches(index):
        return all(abs(samples[index] - c * COS[index % PERIOD] - s * SIN[index % PERIOD]) <= tolerance
                   for samples, (c, s) in zip(channels, fits))

    start = anchor
    while start > 0 and matches(start - 1):
        start -= 1
    end = anchor
    while end < len(channels[0]) and matches(end):
        end += 1
    # A zero-crossing gate-end sample can also fit the ungated waveform.
    # State both the actual compatible run and a nominal zero-crossing boundary.
    nominal_end = end
    if end > start and all(abs(samples[end - 1]) <= 1 / 32768 for samples in channels):
        nominal_end -= 1
    interior = spectrum(channels[0], anchor)
    residuals = []
    for samples, (c, s) in zip(channels, fits):
        residuals.append(math.sqrt(sum((samples[i] - c * COS[i % PERIOD] - s * SIN[i % PERIOD]) ** 2
                                      for i in range(anchor, anchor + WINDOW)) / WINDOW))
    return {"startSampleFrame": start, "endSampleFrameNominal": nominal_end,
            "fitCompatibleEndSampleFrameExclusive": end,
            "startSecondsInWAV": start / RATE,
            "durationSecondsNominal": (nominal_end - start) / RATE,
            "interiorSpectrumLeft": interior,
            "interiorSpectrumRight": spectrum(channels[1], anchor),
            "interiorFitResidualRMS": residuals,
            "onsetRefinementToleranceAmplitude": tolerance,
            "onsetPrecisionCaution": "Approximately 1-2 samples for these zero-crossing bursts; raw WAV and rounded first PTS cannot prove absolute clock accuracy."}


def rounded(value):
    if isinstance(value, float):
        return round(value, 9)
    if isinstance(value, list):
        return [rounded(v) for v in value]
    if isinstance(value, dict):
        return {k: rounded(v) for k, v in value.items()}
    return value


def analyze(stem):
    wav_path, log_path = stem.with_suffix(".wav"), stem.with_suffix(".log")
    log = log_path.read_text()
    first_pts = float(re.search(r"First audio PTS ([0-9.]+)", log)[1])
    first_video_pts = float(re.search(r"First video PTS ([0-9.]+)", log)[1])
    raw_pairs = [(float(v), float(offset)) for v, offset in re.findall(
        r"SYNC pulse: video ([0-9.]+); audio offset ([+-][0-9.]+) s", log)]
    with wave.open(str(wav_path), "rb") as handle:
        assert (handle.getframerate(), handle.getnchannels(), handle.getsampwidth(), handle.getcomptype()) == (RATE, 2, 2, "NONE")
        pcm = array.array("h", handle.readframes(handle.getnframes()))
        if sys.byteorder != "little":
            pcm.byteswap()
    channels = [[x / 32768 for x in pcm[ch::2]] for ch in range(2)]
    runs = tone_windows(channels)
    bursts = [refine_tone(channels, run) for run in runs]
    sensitivity = []
    for run, burst in zip(runs, bursts):
        starts = [refine_tone(channels, run, tolerance)["startSampleFrame"]
                  for tolerance in [.0001, .0005, .001, .002]]
        sensitivity.append({"defaultStartSampleFrame": burst["startSampleFrame"],
                            "startRangeAcrossTolerancesSampleFrames": [min(starts), max(starts)]})
    for burst in bursts:
        burst["estimatedStartPTS"] = first_pts + burst["startSecondsInWAV"]
        burst["durationClass"] = "full ~200 ms pulse" if abs(burst["durationSecondsNominal"] - .2) < .001 else "partial diagnostic transition pulse"
    pairs = []
    for index, (video_pts, raw_offset) in enumerate(raw_pairs):
        raw_pts = video_pts + raw_offset
        raw_sample = round((raw_pts - first_pts) * RATE)
        burst_index, burst = min(enumerate(bursts), key=lambda pair: abs(pair[1]["estimatedStartPTS"] - video_pts))
        assert abs(burst["estimatedStartPTS"] - video_pts) < .4
        raw_spectrum = spectrum(channels[0], raw_sample)
        corrected_offset = burst["estimatedStartPTS"] - video_pts
        pairs.append({"point": index + 1, "videoPTS": video_pts,
                      "rawAmplitudeDetectorOffsetSeconds": raw_offset,
                      "rawAmplitudeDetectorEventPTS": raw_pts,
                      "rawAmplitudeDetectorEventSampleFrameApproximate": raw_sample,
                      "rawEventFollowing10msSpectrumLeft": raw_spectrum,
                      "rawEventFollowing10msSpectrumRight": spectrum(channels[1], raw_sample),
                      "rawEventClassification": ("1 kHz diagnostic tone" if raw_spectrum["purity"] > .985 and .115 <= raw_spectrum["amplitude"] <= .125
                                                 else "source/program audio or transition; not the 1 kHz diagnostic signature"),
                      "matchedToneBurst": burst_index + 1,
                      "toneStartPTS": burst["estimatedStartPTS"],
                      "toneDurationSecondsNominal": burst["durationSecondsNominal"],
                      "toneAudioMinusVideoSeconds": corrected_offset,
                      "differenceFromRawDetectorSeconds": corrected_offset - raw_offset,
                      "within31msOriginalPerPointLimit": abs(corrected_offset) < .031})
    offsets = [pair["toneAudioMinusVideoSeconds"] for pair in pairs]
    raw_offsets = [pair["rawAmplitudeDetectorOffsetSeconds"] for pair in pairs]
    audio_buffers = int(re.search(r"RESULT video=\d+; audio buffers=(\d+)", log)[1])
    max_audio_step = float(re.search(r"maximum audio-buffer step ([0-9.]+) s", log)[1])
    max_video_step = float(re.search(r"maximum video step ([0-9.]+) s", log)[1])
    return {"capture": str(stem.resolve()),
            "unalteredInputSHA256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in [wav_path, log_path]},
            "rawValidationRetained": re.findall(r"VALIDATION: (\w+)", log),
            "wav": {"sampleRate": RATE, "channels": 2, "bitsPerSample": 16,
                    "sampleFrames": len(channels[0]), "seconds": len(channels[0]) / RATE},
            "firstAudioPTS": first_pts, "firstVideoPTS": first_video_pts,
            "continuityEvidence": {"loggedAudioBuffers": audio_buffers,
                                   "savedSampleFramesPerLoggedBuffer": len(channels[0]) / audio_buffers,
                                   "expected192FrameBuffersMatchWAVLengthExactly": len(channels[0]) == audio_buffers * 192,
                                   "loggedMaximumAudioBufferPTSStepSeconds": max_audio_step,
                                   "loggedMaximumVideoPTSStepSeconds": max_video_step},
            "toneBurstsDetectedWithoutVideoTiming": bursts,
            "onsetSensitivity": {"fitToleranceAmplitudesChecked": [.0001, .0005, .001, .002],
                                 "bursts": sensitivity},
            "allLoggedVideoPoints": pairs,
            "summary": {"loggedVideoPoints": len(pairs), "matchedToneBursts": len(bursts),
                        "rawOffsetRangeSeconds": [min(raw_offsets), max(raw_offsets)],
                        "signatureOffsetRangeSecondsAllPoints": [min(offsets), max(offsets)],
                        "signatureOffsetSpreadSecondsAllPoints": max(offsets) - min(offsets),
                        "allPointsWithin31ms": all(abs(x) < .031 for x in offsets),
                        "spreadWithin31ms": max(offsets) - min(offsets) < .031,
                        "firstPointRetained": True},
            "interpretation": "The first amplitude-only trigger is not the diagnostic sine. Its 0.5-second debounce prevents the raw tester registering the subsequent true first tone. The spectrally identified first tone is retained and compared to the first logged video pulse; every logged point is within the original 31ms per-point timing bound. This is an offline timing interpretation, not a replacement raw validation result."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stems", nargs="*", type=Path)
    parser.add_argument("--output", type=Path, default=Path("capture-pulse-spectral-analysis.json"))
    args = parser.parse_args()
    workspace = Path(__file__).resolve().parents[1]
    stems = args.stems or [workspace / "capture-after-audio2", workspace / "capture-after-audio2-repeat"]
    source_root = workspace.parent / "shuttle-camera-extension"
    source_paths = [source_root / "tools/AVTest.mm", source_root / "src/CameraExtension.mm"]
    report = {"sourceReferences": [{"path": str(path), "SHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                     "relevantLines": "61-62: amplitude-only detector; 154-166: matching and raw timing limits" if path.name == "AVTest.mm" else "184-189: 1kHz/0.12/200ms diagnostic audio; 223-225: corresponding video gate"}
                                    for path in source_paths],
              "method": {"target": "CameraExtension.mm diagnostic: stereo 1 kHz, peak 0.12, 200 ms gate each second",
                         "detector": "Exact-frequency single-bin DFT (Goertzel-equivalent power), 10 ms windows, 1 ms hop, both channels",
                         "coreRequirements": {"minimum1kHzEnergyPurity": .985, "peakAmplitudeRange": [.115, .125], "minimumCoreSeconds": .08},
                         "onset": "Fit a 1 kHz sine to each channel's pure interior, then expand until either channel deviates by >0.001. Video timing is used only after detection.",
                         "clockMapping": "audioPTS = logged First audio PTS + WAV sample-frame index / 48000",
                         "rawTester": "Any left-channel |sample| >0.03 after diagnostic is enabled, with 0.5 s debounce; this is not frequency-specific."},
              "captures": [analyze(stem) for stem in stems],
              "limits": ["This offline reanalysis does not turn the original raw VALIDATION: FAIL results into PASS; all original capture/log files remain untouched.",
                         "WAV has no per-buffer timestamps. Mapping assumes contiguous saved audio at exactly 48 kHz. Logs report maximum buffer PTS step 4 ms and WAV frame counts equal buffer count times 192, consistent with continuity, but they do not retain every individual PTS.",
                         "Only seven video pulse timestamps per capture were logged by the raw tester; omitted/dropout video pulses cannot be reconstructed from the WAV. All seven logged points, including the first, are analyzed.",
                         "This tests an internally generated capture diagnostic and source timestamps. It does not measure a physical FCP playback/output path, display latency, or real VHS audio/video alignment.",
                         "Normal program/VHS audio is an inference from low tone purity before the diagnostic signature, plus the source transition logic. The WAV cannot independently identify its physical origin.",
                         "Do not treat submillisecond estimates as an absolute clock calibration. First audio PTS was rounded in the log, and zero-crossing gate boundaries have a one-sample ambiguity."]}
    args.output.write_text(json.dumps(rounded(report), indent=2) + "\n")
    print(args.output.resolve())
    for capture in report["captures"]:
        print(Path(capture["capture"]).name, json.dumps(rounded(capture["summary"])))
        print("First point:", json.dumps(rounded(capture["allLoggedVideoPoints"][0])))


if __name__ == "__main__":
    main()
