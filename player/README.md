# Shuttle Player

A separate macOS player for **Intensity Shuttle USB 3.0**, companion to Shuttle Video. Current version: **0.3.2**.

## Open a web video

Choose **File → Open Video URL… (⇧⌘O)** and paste a **YouTube, Dailymotion or Vimeo** link. Choose a playback method, then **Open and Play**:

| Method | Behaviour | Controls |
| --- | --- | --- |
| **Download first** (default) | Downloads and prepares the complete movie before playback. Reliable seeking and replay. | Play/Pause, Stop, scrub, ±10 seconds, Loop and volume. |
| **Stream** | Resolves the link and starts once about three seconds of paired picture and sound are buffered. The rest arrives during playback. | Play/Pause, Stop, scrub, ±10 seconds and volume. Loop uses Download first. |

The app opens normally with no URL box. The File menu remembers your last method. Download first shows download percentages and an animated preparation bar. Stream shows lookup, seeking and buffer progress; initial startup also includes site lookup/connection time. If streaming runs short of data, picture holds with silence while the paired buffer refills. Stop releases the stream and the Shuttle. Drag the scrub bar and release to jump to another position; the app holds picture with silence while the new position loads. A paused seek stays paused, while a playing seek resumes. Rapid choices use the latest position. At the end, press Play to replay or scrub back. Some site links expire; reopen the original link if needed. Choose **Download first** when you need seeking, looping or playback without a continuous internet connection.

Picture and stereo sound go through the selected Shuttle output. **Stretch is the default**, with Fit/Fill available. Choose HDMI and your PAL/NTSC/1080 format before opening the URL. Source video up to 1080 is requested; upscaling adds no detail. Local files still use **Open Video… (⌘O)** and wait for Play.

Public on-demand videos are supported when the site makes a compatible stream available. Sign-in/password-only videos, DRM-protected content and live/upcoming streams are not supported. No browser cookies or account credentials are read. Playlist URLs are restricted to the first item. Site changes, removals, regions and format availability can still cause failures. Use videos you have permission to play.

Download first needs a network connection while preparing; seek/loop then use the local file. Prepared movies are removed when replaced or the app quits normally. Force quitting can leave cache files under `~/Library/Caches/local.shuttle.player/Web Videos/`; macOS may purge them. These are playback cache files, not a permanent Downloads library.

Stream keeps a bounded buffer in RAM (up to about 500 MB of decoded video at 1080, plus decoder/preview memory), rather than storing the complete movie. Pause fills that buffer and applies backpressure to the decoder. Stream connection/decoder failures stop output with a message; use Download first if a site stream is unreliable. Actual live broadcasts remain unsupported.

Bundled helpers: pinned yt-dlp2026.10.26, QuickJS2026-06-04 and an LGPL FFmpeg8.1.3 build for HTTP(S)/HLS decoding and movie preparation. Streaming video is decoded/scaled by FFmpeg; local files and Download first keep the AVFoundation decoder. No Homebrew/Python installation or new driver is required. The site resolver runs separately; the streaming decoder runs in its own supervised process with bounded audio/video queues. USB framing and FIFO feedback are unchanged. No main Shuttle Video app, camera/audio driver, FCP or Premiere plug-in is modified.

## Player controls

- Open a movie, then Play/Pause or Stop. Play cleanly quits Shuttle Video and waits for its recording/output to finish before taking over; no forced termination of recordings or third-party apps.
- Scrub bar, elapsed/total time and ±10-second controls.
- Loop and independent playback volume; no Mac sound-route changes.
- Smooth, buffered preview at the output cadence (25/29.97 fps); native icon controls centred below the scrub bar.
- **Stretch by default**: the entire movie fills the selected output raster. Fit and Fill are optional.
- Starts with Shuttle Video’s saved output format and connection (PAL/NTSC included); manual Player choices stay local. No meters, timecode or safe-zone burn-ins.
- PAL/NTSC SD and 1080i/p at 25 or 29.97 fps output cadence.
- HDMI, S-Video, composite and component connection choices; analogue SD formats restricted appropriately. Connections are format compatibility choices, not independent physical-port switches.
- About, Help, Licence and Quit menus.

Shuttle Video's capture, extensions, audio driver and editor plug-ins are unchanged. Close third-party capture/output clients before using the Player. Play explicitly starts USB output; opening a local file alone does not. Open Video URL → Open and Play starts after preparation or initial streaming buffering.

![Shuttle Player interface](docs/Shuttle-Player.png)

## 0.1.1 update

The original preview was deliberately sampled at about five frames per second. It now publishes every output frame to a bounded preview ring, and the UI presents them at a steady cadence while remaining responsive during scrubbing. The TV packet format, audio, USB scheduling and FIFO feedback are unchanged. Live app/TV picture and sound were confirmed by the user; the local preview measured about 25 fps in the 1080p25 test. Intel remains untested.

## Build

On a Mac with Xcode/Command Line Tools, run:

```sh
./build.sh
```

The script builds both `arm64` and `x86_64` slices, including libusb, and creates `build/Shuttle Player.app`. Build target: macOS 13+. Native Apple silicon build and offline tests have been checked on macOS 27.0.1. **Intel hardware and older macOS versions remain untested.** Cross-compilation is not runtime qualification. Intel runtime remains untested.

The app is ad-hoc signed, not Developer ID signed or notarized. No installer, driver activation or security-setting changes occur during building. Editable Player source, pinned helper sources/input hashes, build scripts and notices are supplied. The official standalone yt-dlp helper has separate third-party licences; see resources/Web-Licences and vendor/web-tools.

## Tests

```sh
./tests/run.sh
```

Generates its own small synthetic movie with timed flashes/tones, decodes actual video/audio, and checks 18 mode/scaling combinations: seeking both directions, pause/hold/resume, gain/mute, looping/end/replay, whole-frame Stretch, fractional audio cadence and preview IPC. AppKit checks menus, scrubber subclass and safe initial state without starting USB. Generated files stay under build/tests and are excluded from the release source archive.

Live HDMI picture and stereo sound at 1080p25 were confirmed by the user on the Mac Studio. Precise TV audio/video alignment and other Player modes remain to be measured. The release includes a small, original colour-bar/beep movie for a repeatable output check.

The USB scheduler and FIFO feedback are retained from Shuttle Video 0.1.47, but this Player's transport controls are new. It is not a frame-accurate deck controller or an interlaced archival recorder.

See **Read Me.html** for usage, output formats and troubleshooting. GPL-2.0-or-later; see COPYING and THIRD-PARTY-NOTICES.md. No affiliation with Blackmagic Design.

## URL playback checks

Live preparation of YouTube “Me at the zoo”, Dailymotion “Office Christmas Party Review” and Vimeo “Big Buck Bunny” produced readable picture-and-audio files. Actual Player decoding, seeking and pause/hold were checked without USB. A protected Vimeo example was rejected. This is not a guarantee that every link works. The new URL flow still needs a live HDMI user check; prior local-file HDMI playback was user-confirmed. See VALIDATION.md.

## Streaming checks

Streaming adds its own decoder/buffer path; Download first and local playback retain the earlier path. See VALIDATION.md for real decoder, starvation/cancellation, site and UI checks. Live HDMI verification of Stream mode is still pending. Intel and older macOS runtime remain untested.

## 0.3.2 YouTube buffering fix

YouTube media is fetched in bounded 1 MiB ranges using FFmpeg8.1.3, avoiding long open-ended media requests. The paired three-second playback buffer and memory caps remain the same. A deterministic HTTP server test rejects oversized/open-ended requests and verifies the entire fixture can still be read. See VALIDATION.md for the sustained test on the reported long video. This improves delivery; a connection slower than the video still requires buffering.

## Streaming scrubbing (0.3.2)

Seeking restarts the online decoder at the requested time and refills the paired buffer without downloading the full movie. Seek requests commit when you release the slider; ten-second skip controls work too. Network work and retiring the old decoder happen away from the USB callback. Briefly, both old and new bounded decoder buffers may exist during a seek, so peak RAM can be higher than steady playback. Picture stays steady and audio is silent while waiting. Availability and seek support depend on the site; expired links must be reopened. See VALIDATION.md for the synthetic sync tests and public-site probes.
