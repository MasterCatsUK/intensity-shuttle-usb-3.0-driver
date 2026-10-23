# Shuttle Player 0.1.1 validation — 19 October 2026

- User reported TV playback was perfect but the app preview was choppy. Confirmed cause: preview publication only every fifth frame and 10 Hz UI polling.
- Every output frame is now eligible for preview publication. The private, versioned channel contains eight bounded frame slots; a local steady clock presents buffered frames at the output cadence. Nonblocking advisory locks keep the UI from waiting on or blocking USB. Reusable RGBA conversion storage is private and conversion runs before the short shared-memory lock.
- Interface polling uses a 60 Hz timer in common run-loop modes, so dragging the scrub bar does not suspend preview refresh. Diagnostic file writes run on a serial background queue, and FIFO diagnostic logging is reduced to once per ten polls. Actual FIFO poll/control intervals are unchanged.
- Pure cadence tests simulated 600 UI refreshes with 32-ms USB delivery bursts: all 250 due frames at 25 fps and all 300 due frames at 29.97003 fps were presented, with bounded recovery after a stalled UI.
- Real AVFoundation decoding tests passed all 18 mode/scaling combinations, including pause/seek/resume, gain/mute, EOF/replay/loop, fractional audio counts and the version-2 preview ring. Background seek tests also passed.
- AppKit checks passed native SF Symbol images, no text titles on transport buttons, transport group centred to within one point, continuous scrubber subclass, full-rate timer and safe initial state without USB start.
- Both arm64 and x86_64 host/helper slices compiled and linked; deep signatures verified. Intel and older macOS remain untested.
- Live 1080p25 test measured 25.20 then 24.92 preview frames/s in five-second windows (target 25 fps). User first confirmed TV output was good, then confirmed both app and TV were okay. This validates usability on this Mac Studio, not exact preview-to-TV latency or all hardware modes.
- OutputPacket.hpp is byte-identical to the previously working playback encoder. No packet-format, USB transfer scheduling, FIFO feedback, movie decoding, audio routing, driver or security changes were made for this update.
- Actual screenshot uses the project's synthetic colour-bar/beep movie. No user's movie footage, paths, private logs or SDKs are included in the release.

## Previous: Shuttle Player 0.1.0 validation — 19 October 2026

- Both host and output sender successfully compiled and linked as arm64 and x86_64; universal binaries contain both slices. Both slices declare macOS 13.0 as their minimum target. Intel runtime and older macOS are untested.
- Native real AVFoundation decoding passed 18 output-mode/scaling combinations (six formats × three sizing choices). Checks include backwards/forwards seeking with a reader time range, silence during pause, audio after resume, half gain and mute, EOF/replay/loop, Stretch reaching frame edges, fractional-rate PCM lengths, and private preview-channel contents.
- Background seek test passed: rapid requests coalesce and decoding occurs outside USB-side rendering, holding picture/silence while a seek loads. The fixture check bounds each paused render to under 100 ms; it is not a full sustained throughput benchmark.
- AppKit offline checks passed: menus, ScrubSlider subclass/continuous tracking, disabled transport before a file loads, and no automatic USB start.
- Real UI opened and loaded a synthetic MOV; Play/Pause, scrub bar, six output formats and Stretch were visible. Actual screenshot is included in docs.
- A live 1080p25 comparison used the existing 0.1.39 sender and then the new Player with the same bright colour-bar / moving-block / beep movie. User confirmed picture and sound from the earlier sender, then answered “yes” to the new Player picture/sound/scrub check. Treat this as a basic usability check, not a frame-accurate sync measurement.
- Initial short comparisons were reported black; continuous looping tests subsequently worked. No driver, firmware or security change was made. No proven hardware fault or exact cause of the earlier black picture was established.
- Player Play normally terminates Shuttle Camera and waits for it to finish saving/closing (up to 20 seconds) before launching the USB sender. It never force-kills camera recordings or third-party apps. Camera's existing quit path finalizes its recording. External capture clients still cause a safe preflight failure. The new handover UI has been built; handover during an active long recording has not been live-qualified.
- The output sender's USB scheduling, packet framing and FIFO feedback derive from the previously working Shuttle Camera sender. Stop cancels transfers and restores input alternate setting; Player has an eight-second watchdog for its own sender. No camera/audio extension or editor plug-in was added or replaced.
- Player reads Camera output format/connection at launch, with capture-standard fallback. Settings are copied into Player only; no inherited timecode, meters, safe-zone or idle-screen overlay path exists in Player.
- App and helper signatures verified with codesign --verify --deep --strict. They are ad-hoc development signatures, not Developer ID or notarization.

Only generated test video and UI screenshots are included. No user's captured material, Adobe SDK, credentials, machine logs or private QA is distributed. No GitHub publication has been performed.
