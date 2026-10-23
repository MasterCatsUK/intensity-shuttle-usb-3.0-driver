# Shuttle Camera 0.1.45 — return from the recovery test

Restores the complete feature build from 0.1.43 after the diagnostic 0.1.39 recovery build44. The app code and loadable executable sections are unchanged from0.1.43; only release packaging/version/signatures differ. A newer host build number lets the standard installer replace recovery44 without weakening version checks.

The user identified a malfunctioning TBC and reported that video returned. The installed camera19 driver remained active throughout the recovery-app test and now reports PAL. This update keeps camera19, output12, HAL3 and Premiere1 unchanged. No driver reactivation is needed while those versions are already enabled. The recovery camera20 was not active in this case.

Capture / Input Setting / Output Setting / Idle Settings return, including the live preview, picture controls and direct ProRes422 + stereo MOV recorder. Click Show input to preview; allow Camera access if macOS asks. Record requests Microphone access. Interlaced presets preserve both fields; progressive presets remain progressive. Opening the app alone does not start USB capture. See [the feature guide](Whats-New-0.1.42.md) and [permission/startup repair](Whats-New-0.1.43.md).

Stop recording/output and quit camera/editor apps and Shuttle Camera before installing Shuttle-Capture-0.1.45.pkg. Afterward verify PAL/S-Video, the selected aspect/resolution and a short recorded sample with sound. Physical A/V sync and long HD throughput still need qualification.

This is a return to the existing feature set, not a new capture-processing change. The existing development signing/security requirements remain. Installer mock, exact payload/source/signature and unchanged-code comparisons are checked before delivery. No private tape footage is included.
