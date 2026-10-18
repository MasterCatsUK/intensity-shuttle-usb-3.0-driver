# Shuttle stereo audio input — local development build

Installed on this Mac as **Intensity Shuttle — Stereo Audio**, a two-channel,
48 kHz input. The user confirmed QuickTime's input meter and a recorded movie
both have sound on 17 October 2026.

In QuickTime's New Movie Recording menu, select **Intensity Shuttle — PAL
S-Video** as Camera and **Intensity Shuttle — Stereo Audio** as Microphone.
Keep the Shuttle camera running: this version receives audio from the camera's
USB capture, so audio-only use without an active Shuttle camera is silent.
The VCR's red/white audio leads must connect to the Shuttle's analogue inputs.

The camera still supplies 720 × 576 at 50p, converted from PAL's 50 fields per
second. Audio takes the first two of the Shuttle's eight 24-bit channels and
publishes 32-bit float PCM without reducing the original sample precision.

## Verified

- Core Audio and AVFoundation list the new input and receive real stereo PCM.
- One native 10-second test received 489 video frames and 482,496 stereo audio
  frames (including startup/stop boundaries). RMS 0.094565; peak 0.825684.
- The user confirmed microphone selection, meter movement and recorded sound
  in QuickTime after installation.
- PCM24 sign conversion, malformed-packet rejection, distinct stereo channels,
  stale-data silence and transport stop/restart pass under ASan/UBSan.

This is an experimental local build on macOS 27.0.1 / Apple silicon. Source
loss and video lock interruptions can produce silence; the short test is not
proof of continuous capture or long-term A/V synchronization. Zoom, Final Cut,
audio-only capture and simultaneous audio clients are not qualified.

## Implementation

`Shuttle Audio.driver` is an input-only Audio Server plug-in under
`/Library/Audio/Plug-Ins/HAL`. It uses libASPL for Core Audio property handling.
The camera service owns the USB connection and sends timestamped stereo packets
through loopback UDP. Traffic is restricted to 127.0.0.1:49381. The input uses a
bounded atomic ring, returns silence for missing/stale frames and reports an
80 ms buffering latency. No external network service or firmware change is used.

The camera extension and audio plug-in are ad-hoc signed for this Mac's existing
development setup. SIP is disabled and extension developer mode is enabled.
Restoring SIP may prevent these local builds loading; this has not been tested.

## Build

With Command Line Tools installed:

```sh
./build.sh
xcrun clang++ -std=c++17 -O1 -g -fsanitize=address,undefined \
  -DSHUTTLE_AUDIO_PORT=49383 -Wno-reorder-init-list \
  -Ivendor/libASPL/include -Isrc tests/audio_test.cpp build/objects/*.o \
  -framework CoreFoundation -framework CoreAudio -o build/audio-test
./build/audio-test
```

The test uses a different local port so it does not interrupt live capture.
Building does not install or restart anything. Install Audio.command installs
the included driver through a native macOS administrator dialog and briefly
restarts Core Audio. It refuses to overwrite an existing Shuttle Audio.driver.

To remove it, close camera/recording applications, move Shuttle Audio.driver
out of `/Library/Audio/Plug-Ins/HAL` using Finder with administrator approval,
then restart the Mac. Deactivating the camera extension alone does not uninstall
the separate audio plug-in.

## Source licences

Project source is GPL-2.0-or-later; see COPYING. libASPL is included with its MIT
and Apple notices, pinned to commit 633e0f70203edd87d320fc5a3cae901e1363aac5:
https://github.com/gavv/libASPL
