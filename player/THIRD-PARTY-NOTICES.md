# Code and assets

Shuttle Player is GPL-2.0-or-later community software, derived from the Shuttle Camera project's playback implementation. Full GPLv2 text is in COPYING. Modified sources are dated 19 October 2026. No warranty is provided.

- libusb 1.0.29 is LGPL-2.1-or-later. The complete, unmodified upstream source archive (including COPYING and notices) is included in vendor/libusb-1.0.29.tar.bz2. The build script builds separate static libraries for each architecture. The Player and its source are provided together so recipients can rebuild/relink with a modified libusb. The macOS 13 build disables configure detection of pipe2, a newer macOS function, to use libusb's existing pipe/fcntl fallback; no upstream source edit is required.
- Apple frameworks and SDK are system dependencies, not redistributed. Install Xcode/Command Line Tools separately.
- The SVHS icon is the original Shuttle Camera project artwork, generated from a text-only prompt without a reference icon. Its provenance is in resources/ICON-NOTE.md. It is included under the project GPL-2.0-or-later terms; no claim of exclusive copyright in AI-generated elements is made.
- The synthetic test generator is derived from Shuttle Camera's original GenerateSyncMovie.mm. The fixture contains generated test imagery and tones only. No user video or proprietary SDK is included.

Blackmagic Design, Intensity Shuttle, Apple, Adobe and other product names identify compatibility. This project is independent and claims no endorsement.
