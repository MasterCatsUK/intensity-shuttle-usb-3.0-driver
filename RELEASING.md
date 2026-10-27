# Combined companion release

Repository: https://github.com/andrewvideo/intensity-shuttle-usb-3.0

Current release: **Shuttle Video 0.1.54 + Shuttle Player 0.3.2**, tag `v0.1.54-player-0.3.2`. Main installer and drivers are unchanged. Do not relabel or replace the historical `v0.1.54` source/installer; publish this matching companion source under its own tag. Player is copied into Applications separately, not installed by the main package.

Commit the complete Player source, pinned helper inputs/build recipes, licences and current README. From a clean committed checkout, run `python3 tools/package_companion_release.py --help` to assemble the Complete ZIP and exact repository source archive using the previously verified installer and Player release folder. Compare the main package hash with the original 0.1.54 release, verify Player signatures, manifests and ZIP contents, and upload the full main package, standalone Player ZIP, Complete ZIP, exact tagged source ZIP and SHA256.txt. Match release text to these exact files. Do not mark a new main-app version or claim a new HDMI/Intel qualification from software tests alone.

The main installer can still be built with `build-release.sh`; see docs/BUILDING.md. The companion packaging command never builds or changes it. Preserve licences/vendor notices. No Adobe SDK headers are distributed; obtain SDK separately to rebuild Transmit2. Do not distribute cached site videos, signed stream URLs, user clips, older restricted icons, Final Cut libraries, SDKs or local diagnostics.

Retain unsigned/ad-hoc/no-notarization, main extensions’ SIP development requirements, Intel/fresh-machine validation limits and pending live-check status in public text. The README and docs/Whats-New-Player-0.3.2.md describe the companion release; docs/Whats-New-0.1.54.md describes the unchanged main app. Older PDF/HTML guides are historical. A GitHub Latest label identifies the newest combined download, not signed consumer-release qualification.
