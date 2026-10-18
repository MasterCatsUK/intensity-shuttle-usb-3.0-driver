# Release 20 installer source review

Prepared 17 October 2026. Intended payload: host 20, camera extension 15,
HDMI output extension 8 and audio HAL 3. Camera and HAL versions are unchanged.
This review updates installer source only; it does not build or install a
package and does not validate Final Cut or device behavior.

## Source changes

- Builder pins exact bundle identifiers and versions: host20/camera15/output8/HAL3.
  Package filename and receipt version are 0.1.20. Existing 0.1.19 package names
  are distinct and are not replaced by this update.
- Preinstall accepts known existing host versions through 20 and HAL versions
  through 3; future host21/HAL4 and unrelated bundles remain rejected before
  writes. Postinstall requires host20/HAL3. Capture-idle, process, symlink,
  ownership and backup checks remain in place.
- Mock payload uses host20/HAL3. Exact builder guards reject host19, output7,
  camera16 and HAL2. A new upgrade scenario starts from host19/HAL3, verifies the
  old app backup is preserved and confirms an identical HAL avoids a Core Audio
  restart.
- README, HTML installer resources, postinstall status and roadmap describe
  source persistence, sender-first Final Cut startup and ready-mode-only output
  availability, using the Start Final Cut output button and exact ready-status
  text. They retain movie selection and Loop movie, PAL/NTSC options,
  explicit HDMI media-audio routing and Stop/Restore behavior.
- Prior verified 0.1.19 playback is distinguished from this update's pending
  native/live validation. No claim is made that 0.1.20 fixes the freeze or that
  physical flash/beep alignment has been measured.
- `release19-validation.md` is retained unchanged as a historical review.

## Checks run

```
/bin/bash -n build.sh scripts/preinstall scripts/postinstall
python3 tests/installer_test.py
```

Both passed. The mock suite ran 17 tests, including the host19-to-host20 upgrade
with unchanged HAL. All script tests use a temporary filesystem and fake system
commands; no installed app, driver, preference, USB device or live audio route
was changed.

The actual host20/output8 binaries, source package staging, archive expansion,
signatures, real installer and live Final Cut workflow remain the owning
agent's next checks. No package was produced by this review.
