# Build validation — 0.1.31

On 18 October 2026, the clean source folder built the ARM64 capture extension, unified host, Core Audio driver, Premiere Transmit adapter and full installer. The local compiler environment was macOS 27; the separately obtained Adobe SDK was version 26.0. No Adobe SDK files are redistributed.

All 21 isolated installer tests passed. Installer expansion verified exact bundled application/audio payloads, ad-hoc bundle signatures, ARM64/startup-volume requirements and embedded corresponding source. Host version 31 contains the new original SVHS icon; capture extension 15, output extension 12, HAL 3 and Premiere adapter 1 retain their qualified versions.

No installer was run and no security settings or installed apps were changed during this build. The user confirmed 0.1.30 functionality; this 0.1.31 icon/version change has not received a new live hardware test or fresh-machine qualification. Installer signing/notarization remains outstanding. See the publisher checklist.
