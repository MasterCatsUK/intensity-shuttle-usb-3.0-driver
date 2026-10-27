# Code and assets

Shuttle Player is GPL-2.0-or-later community software, derived from the Shuttle Camera project's playback implementation. Full GPLv2 text is in COPYING. Modified sources are dated 19 October 2026. No warranty is provided.

- libusb 1.0.29 is LGPL-2.1-or-later. The complete, unmodified upstream source archive (including COPYING and notices) is included in vendor/libusb-1.0.29.tar.bz2. The build script builds separate static libraries for each architecture. The Player and its source are provided together so recipients can rebuild/relink with a modified libusb. The macOS 13 build disables configure detection of pipe2, a newer macOS function, to use libusb's existing pipe/fcntl fallback; no upstream source edit is required.
- Apple frameworks and SDK are system dependencies, not redistributed. Install Xcode/Command Line Tools separately.
- The SVHS icon is the original Shuttle Camera project artwork, generated from a text-only prompt without a reference icon. Its provenance is in resources/ICON-NOTE.md. It is included under the project GPL-2.0-or-later terms; no claim of exclusive copyright in AI-generated elements is made.
- The synthetic test generator is derived from Shuttle Camera's original GenerateSyncMovie.mm. The fixture contains generated test imagery and tones only. No user video or proprietary SDK is included.

Blackmagic Design, Intensity Shuttle, Apple, Adobe and other product names identify compatibility. This project is independent and claims no endorsement.

## Web-video tools (0.3.1)

- yt-dlp2026.10.26: the official `yt-dlp_macos` release asset, hash verified against its release SHA256 manifest. yt-dlp itself is Unlicense; its PyInstaller-bundled executable includes third-party/GPLv3+ components with separate terms. Retain the full `resources/Web-Licences/yt-dlp-THIRD-PARTY.txt` and LICENSE. These helpers are separate executables, not linked into Player. Official source: https://github.com/yt-dlp/yt-dlp/tree/2026.10.26 . Corresponding project source archive and upstream licence/source references are in vendor/web-tools and the licence file.
- QuickJS2026-06-04, Fabrice Bellard and Charlie Gordon: MIT. Unmodified source archive included; native universal qjs built locally. Full licence retained. https://bellard.org/quickjs/
- FFmpeg8.1.3: LGPL2.1+ configuration, no GPL/nonfree components enabled. Unmodified full source archive and LGPL/full upstream notices included. Minimal static HTTP(S)/HLS decoder/scaler/resampler and stream-copy mux/probe, using macOS Secure Transport for TLS; rebuild/relink using tools/build_web_tools.sh and supplied sources. https://ffmpeg.org/

All helper input hashes are pinned in vendor/web-tools/SHA256.json. tools/build_web_tools.sh builds QuickJS/FFmpeg for both architectures, combines universal binaries and retains notices. Ad-hoc signatures are added locally. No helper self-update or remote plugin/EJS component download is enabled by Player. No site movie/test cache is distributed.
