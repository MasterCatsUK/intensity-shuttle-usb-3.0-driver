# Release 19 offline installer regression review

Reviewed 17 October 2026. Final intended payload: host 19, camera extension 15,
HDMI output extension 7, audio HAL 3. Output-7 clock/format changes and HAL-3
presentation compensation remain subject to live regression testing.

## Checks performed

- `python3 installer/tests/installer_test.py`: **16 tests passed**, 6.966 seconds.
  Tests run against a temporary filesystem. Process checks, activation-adjacent
  commands, Core Audio restart, app opening, signing and ownership changes are
  mocked; no installed app or live hardware was used.
- Separately parsed `installer/build.sh`, `installer/scripts/preinstall` and
  `installer/scripts/postinstall` with `/bin/bash -n`: passed.
- Builder requires exact identifiers/versions for host19, audio3 and nested
  camera15/output7; package names/receipt version are 0.1.19. A new test accepts
  that complete tuple and rejects output6, camera16 and audio2 payloads.
- Preinstall accepts existing host versions through 19/audio through 3, and
  refuses future host20/audio4; postinstall requires host19/audio3. Mock payload
  expectations agree. The changed-audio test upgrades audio2 to audio3.
- Documentation scan found no stale current-release 17/18 metadata, claims of
  a proven output-7 fix, or claims that implemented CMIO output is unavailable in the
  edited release instructions. The source README retains the historical
  host17/output5 video confirmation as history.

## Mock scenarios covered

Fresh installation; unchanged audio reinstall without restart; changed audio
backup/restart; active or unknown capture rejection; SIP-enabled rejection;
future/unrelated bundle rejection; symlink rejection; capture starting during
installation without a Core Audio restart; Final Cut/settings/output/playback
process rejection; standalone output bundle checks/backup; retirement of the
old standalone output app only after unified payload verification; future
audio4 rejection; exact nested payload versions in the actual builder guard.

## Offline routing tests

`tools/audio_route_test.mm` is GPL-2.0-or-later and includes the actual
OutputHost implementation with every Core Audio function replaced by fakes.
NSUserDefaults is replaced with an in-memory dictionary inside the test
process. It starts no NSApplication, helper or audio I/O and never reads or
writes the Mac's real route/preferences.

Build and run:

```sh
xcrun clang++ -std=c++14 -fobjc-arc -Wno-deprecated-declarations \
  -mmacosx-version-min=27.0 tools/audio_route_test.mm -framework Cocoa \
  -framework CoreMediaIO -framework SystemExtensions \
  -o /private/tmp/shuttle-audio-route-test
/private/tmp/shuttle-audio-route-test > validation/audio-route-test.log
```

**PASS** in `validation/audio-route-test.log`: startup read-only; explicit dOut
only; repeat-click preservation; Stop/helper-exit/quit restoration; later
external choices, including away and back to HDMI; missing prior device retry;
explicit crash recovery; current-route read/write failure; preference-save
failure; route changing during restoration. The fake setter rejects any
attempt to change an input or system-alert selector.

OutputHost and CombinedHost passed native clang++ syntax checks. Route messages
show names, not raw UIDs. The explicit Use HDMI audio button has a tooltip for
default Mac media routing and Stop/helper-exit/quit restoration. No confirmation
dialog was introduced. Parent visually checked the rendered controls.

## Documentation changed

1. `installer/README.md`
2. `installer/PLAYBACK-ROADMAP.md`
3. `installer/resources/Welcome.html`
4. `installer/resources/ReadMe.html`
5. `installer/resources/Conclusion.html`
6. `package-source/shuttle-camera-development/README.md`
7. `package-source/shuttle-camera-development/unified/README.md`

These now describe host19/output7/camera15/HAL3, earlier confirmed native
picture/tone and all-six-format tests, and earlier confirmed Final Cut Pro 11.2
external timeline video. They preserve capture instructions and explicitly
record the later output-6 regression in Final Cut's own viewer. Output7 is not
advertised as a confirmed fix. Timeline stereo and longer A/V synchronisation
remain unconfirmed.

Instructions describe the explicit **Use HDMI audio** button, saved previous
UID, guarded automatic restore, Restore audio recovery and startup with no
automatic route change. They explain that Mac media audio is routed separately
from Final Cut's video, and that Sound settings remains a manual alternative
which users should undo manually afterwards. They also retain
the requirement to start the matching timeline sender before Final Cut's
Window → A/V Output, and turn A/V Output off before stopping the sender.

Blackmagic's official Desktop Video manual independently documents separate
macOS sound-output selection for Final Cut:
https://documents.blackmagicdesign.com/UserManuals/DesktopVideoManual.pdf?_v=1723014010000

## Packaging observations for the final builder

- The actual entry point is `installer/build.sh`; there is no
  `installer/build-installer.sh` in this workspace.
- The builder's initial version guard now checks exact host19/HAL3 and nested
  camera15/output7 before copying payloads. Source archives must contain the
  parent's final matching build scripts/source and the new routing harness.
- In this standalone workspace layout, the builder's fallback
  `installer/../../outputs/shuttle-camera-development` resolves to
  `i/work/outputs/shuttle-camera-development`, which does not exist. Pass the
  intended prepared source bundle explicitly, as planned. When the installer
  is bundled beside `Shuttle Camera.app`, its first default-source branch is
  valid.
- The unified README reports the parent's revised-helper native availability
  diagnostic: 205440/205440 requested sample frames after preroll, 100/100 video
  acknowledgements and zero USB errors. It explicitly states that this used
  installed HAL2 with a continuous explicit tone and proves only data
  availability, not HAL3 presentation compensation or FCP sync. Frame-start
  acknowledgement ticks and USB-deadline relative audio timing are documented.

Changed implementation files are `src/output/OutputHost.mm` and the new
`src/output/AudioRoute.hpp`; the installer builder/scripts/tests were updated
as authorized. No app/extension/HAL binaries, installed files, hardware, live
processes or package outputs were modified by this work. No installer package
was built or installed. Final exact-payload expansion/signature checks belong
to the parent's packaging step.
