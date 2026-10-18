# Premiere Pro HDMI output integration

Status: SDK supplied by user and extracted under work/adobe-sdk26. Native transmitter and host29 built; offline qualification passed. No Premiere components installed yet; actual Premiere loading/HDMI/audio tests pending. Existing installed Shuttle Capture0.1.28 unchanged.

## Verified environment

Premiere Pro 25.2.3:
`/Volumes/Media HD/Applications/Adobe Premiere Pro 2025/Adobe Premiere Pro 2025.app`

Adobe's official C++ SDK download redirects to Adobe sign-in:
https://developer.adobe.com/console/servicesandapis/pr

SDK archive supplied: /Volumes/Media HD/Downloads/Premiere Pro26.0 C++ SDK MacOS.zip (actual filename includes spaces before26.0). Public interface version1 is used, leaving newer SDK functionality unadvertised. SDK headers remain separate from distributable source.

## Integration design to validate against SDK

Build a native arm64 Mercury Transmit output plug-in. Use Adobe SDK sample and documentation to establish video mode negotiation, frame ownership/lifetime, audio callbacks, playback clock, scrubbing, stop/restart and shutdown contracts before writing the adapter.

Reuse the existing USB playback engine and HDMI renderer. Preserve all six tested PAL/NTSC modes. Reuse saved safe guides, stereo meter rendering and audio offset, verifying whether Premiere supplies real sequence timecode rather than substituting elapsed playback time.

The current video receiver uses one loopback producer, TCP47539 and wire revision003; CMIO extension automatically connects to it. Premiere must not compete for that socket. Add a distinct Premiere source/transport endpoint or explicit producer arbitration, selected by the app, without changing the existing FCP source's behavior. Readiness must reflect USB startup and plug-in connection separately.

Current HDMI audio receiver is UDP49382, float32 stereo at48kHz with absolute sample positions. Establish a common host-time mapping from Premiere playback clock and audio positions before reusing it. Do not assume Premiere timestamps are host timestamps. Prefer direct timeline audio through the transmitter when supported, avoiding global Mac media routing for Premiere. Do not allow HAL and Premiere to write competing timestamped audio streams.

Plugin callbacks must not perform blocking USB/socket operations. Bound queued video/audio and return clock feedback based on actual playback completion; retain previous FCP fixes for outstanding credits and stop/start generations. Release Adobe-owned buffers according to SDK contracts.

## Qualification

1. Compile and load in installed Premiere, confirm a named Shuttle device in Playback preferences.
2. Local synthetic frame/audio and lifecycle tests with a private transport; no installed FCP changes.
3. USB readiness and plug-in enabled/disabled, disconnected, pause, scrub, play/replay checks.
4. User live check of Program Monitor and HDMI motion/audio on1080p25, then supported PAL/NTSC modes.
5. Verify timecode only if SDK supplies actual sequence timecode; verify meters/safe zones/audio offset.
6. Recheck existing Final Cut path after integration changes, then package a versioned installer with matching sources.

## Sources

https://developer.adobe.com/premiere-pro/
https://helpx.adobe.com/premiere/desktop/get-started/preferences-and-settings/display-video-on-a-second-monitor.html
https://github.com/Syphon/Syphon-Transmit (reference only; headers deliberately not included upstream)

## Implemented first adapter

See README.md for the actual design and usage. Premiere owns its playback clock; the initial video transmitter does not implement SDK audio/clock APIs. Audio uses the existing independent HAL3 HDMI route. This supersedes the tentative preference for direct SDK timeline audio above. No direct native audio clock should be claimed.
