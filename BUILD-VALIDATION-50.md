# 0.1.50 validation

23 October 2026. Universal host/helper update. Camera21, output13, HAL4 and Premiere2 remain byte-identical to 0.1.49. Nine Mach-O programs and bundle metadata/signatures verified for arm64 and x86_64, macOS14.4 minimum. Intel runtime untested.

- Analytical scopes: black/white/superwhite, Rec.601 red, histogram counts, neutral vectors and luma rows; all six views render legal SD/HD output. New flat-white HD waveform continuity regression passes.
- Asynchronous scopes: coalescing pending frames, no waiting for worker renders, last raster held, stale view rejected, Video byte identity and orderly worker teardown. Initial measured worst frame submission below1ms on this Mac; rendering is separate and not a calibrated benchmark.
- Actual nextWireFrame test: all six output modes preserve Video USB packet bytes and clean pre-overlay fan-out. Scope worker is warmed before comparing the selected rendered scope packet.
- Screen helper: all six modes, independent buffer ownership, SD pixel aspect, Fit/Fill/Stretch, and stereo meters with local listening disabled. Mac helper moves frame ownership instead of copying it again.
- Offline AppKit hit-test/action/persistence regression: zero failures, no real route/settings/task writes.
- Installer filesystem mocks: 24 cases including active clients, backups, version checks and audio restart safeguards.
- Scope screenshot generated from an original synthetic ramp and visually reviewed. No user video used in distributed screenshots.

The user confirmed simultaneous49 output worked and meters work with Virtual Shuttle Audio routing; reported dark/grid traces and slower scopes. 50 addresses these in host/helpers only. Live50 comparison, listening/sync and paused/playing effect/title refresh remain pending. No GitHub publication.
