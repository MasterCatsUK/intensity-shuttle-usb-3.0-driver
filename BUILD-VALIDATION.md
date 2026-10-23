# Validation — 0.1.35 resolution display fix

Host35 built; camera17/output12/HAL3/Premiere1 unchanged. Offline native UI regression simulates valid1440 settings then device absence: resolution/cache retained and retry scheduled. It also verifies automatic readback preserves an unapplied1280 draft and explicit Refresh loads actual settings/cancels retry. Previous stale-activation and live-capability UI checks pass, with zero real device/audio writes or helper launches. Installer mocks and expanded exact payload/signature/source checks run during packaging.

Read-only installed camera diagnosis reported1440×1080; no installed settings were changed. User confirmed33 live picture controls working. Reopen/reboot UI and saved-resolution behaviour still need user confirmation. No installation, activation, security or GitHub changes were made during preparation.

## 0.1.36

Host36 adds sizing/connectors/idle movies and experimental separate display helper. Camera17/output12/HAL3/Premiere1 unchanged. Native build/deep signature checks, offline UI checks, frame geometry/connector constraints, synthetic AVFoundation decoding across6modes×3sizings, idle picture conversion and silent movie looping passed. Live virtual-display probe created a1920×1080 separate display, captured a red window, and verified removal from the online-display list after Stop. Composite and S-Video capture passthrough were confirmed by the user; analogue playback/component, full TV extended-desktop operation and physical timing of the new media-sizing paths remain unqualified. No install/security changes occurred during these tests.

## 0.1.37

Host-only wording change: Use Shuttle Audio in the button, tooltip, help and logs. Audio routes/device identifiers/driver implementations unchanged. Native build and deep signatures passed; existing isolated UI checks passed with zero real device writes/audio route changes/helper launches. Button rendering inspected. PAL composite bars hardware result from36 recorded in Whats-New-0.1.37.md. Installer checks run during packaging.

## 0.1.38

Reproduced648×486 virtual screen absent from macOS Displays despite active CG display and successful desktop sender start. New1024×768 SD desktop verified visible in Settings during PAL and NTSC probes, red window captured into exact SD output raster, removal checked. Geometry regression ensures4:3/16:9 desktop mapping at all6modes with correct output pixel aspect. Existing UI checks passed with zero real device/audio/preference writes or helper launches. Native build/deep signatures passed. Installer checks run during packaging. No new USB/TV timing claim.

Live fullscreen-red PAL/NTSC probes verify red at centre and left/top/bottom edges after disabling redundant SCK square-pixel aspect correction. The earlier NTSC probe exposed a black left border with preservesAspectRatio enabled. Updated pipeline passes exact SD raster/edge checks and removes the virtual display on Stop.

Distinct virtual-display serials per desktop dimensions prevent macOS restoring1024×768 onto an HD screen sharing the old identity. Sequence HD→PAL→NTSC probes passed requested actual desktop size, edge colour, exact output raster and display removal; a final return-to-HD check is part of packaging validation.

## 0.1.39

Stretch uses whole-current-display → whole-output-surface rather than retaining startup crop dimensions. Reversible temporary-display live tests pass all11requested resolutions, with one stream running throughout, into HD/PAL/NTSC exact rasters. Fresh alternating quadrant pattern prevents accepting a stale frame; all4quadrants checked. Temporary screens removed. Baseline38 fails first live change, confirming regression coverage. Native build/deep signatures and existing offline UI checks passed; installer checks run during packaging. No physical USB/TV timing claim. User confirmed installed38 PAL/NTSC extended screens appear and work.

## 0.1.40


PAL/NTSC x two input aspects x six output sizes passed guarded UYVY resampling checks, including luma/chroma separation, borders and row padding. All 24 actual camera CVPixelBuffer paths and CMIO format descriptions passed dimension, pixel-aspect, black-frame and frame-duration checks. Native samples remain unchanged. Existing live-picture fixture and isolated UI tests passed without real USB, preference, audio or helper actions. Installer mock/payload/signature checks run during packaging. Long live recordings and third-party recorder metadata retention still need user testing after installation.

## 0.1.41


In-memory tests use deliberately different first/second fields for PAL and NTSC, in both separated USB field blocks and interleaved input layouts. Both input aspects, both field orders and native/1080i passed actual camera-buffer checks with no cross-field blending. Native field bytes are preserved exactly; output row padding and guard bytes are untouched. Actual intercepted CMIO sample delivery verifies 25 / 29.97 fps timestamps and durations, field metadata and unchanged progressive cadence. Stream property durations agree with advertised format durations. Settings, native UI, existing progressive scaler and installer tests also pass. No USB capture, audio route or production preference is changed by those fixtures.

Live recorder compatibility, physical source field dominance and saved-file field tags require checking after installation. The user has confirmed 0.1.40 progressive 1080p / 16:9 capture looks correct; this does not qualify the new interlaced path. The experimental signing/security setup remains unchanged.

## 0.1.42

New software-ProRes recorder tested by actual encode/decode across 16 PAL/NTSC x native/HD x field-order x progressive/interlaced combinations. Field metadata, separate luma rows, PCM stereo channel data and rational frame durations pass. Existing output file protection, changed camera format, backwards PTS and bounded audio overflow are covered. Direct CMIO preview converts UYVY and honours PAL 4:3/16:9 pixel aspect without changing samples. Native UI tests and 21 installer mocks pass. A five-second live capture has two-field ProRes and matching timeline lengths, but its silent input does not qualify physical audio/sync. No installed drivers/settings/audio routes were modified. Long capture, physical A/V synchronization, real-time HD throughput, and installed new UI still require testing. Private QA footage is excluded from source/release.

## 0.1.43

System TCC logs independently confirm the installed42 app was refused Camera access because its bundle lacked NSCameraUsageDescription. Added both privacy descriptions and explicit AVFoundation consent gates. Preview no longer starts USB automatically at launch. Existing16 encode/decode cases now use nanosecond-quantized NTSC timestamps, catching and fixing sub-nanosecond false backwards-timing errors. Full audio samples are limited to the video horizon. UI startup/Stop/Quit, CoreImage preview and exact metadata/helper installer guards pass. User confirmed repeat1080p25 colour-bar/moving-block HDMI playback stable; sender logged zero USB packet/transfer errors. Raw incoming source timing reported NTSC during PAL/S-Video diagnostics; originalPAL restored, live source disagreement unresolved. No installed binary/security/audio-route changes made during preparation.

## 0.1.45 — return from recovery app44

Packaging-only update of feature app43. Byte comparisons confirm src, unified/src and vendor unchanged. Mach-O loadable sections match43 for host, recorder, playback, display and camera extension. Host version45 and ad-hoc signature updated; camera19/output12/HAL3/Premiere1 retained. All21 installer mocks pass, including upgrade guards. Expanded package signature/payload/source checks run during packaging. Read-only live diagnosis after the user's TBC correction reports PAL/S-Video with activecamera19 while recovery host44 is installed. Physical recording sound/sync and long real-time HD capture still require user confirmation. No live capture, settings, drivers, audio route or security changes made during packaging.

## 0.1.46 — input UI, meters, local listening and idle source

Host46 adds Apply pause/reconnect callbacks with bounded external-client retry, draft/error handling, recording protection and input controls disabled while applying. Offline native UI regression passes with fake CMIO/defaults/audio/routes/tasks: zero real device writes or helper launches; actual simulated format success, failure and external-use paths verified. Layout/hit tests pass for listening controls, corrected tab labels, driver actions and adaptive preview/meter placement; rendered screenshots visually reviewed. Preview pixel conversion/PAR regression passes. Actual monitor ring tests pass independent gain/mute, unchanged original PCM, pre-fader peaks, planar/interleaved stereo and bounded overflow/latency.

Dedicated idle source tested through actual Playback::nextWireFrame at all6modes: exact wire packets and silent audio for hold-without-frame/black/colour bars; no fallback moving block or editor timeout. Existing sender startup regression passes including FCP/ Premiere readiness and no production helper/device actions. Host/recorder/display/playback native build and deep signature checks pass. Camera19/output12 bundle files compare byte-identical to45; HAL3/Premiere1 retained. 21 installer mocks and expanded exact payload/source/signature checks run during packaging. Actual speaker/headphone listening, physical meter readings and a short recorded sample still need user checks after installation. No installed app/drivers, settings, audio route, input volume, permissions or security changed by preparation; no GitHub publication. Private QA excluded.

## 0.1.47 — recording codec selection and default player

All seven codecs tested by actual encode/decode in 96 PAL/NTSC x native/HD x field-order x supported field-count cases. ProRes422/LT/HQ/Proxy and uncompressed preserve field count/order and distinct field-row luminance; progressive H264/HEVC preserve expected metadata/timing/SAR/stereo. Lower-quality progressive codecs are checked in flat regions away from spatial edges, avoiding an incorrect requirement for lossless Nyquist-line detail from Proxy. Uncompressed uses timed source samples without a video encoder. Runtime guards reject interlaced H264/HEVC before accepting frames. Existing overwrite, format-change, backwards-PTS and audio-overflow checks pass.

Offline combined UI0failures verifies menu geometry/target, independent saved codec preference, progressive-only item disabling, Record gating, recording protection, Apply paths and workspaceURL opening of an existing non-empty movie. Fake workspace receives the fileURL, so no user player is launched by tests. No live USB capture, input/audio-route writes, permission/security changes or driver activation during testing. Long sustained codec throughput, installed player opening and physical source/audio sync still need user testing. Native app build/deep signatures and installer mock/expanded exact payload/source checks run before delivery. Camera19/output12/HAL3/Premiere1 are unchanged. Private QA excluded.

## 0.1.48 — Shuttle Video, two Final Cut destinations

Universal arm64/x86_64 builds of host48, camera21, output13, HAL4 and Premiere2 target macOS14.4+. The minimum retains CMIO stream-latency reporting used by the qualified output design; compiling for Intel does not qualify Intel hardware or older macOS runtime. Internal bundle/executable, hardware device and audio UIDs remain stable. Serial control is deferred. No publication is performed.

The extension validates six exact singleton formats, bounded latency and distinct Virtual Shuttle/Intensity Shuttle names/UUIDs linked to the stable audio UID. The virtual helper uses its own loopback endpoint, no USB and no ScreenCaptureKit. Actual frozen-CMIO producer to generic receiver tests deliver30changed frames per each of6formats with the exact SAME PTS/timecode, verify changed bytes and one acknowledgement per received frame, hold-without-extra-ack, readiness gating and reconnect. Thus timestamp equality never suppresses a freshly rendered paused edit. Credits, publication, old transport/reconnect, ack bursts, wire clock, audio cursor and timestamped audio regression pass on isolated test ports.

Offline actual CoreImage conversion/AppKit view raster tests pass all6formats, SD display aspect, independently owned refreshed image buffers and Fit/Fill/Stretch. Outgoing PCM and L/R readings remain unchanged with listening disabled. Existing monitor-ring tests verify separate gain/mute, unmodified PCM, pre-fader stereo peaks and bounded queue/latency. Meter and timecode pixel/placement/translucency tests pass. Actual96codec encode/decode cases pass PAL/NTSC SD/HD, compatible field counts/orders, separate field rows, metadata/PCM/timing and safety guards; in-memory camera/interlaced scaling/sample-clock fixtures pass. No live USB capture or real audio-route writes occur in those tests.

Hidden UI tests use fake CMIO/audio/defaults/task/workspace APIs:0failures, target/hit geometry, new destination and speaker/volume controls, separate virtual/hardware sync preferences, existing codec/recording/settings paths and zero real helper/device/route writes. Screenshots are actual control renders with example devices; they do not prove a live Final Cut connection. Installer24mocks pass migration/backup/retirement, changed/unchanged audio, active process/capture guards, newer/unrelated bundles, symlink/state ownership and architecture/OS boundaries. Packaging additionally expands and compares exact signed payloads and verifies complete corresponding source.

Live Final Cut tests of effects/colour/titles both paused and playing, selected-screen sound/listening/mute/meter behaviour, sync and physical output regression remain required after installation/activation. Intel, HDR, long sessions and all editor versions are unqualified. Installed apps/drivers, security settings and system audio routes remain unchanged during preparation.

## 0.1.49 — scopes and simultaneous Virtual + Shuttle

Installed48 startup failure was traced to active output12, then to macOS's failed replacement launch (launchd37 Operation already in progress) even with13 marked enabled. After the old job had exited, a repeated activation started output13. The app visibly reached Ready for Final Cut without reboot/security changes. This confirms readiness, not live timeline quality; the user's FCP playback test is pending.

New host49/helpers build universal arm64/x86_64 with14.4 deployment. Exact directory comparisons show camera21/output13/HAL4/Premiere2 unchanged byte-for-byte from48. Capture/recording/codec implementations are unchanged. Hidden UI tests pass0failures with fake CMIO/audio/defaults/tasks/workspace: destination3, both connection/display controls, independent View/overlay choices, target geometry, physical sync key for simultaneous mode, previous capture/recording paths, and no live helper/device/route actions. Output panel adapts to available screen height and scrolls on small screens. Example UI and original synthetic scopes images were visually inspected.

Scope fixtures verify SDR black/white/superwhite,601red, luma bins, histogram counts, neutral vector, legal UYVY conversion, all6scope views at SD/HD and Video passthrough. HD render timings were about2–5ms on this Mac, with an80ms scope refresh cap. Existing screen conversion/aspect/sizing tests pass all6video modes. An isolated preference-domain test verifies separate virtual/hardware view, guide/timecode flags/positions and preserved physical audio sync.

Actual cross-process mmap tests verify untorn image/PCM/timecode, ready/stop, mode guards, bounded latest-frame storage and immediate drop instead of blocking a busy reader. Actual Playback::nextWireFrame tests run all6output modes×Video/FourUp, compare exact existing Video USB packets, and verify the other destination retains the clean pre-overlay rendered picture/timecode when the hardware shows scopes. The USB wire clock/credit/ack implementation remains unchanged; simultaneous mode uses that master and only one Core Audio receiver/listening copy. A Mac screen helper cannot issue extra FCP acknowledgements. Parent/child stop/failure and parent-death guards bound paired lifetimes; no actual USB transfers occur in the fixtures.

All24installer filesystem mocks pass host49/upgrade/migration/capture/editor/process/version/symlink/OSarch guards. Packaging expands and checks exact signed/universal payloads and complete corresponding source. Live simultaneous FCP/TV/Mac operation, view reversal, paused/playing effects/title updates, listening/mute/meters, physical sync and long-session stability still require installed testing. Intel runtime remains untested. No GitHub upload or serial/deck-control implementation.
