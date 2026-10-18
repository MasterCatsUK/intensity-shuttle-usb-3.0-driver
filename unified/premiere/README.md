# Shuttle Premiere Pro output — 0.1.29 development

Native Apple-silicon Mercury Transmit video plug-in, built against Adobe's supplied26.0 C++ SDK using the version1 transmit API. Installed Premiere25.2.3 is the live test target. Successful compilation and offline tests do not qualify actual Premiere/HDMI playback.

## Use

1. Close Shuttle capture previews. In Shuttle Camera → Video Output choose the physical output format and source **Premiere Pro / Mercury Transmit**.
2. Click **Start Premiere output**; wait for **Ready for Premiere**. Keep Shuttle Camera open.
3. In Premiere Settings → Playback, enable **Mercury Transmit** and select **Intensity Shuttle — HDMI Output** under Video Device. Start with a1080p25 sequence and1080p25 physical output.
4. For sound, in Premiere Settings → Audio Hardware choose **Intensity Shuttle — HDMI Audio** as the default output. This is the existing Core Audio device, separate from the video transmitter. The plug-in does not appear as a Transmit audio device and does not take over Premiere's playback clock.
5. Disable Mercury Transmit before stopping output in Shuttle Camera. If you explicitly selected HDMI in Premiere Audio Hardware, select your normal audio device there afterward. Shuttle Camera's Restore audio controls the Mac's system media output, not Premiere's explicit per-application device choice.

Changing the app's format causes the transmitter to request a mode refresh through NeedsReset. Use matching sequence/output frame rates for initial qualification. Frame-rate conversion across mismatched cadences has not been qualified.

HDMI safe guides, L/R meters, audio offset and timecode overlay reuse the existing engine. Timecode is taken from nonnegative Adobe sequence time plus sequence zero point and drop-frame metadata; an immediate frame without a timestamp has no valid timecode and displays dashes. Actual Premiere metadata delivery still requires live checking.

## Build

Run `premiere/build.sh '/path/to/Adobe SDK/Examples'`. The SDK must be obtained separately from Adobe; no SDK headers or Adobe sample code are included in the source distribution. The plug-in's source is original, uses Adobe's declared public interfaces, and is distributed under GPL-2.0-or-later alongside this project.

The installer places `Shuttle Transmit.bundle` under:
`/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/`

Video uses localhost TCP47540, separate from FCP's unchanged47539. No USB calls occur inside Premiere. Each PPix is copied into owned memory and released exactly once; socket operations run on a worker. Both software input queue and consumed-but-not-completed frames are bounded to six. Premiere remains the clock source. There is no SDK clock callback and no fabricated hardware-completion feedback.

`src/output/SharedOutputCMIO.hpp` freezes the qualified extension12 transport; the general SharedOutput.hpp adds configurable ports for Premiere. Extension12 remains byte-identical to the qualified0.1.28 build. Capture15 and HAL3 also remain unchanged.

## Offline checks

TransmitTest.mm checks SDK entry/lifetimes, PPix release, no audio/clock advertisement, padded and negative UYVY stride, sequence/drop-frame timecode, and six-frame physical backpressure/recovery with a private ephemeral loopback receiver. App tests use fake preferences, audio/CMIO calls and subprocesses. Nothing in those tests opens USB, modifies routes, installs a driver or closes an editor.

Location correction0.1.29.1: installedPremiere25.2.3 actually scans legacy `Plug-ins`, verified in its Plugin Loading.log. SDK26 documentation path `Plugins` did not load the bundle. A separate repair installer relocates only the identical signed plug-in, preserving the unscanned copy in Backups. Host29 and all drivers remain unchanged.
