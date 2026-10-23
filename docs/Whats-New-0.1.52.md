# Shuttle Video 0.1.52 — fullscreen Virtual Shuttle

The Virtual Shuttle monitor now covers the **entire selected Mac display**, including the menu-bar and Dock area. A dedicated borderless monitor window sits above those interface elements and retains the exact display frame, including on screens arranged above or to the left of the main display.

Final Cut keeps keyboard focus when output starts. This update does not change global menu-bar/Dock preferences, rearrange displays or move the editor into another fullscreen Space. The editing screen keeps its own normal interface.

## Stop the monitor

- Click **Stop** in Shuttle Video.
- Or click the output picture and press **Escape**.
- Or right-click the output picture and choose **Stop Virtual Shuttle**.

Clicking the monitor lets it receive Escape. Click Final Cut again to use its keyboard controls. In **Virtual + Shuttle** mode, stopping the Mac monitor stops the paired hardware sender too and restores the saved Mac audio route as usual. This also gives an exit when the selected output is the only display.

The higher-detail native RGB scopes and automatic overlay suppression from 0.1.51 are retained. No changes were made to audio sync, USB timing, Final Cut clock/credits, local audio buffering or scope processing. The user reported that both outputs' sync was correct again on 0.1.51 before this update was installed; the cause of the temporary mismatch was not established.

## Installation

Turn off editor A/V Output, stop capture/recording/output and quit editor/camera/Shuttle apps before installing. Camera21, output13, audio4 and Premiere2 stay unchanged; an already enabled output13 needs no reactivation. Start output in Shuttle Video, wait for Ready, then enable the selected Final Cut A/V device as before.

Offline checks cover exact full-display geometry, window ordering above the menu bar, no initial focus/visibility or global presentation change, native RGB frame ownership, all six video modes and metering with listening disabled. Universal bundles and installer payload checks are also verified. Live fullscreen/menu coverage and Escape/context-menu stop still require testing after installation. Intel runtime remains untested. Development signing/security requirements are unchanged.
