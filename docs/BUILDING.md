# Build and modify Shuttle Video + Shuttle Player

Run commands from the repository root. Adobe SDK files are obtained separately.

## Build the whole installer

1. Use an Apple-silicon or Intel Mac with the macOS27 SDK/Command Line Tools (the tested compiler environment), Python3, make and normal Apple command-line signing/package tools. Full Xcode or a compatible Command Line Tools installation is needed. `xcode-select --install` requests Apple's installation if missing.
2. Obtain the Premiere Pro C++ SDK separately from Adobe. The tested SDK was26.0; the plug-in uses transmit interfacev1 and was used with Premiere25.2.3. Adobe headers/sample code are not redistributed in this source folder.
3. In Terminal, change to this folder. Keep the SDK outside it, then run:

```sh
./build-release.sh "/absolute/path/Premiere Pro 26.0 C++ SDK/Examples"
```

The script builds camera+app, HAL3 audio, and the Premiere transmitter, stages sources and binaries, then builds/expands/checks the installer. Results are in `build/packages`. Everything stays under this source folder; nothing is installed, activated or flashed. Repeated staging is deliberately refused: move `build/release-source` aside before repeating a complete package build. Existing work is not silently deleted.

The scripts build universal arm64/x86_64 binaries targeting macOS 14.4+. Intel and older macOS runtime are untested. CMIO stream latency requires 14.4. The Adobe SDK is a separate download; its headers are not redistributed.

## Build individual components

```sh
./build.sh                         # capture extension + unified app
./audio/build.sh                   # Core Audio driver
./unified/premiere/build.sh "/absolute/path/to/Adobe SDK/Examples"
```

The app is `build/Shuttle Video.app`, audio is `audio/build/Shuttle Audio.driver`, and the Premiere bundle is `unified/premiere/build/Shuttle Transmit.bundle`. You can build the app/audio without downloading Adobe's SDK. The Premiere bundle remains separate from the app and is installed into the shared Adobe Plug-ins location by the installer.

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

The optional guide generator is `docs/source/build_readme.py`; it writes to `user-guide` using its included screenshots. It needs Python packages reportlab and Pillow; it is not needed to build the app. Use a Python virtual environment if installing those packages. PDF rendering/QA used Poppler; PDF extraction checks used pypdf.

## Build the separate Shuttle Player

From the repository root:

```sh
cd player
./build.sh
./tests/run.sh
```

Player builds independently of the main app and Adobe SDK. It targets macOS 13+, producing arm64/x86_64 slices; Intel and older macOS runtime remain untested. Its script verifies pinned inputs in `vendor/web-tools/SHA256.json`, builds QuickJS and the minimal LGPL FFmpeg for both architectures and packages the official standalone yt-dlp helper. These inputs, licences and build recipes are included in the repository and release source. No Homebrew or Python installation is required by Player users; Python 3 and Apple build tools are needed to build/test. See [Player build and validation details](../player/README.md). The main installer build above does not build or install Player.

The combined companion release is assembled by `tools/package_companion_release.py` from an existing verified main installer and Player release folder. Run it with `--help` for arguments. It archives the exact clean repository commit; it does not rebuild, install, sign with Developer ID, publish or modify drivers.
