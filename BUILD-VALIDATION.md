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
