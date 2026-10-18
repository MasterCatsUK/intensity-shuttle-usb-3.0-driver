# Shuttle Camera 0.1.38 — PAL/NTSC extended display visibility

The PAL/NTSC virtual desktops in0.1.36/37 were768×576 and648×486. On this Mac they existed and could be captured, but macOS Displays omitted them. The same settings page listed the1080 desktop correctly. This was reproduced with the installed app; selecting Extended display, rather than Test pattern, did not resolve it.

PAL and NTSC extended output now use a **1024×768 (4:3) virtual desktop**. ScreenCaptureKit scales that desktop into the selected video format:

| Choice in Shuttle Camera | macOS desktop | Shuttle wire output |
|---|---|---|
| PAL |1024×768,4:3 |720×576,576i50 |
| NTSC |1024×768,4:3 |720×486,480i59.94 |
| Supported1080 modes |1920×1080,16:9 |Selected1080 format |

The desktop sender also disables ScreenCaptureKit’s additional square-pixel aspect correction: our Fit/Fill/Stretch geometry already accounts for PAL/NTSC pixel proportions. Otherwise SD can gain unwanted borders.

The larger desktop is for macOS usability/visibility. It does not turn composite or S-Video into an HD output. PAL/NTSC pixel proportions are preserved when scaling. The virtual desktop runs at60Hz; the USB output keeps its selected25/29.97 frame cadence and interlaced wire format. Select the desired video standard in Shuttle Camera, not by changing macOS refresh rate.

## Use it

1. Stop output, choose **Extended display** as Source.
2. Choose HDMI, S-Video or Composite and PAL or NTSC, then click **Start extended display**.
3. In **System Settings → Displays**, select **Shuttle Extended Display**. It should now appear as1024×768. Arrange it as needed and drag windows onto it.
4. Choose **Use Shuttle Audio** if sound should follow the Shuttle. Stop removes the virtual screen and restores the saved audio route.

Test pattern and Movie file send pictures directly and do not create a macOS screen. Mac desktop mirrors an existing screen. The extended screen exists only while extended output is running. Compatible physical outputs can carry the same stream simultaneously.

## Validation and installation

Reproduced the old NTSC648×486 screen being absent from Displays despite CoreGraphics reporting it active and desktop output starting. With the new shared desktop-size policy, live PAL and NTSC probes both created a1024×768 desktop, captured a red test window into their exact SD rasters and verified removal on Stop. The System Settings accessibility view listed Shuttle Extended Display during both probes; NTSC was selected and showed1024×768 (Default). These probes did not open USB or change audio routing. The existing PAL composite bars test remains qualified; this is not a new physical-TV timing qualification.

Geometry regression checks all six mode choices and verifies the selected virtual desktop scales into each output without unintended borders. Native build, existing offline UI checks and installer payload checks run before packaging. Host38 changes desktop-size selection and the desktop sender’s aspect handling. The display helper gives SD and HD separate stable identities, so macOS does not restore a saved4:3 mode onto the1080 desktop. Live fullscreen-red probes also check the centre and left/top/bottom edges in the PAL/NTSC output, preventing the previous extra borders. The USB packet/clock implementation and camera17/output12/HAL3/Premiere1 remain unchanged.

Stop capture/output and quit camera apps, editors and Shuttle Camera before installing0.1.38. No driver reactivation is needed if already enabled. Existing experimental signing/security requirements and private virtual-display API caveats remain unchanged. After an ad-hoc app update, screen-recording permission may need refreshing by removing the old app entry and re-adding /Applications/Shuttle Camera.app; a full computer restart is normally unnecessary.

Use Whats-New-0.1.36.md for sizing/idle movie instructions, with the desktop dimensions in this document replacing its earlier SD values. Use Whats-New-0.1.37.md for the Use Shuttle Audio wording.
