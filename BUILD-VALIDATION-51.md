# 0.1.51 validation

23 October2026. User confirmed50 looks better and plays smoothly; requested less blocky waveform/histogram plots and clear scopes without guides/meters.

Native RGB Mac scope canvas now uses backing resolution with aspect-preserving3840×2160 cap. Analysis up to960×768, both luma pixels measured, denser vertical samples; histogram remains8-bit256bins. Worker still coalesces without waiting on USB. A native2560 fixture took about36ms on the separate worker; worst submission under1ms in the local stress run, not a machine-wide benchmark.

Tests: analytic SDR/legalSDHD6views, flat-white continuousHDtrace, odd-pixel single-column stripe retention; native2560×1440/3840×2160 RGB image ownership/dimensions; async mode/native cache keys and Video identity; actual nextWireFrame six modes with every overlay saved ON still produces exact clean scope packets while Video packets stay unchanged; clean shared fan-out; UI disables all scope overlays and restores Video controls without changing saved flags; 24 installer filesystem mocks;9universal binaries/signatures/metadata and exact expanded payloads. All driver components compare byte-identical50. Live51 appearance/smoothness/overlays pending. Intel runtime untested. No GitHub publication.
