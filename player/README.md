# Shuttle Player

A separate macOS player for **Intensity Shuttle USB 3.0**, ready to bundle alongside Shuttle Camera in a later release.

- Open a movie, then Play/Pause or Stop. Play cleanly quits Shuttle Camera and waits for its recording/output to finish before taking over; no forced termination of recordings or third-party apps.
- Scrub bar, elapsed/total time and ±10-second controls.
- Loop and independent playback volume; no Mac sound-route changes.
- Smooth, buffered preview at the output cadence (25/29.97 fps); native icon controls centred below the scrub bar.
- **Stretch by default**: the entire movie fills the selected output raster. Fit and Fill are optional.
- Starts with Shuttle Camera’s saved output format and connection (PAL/NTSC included); manual Player choices stay local. No meters, timecode or safe-zone burn-ins.
- PAL/NTSC SD and 1080i/p at 25 or 29.97 fps output cadence.
- HDMI, S-Video, composite and component connection choices; analogue SD formats restricted appropriately. Connections are format compatibility choices, not independent physical-port switches.
- About, Help, Licence and Quit menus.

Shuttle Camera's capture, extensions, audio driver and editor plug-ins are unchanged. Close third-party capture/output clients before using the Player. Play explicitly starts USB output; opening a file alone does not.

![Shuttle Player interface](docs/Shuttle-Player.png)

## 0.1.1 update

The original preview was deliberately sampled at about five frames per second. It now publishes every output frame to a bounded preview ring, and the UI presents them at a steady cadence while remaining responsive during scrubbing. The TV packet format, audio, USB scheduling and FIFO feedback are unchanged. Live app/TV picture and sound were confirmed by the user; the local preview measured about 25 fps in the 1080p25 test. Intel remains untested.

## Build

On a Mac with Xcode/Command Line Tools, run:

```sh
./build.sh
```

The script builds both `arm64` and `x86_64` slices, including libusb, and creates `build/Shuttle Player.app`. Build target: macOS 13+. Native Apple silicon build and offline tests have been checked on macOS 27.0.1. **Intel hardware and older macOS versions remain untested.** Cross-compilation is not runtime qualification. Shuttle Camera's existing Intel port remains a separate next-build task.

The app is ad-hoc signed, not Developer ID signed or notarized. No installer, driver activation or security-setting changes occur during building. All relevant code and libusb source are supplied for rebuilding and modification.

## Tests

```sh
./tests/run.sh
```

Generates its own small synthetic movie with timed flashes/tones, decodes actual video/audio, and checks 18 mode/scaling combinations: seeking both directions, pause/hold/resume, gain/mute, looping/end/replay, whole-frame Stretch, fractional audio cadence and preview IPC. AppKit checks menus, scrubber subclass and safe initial state without starting USB. Generated files stay under build/tests and are excluded from the release source archive.

Live HDMI picture and stereo sound at 1080p25 were confirmed by the user on the Mac Studio. Precise TV audio/video alignment and other Player modes remain to be measured. The release includes a small, original colour-bar/beep movie for a repeatable output check.

The USB scheduler and FIFO feedback are retained from Shuttle Camera 0.1.47, but this Player's transport controls are new. It is not a frame-accurate deck controller or an interlaced archival recorder.

See **Read Me.html** for usage, output formats and troubleshooting. GPL-2.0-or-later; see COPYING and THIRD-PARTY-NOTICES.md. No affiliation with Blackmagic Design.
