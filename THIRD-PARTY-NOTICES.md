# Third-party code and assets

Retain all upstream copyright and licence notices when modifying or distributing this project. This summary does not replace their full licence texts.

See [Credits and acknowledgements](CREDITS.md) for upstream authors, the role of each dependency, implementation references and design inspiration, and the [web-helper credit index](docs/credits/WEB-HELPERS.md) for the retained yt-dlp notice catalogue.

- **Project / bmusb-derived code:** bmusb is Copyright 2015 Steinar H. Gunderson and licensed GPL-2.0-or-later, as stated in its original README. GPL-2.0-or-later notices appear in project sources. `COPYING` supplies GPLv2. The original bmusb0.7.8 archive, macOS-port notes, headers and modified implementation are in `vendor/`; its own COPYING is also in the original archive. Preserve the original author credits in those files.
- **libusb1.0.29:** LGPL-2.1-or-later as described by its upstream source. The original source archive and full COPYING are included in `vendor/libusb-1.0.29.tar.bz2`. This project builds a static library locally; take the corresponding-source/relinking obligations into account when redistributing binaries.
- **libASPL:** Copyright Victor Gaydov and contributors, MIT. The full author list remains in `audio/vendor/libASPL/AUTHORS.md`; full upstream licence and Apple example-code licence notices remain in `audio/vendor/libASPL/LICENSE`, `LICENSE.apple2012` and `LICENSE.apple2020`. Consult those files rather than applying the project GPL label to every upstream file.
- **Apple frameworks and SDK:** platform dependencies supplied by Apple, not included here. Obtain Xcode/Command Line Tools separately under Apple's terms.
- **Adobe Premiere Pro C++ SDK:** needed to compile the original adapter in `unified/premiere/`. Obtain separately from Adobe and comply with its terms. No Adobe SDK headers or sample code are included in this folder.
- **SVHS project artwork:** generated specifically for this project from a text-only prompt. No third-party reference image was supplied. Included under GPL-2.0-or-later; see `unified/resources/ICON-NOTE.md`. The previous icon-pack assets are not included.


Apple, Adobe, Final Cut Pro, Premiere Pro, Blackmagic Design and Intensity Shuttle are referenced to identify compatibility. No endorsement is claimed.

## Experimental virtual display interface reference

`unified/src/output/VirtualDisplayMain.mm` is an original wrapper using runtime Objective-C interface facts documented in Chromium’s `ui/display/mac/test/virtual_display_util_mac.mm`: https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm . No Chromium implementation is bundled. CoreGraphics virtual-display selectors are undocumented by Apple and may change.

## Startup media

`unified/resources/Startup.m4v` is the Shuttle Video logo movie supplied by Andrew for this project and its public distribution. Only that exported movie is included; no Final Cut library, unrelated test footage or project media is distributed. The original file is retained unchanged.

## Shuttle Player web-video helpers

Player 0.3.2 bundles separate pinned yt-dlp, QuickJS and LGPL FFmpeg executables. Complete helper sources/input archives, hashes and build recipes are under `player/vendor/web-tools/` and `player/tools/build_web_tools.sh`; full notices are under `player/resources/Web-Licences/`. The standalone yt-dlp executable contains third-party components with separate terms, including GPLv3+; do not apply the project GPLv2 label to every helper. See [Player third-party notices](player/THIRD-PARTY-NOTICES.md) for versions, licences and source references. Preserve all notices and corresponding-source/relinking materials with redistributions. No site movies, cookies or credentials are included.
