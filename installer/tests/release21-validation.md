# Release 21 installer source review

Prepared 17 October 2026. Intended payload: host 21, camera extension 15,
HDMI output extension 9 and audio HAL 3. Camera and HAL versions are unchanged.
This review updates installer source only. No package was built or installed,
and no live application, audio route, extension or USB device was changed.

## Evidence and scope

Version 0.1.20 passed native A/V tests in all six modes and 12 repeated
readiness/start-stop enumeration cycles. The actual Final Cut test still
failed: scrubbing worked, but pressing Play froze Final Cut. Logs showed a
normal stream stop briefly withdrawing and re-adding the device before a new
start. Those native tests must not be described as successful Final Cut Play.

Output 9 is intended to retain the advertised device during a normal editor
stream stop while the USB sender remains ready, and still withdraw it after an
actual sender disconnect. Version 0.1.21's native and live qualification remain
pending. This review does not establish that the freeze is fixed or that
physical A/V alignment has been measured.

## Installer source changes

- Exact builder guards now require host21/camera15/output9/HAL3 identifiers and
  versions. Receipt and package filename use 0.1.21, leaving existing 0.1.20
  package paths distinct.
- Preinstall permits known host versions through 21 and HAL through 3; future
  host22/HAL4 remain rejected before writes. Postinstall requires host21/HAL3.
  Capture-idle, process, symlink, ownership and backup checks are retained.
- Mock payloads use host21/HAL3. Exact builder checks reject stale host20 and
  output8 as well as changed camera16/HAL2 payloads.
- Upgrade cases cover both host19 and host20 with an identical HAL3, preserving
  prior app backups without restarting Core Audio.
- README, HTML resources and roadmap describe the 0.1.20 failure and 0.1.21
  target without claiming a verified fix. The existing Start Final Cut output /
  Ready for Final Cut workflow, source persistence, all six PAL/NTSC modes,
  movie chooser/loop, explicit HDMI audio route and Stop/Restore behavior remain.
- Existing release19/release20 installer review documents and all earlier live
  result files/packages are retained unchanged as historical evidence.

## Checks run

```
/bin/bash -n build.sh scripts/preinstall scripts/postinstall
python3 tests/installer_test.py
```

Both passed. All 18 mock tests ran against temporary files and fake system
commands. Real payload build/signature/expansion checks and installed output-9
client-stop stability tests remain for the owning agent. No installer build or
live action was performed by this source review.
