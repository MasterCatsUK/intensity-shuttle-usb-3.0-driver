<img src="unified/resources/AppIcon.png" width="144" alt="SVHS cassette icon">

# Shuttle Camera — editable source, 0.1.31

This folder contains the capture extension, unified macOS app, Core Audio input/HDMI-output driver, USB playback engine, Final Cut CMIO sink extension, Premiere Mercury Transmit adapter, installer, tests, dependencies and artwork used by the local development project. You may modify the code under the applicable licences. Keep copyright notices and provide corresponding source when distributing GPL binaries. Third-party dependencies and Adobe SDK terms are described below.

This is an Apple-silicon/macOS27 development build, tested on one Mac Studio. Its unsigned installer and ad-hoc signed extensions are not a production-signed/notarized public release. Runtime testing currently requires SIP disabled; read docs/user-guide/Read Me.pdf first. Building source does not require changing SIP and no supplied build script performs installation or security changes.

## Build the whole installer

1. Use an Apple-silicon Mac with the macOS27 SDK/Command Line Tools (the tested compiler environment), Python3, make and normal Apple command-line signing/package tools. Full Xcode or a compatible Command Line Tools installation is needed. `xcode-select --install` requests Apple's installation if missing.
2. Obtain the Premiere Pro C++ SDK separately from Adobe. The tested SDK was26.0; the plug-in uses transmit interfacev1 and was used with Premiere25.2.3. Adobe headers/sample code are not redistributed in this source folder.
3. In Terminal, change to this folder. Keep the SDK outside it, then run:

```sh
./build-release.sh "/absolute/path/Premiere Pro 26.0 C++ SDK/Examples"
```

The script builds camera+app, HAL3 audio, and the Premiere transmitter, stages sources and binaries, then builds/expands/checks the installer. Results are in `build/packages`. Everything stays under this source folder; nothing is installed, activated or flashed. Repeated staging is deliberately refused: move `build/release-source` aside before repeating a complete package build. Existing work is not silently deleted.

## Build individual components

```sh
./build.sh                         # capture extension + unified app
./audio/build.sh                   # Core Audio driver
./unified/premiere/build.sh "/absolute/path/to/Adobe SDK/Examples"
```

The app is `build/Shuttle Camera.app`, audio is `audio/build/Shuttle Audio.driver`, and the Premiere bundle is `unified/premiere/build/Shuttle Transmit.bundle`. You can build the app/audio without downloading Adobe's SDK. The Premiere bundle remains separate from the app and is installed into the shared Adobe Plug-ins location by the installer.

## Where to change things

| Folder / file | Purpose |
|---|---|
| `src/CameraExtension.mm` | SD USB capture and camera frames |
| `vendor/bmusb.cpp` | upstream bmusb-derived USB capture implementation / macOS port |
| `unified/src/CombinedHost.mm` | app window, tabs, menus, About, Diagnostics |
| `unified/src/capture/Host.mm` | capture controls |
| `unified/src/output/OutputHost.mm` | output controls and audio routing |
| `unified/src/output/PlaybackTest.cpp` | USB playback sender and output pipeline |
| `unified/src/OutputExtension.mm` | Final Cut CMIO sink extension |
| `audio/src/AudioDriver.cpp` | stereo capture + HDMI Core Audio output |
| `unified/premiere/ShuttleTransmit.mm` | Mercury Transmit video adapter |
| `unified/src/output/Timecode*`, `AudioMeters.hpp`, `SafeZones.hpp` | HDMI overlays |
| `installer/` | package scripts, checks and installer tests |
| `tests/`, `tools/`, `unified/tools/` | offline and explicit live test utilities |
| `docs/` | user guide and its generator source |

`SharedOutputCMIO.hpp` freezes the transport used by qualified output extension12; `SharedOutput.hpp` adds a separately configurable Premiere endpoint. Do not casually merge these or change outstanding completion credits: these protect editor playback. Audio uses48kHz stereo. Premiere's adapter is video-only and leaves the clock in Premiere; HDMI sound uses the separate Core Audio route.

## Testing and version discipline

Run the isolated installer tests without admin rights:

```sh
python3 installer/tests/installer_test.py
```

Most C++/Objective-C++ test sources include a build command or explanation at their top. Offline UI tests use fake device calls/preferences/tasks. Some other tools explicitly start USB output or interact with installed drivers: read the source before running them, and close camera/editor clients as instructed. Do not run live tools during an important recording. Building a binary or passing an offline test does not qualify its physical A/V timing.

When publishing changes, update the host/extension/HAL/plugin versions that actually changed and the matching installer guards/tests. Retain bundles' stable identifiers where compatibility requires them. Do not reuse an already-published package version for different code.

## Licences and public redistribution

`COPYING` contains the project GPL text. Preserve upstream notices, the bmusb source attribution, libusb archive/licence, and libASPL/Apple licence files under `audio/vendor/libASPL`. See `THIRD-PARTY-NOTICES.md` and the publisher checklist. The SVHS project icon is new artwork generated from a text-only brief and is provided under the project licence; see unified/resources/ICON-NOTE.md. Adobe SDK headers must be obtained separately and used under Adobe's terms.

For a normal public release, use the appropriate Developer ID signing/entitlements and notarization workflow and qualify a fresh Mac with SIP enabled. The current development bypass setup should not be described as an Apple-approved consumer installation method.

## Rebuild the guide

The optional guide generator is `docs/source/build_readme.py`; it writes to `docs/user-guide` using its included screenshots. It needs Python packages reportlab and Pillow; it is not needed to build the app. Use a Python virtual environment if installing those packages. PDF rendering/QA used Poppler; PDF extraction checks used pypdf.
