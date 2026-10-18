# 0.1.31 artwork update

Replaces the prior icon with new text-generated SVHS project artwork. The previous icon files are not included in this source tree or package. No playback/driver changes. Still an unsigned development release requiring the documented security setup.

# Shuttle Camera0.1.31 — simpler interface

Removes the diagnostic log and long instructions from the main window. Short labels, grouped controls and a compact capture/output layout retain existing settings and functions. Movie controls appear when Movie file is selected. Help contains Output Setup, Diagnostics and Driver Setup. The app menu contains About and Quit(⌘Q). A full-area opaque VHS icon replaces the padded artwork.

Quit Premiere and Final Cut, then stop output and quit Shuttle Camera before installing. Drivers, USB playback and the Premiere transmitter are unchanged; no reactivation is needed. The previous release's live Premiere playback was confirmed working by the user.

# Shuttle Capture0.1.29 — Premiere output development build

Adds native Mercury Transmit video output for Premiere, with a dedicated Premiere source in Shuttle Camera. Live Premiere qualification is pending. The SDK26 build uses the version1 interface; Premiere25.2.3 is the installed test target. Timeline audio uses the existing Core Audio HDMI device, chosen in Premiere Audio Hardware; the transmitter itself is video only and leaves Premiere's clock in control.

Quit Premiere and Final Cut, disable external output, then stop output and quit Shuttle Camera before installing. No extension reactivation is needed: output12/capture15/HAL3 are unchanged. For Premiere select its source in Shuttle Camera, choose matching format, start output and wait for Ready. Enable Mercury Transmit and select Intensity Shuttle — HDMI Output in Premiere Playback settings. Choose Intensity Shuttle — HDMI Audio in Audio Hardware for sound. Keep Shuttle Camera open; disable Mercury Transmit before Stop output.

# Shuttle Capture 0.1.28 development installer

Quit Final Cut Pro first, then stop output and quit Shuttle Camera before running **Shuttle-Capture-0.1.28.pkg**. Enter your administrator password in macOS when asked. The installer backs up prior bundles. This update contains host28, unchanged camera extension15, HDMI output extension12 and unchanged audio HAL3. An identical HAL3 does not restart Core Audio.

This update adds independent **Title safe (80%)** and **Action safe (90%)** switches in Video Output. White title guides enclose the central80% of picture width and height; yellow action guides enclose the central90%. The guides follow the current PAL, NTSC or HD raster, with dark keylines for visibility. They are saved, apply live and default to off. Guides are drawn beneath the timecode and audio meters so those panels remain readable. They work with Final Cut, movie playback and colour bars, and affect only the outgoing HDMI picture.

The user confirmed0.1.27 working. Output extension12 and capture15 remain byte-identical; audio HAL3, timecode transport, output timing, audio sync, meter settings and the VHS icon are unchanged. No driver reactivation is required for an enabled setup.

The single app retains Capture and Video Output, movie selection, Loop movie and PAL/NTSC choices. Capture input and audio timing are unchanged. Existing settings are preserved. Output modes remain PAL576i50, 1080i50, 1080p25, NTSC480i59.94, 1080i59.94 and 1080p29.97. Capture resolutions include native SD, square pixels,1280×960 and1440×1080; scaling adds no source detail. PAL capture50p is bob deinterlacing of50 fields per second. The Dell HDMI-to-DVI setup needs YPbPr; selectable RGB output is unavailable.

## Final Cut setup

1. Existing 0.1.25 users can leave the enabled drivers as they are. For a first-time setup, click **Enable A/V output driver** and approve Camera Extensions if asked.
2. If you did activate a driver, quit and reopen Shuttle Camera once.
3. Select **Final Cut / CMIO — timeline video + audio** and a matching output format, such as1080p25.
4. Click **Use HDMI audio**, then **Start Final Cut output**. Wait for **Ready for Final Cut — you can now enable A/V Output.** Keep Shuttle Camera open.
5. Open Final Cut Pro. Select **Intensity Shuttle — HDMI Output** in Settings → Playback, then enable Window → A/V Output. Scrub and play the timeline.
6. When finished, turn Final Cut A/V Output off first, then click **Stop output**. **Restore audio** also restores the saved normal Mac media output.

The source is remembered. Colour bars and movie-file playback are separate sources from Final Cut. The device is offered only while a matching sender is ready. Capture and output share the USB interface; close capture windows before output, and stop output before capture.

**Use HDMI audio** changes the Mac media-default output, saving the previous device. Stop, helper exit or app quit restores it only while HDMI remains selected; a later output choice is preserved. Input and alert outputs are unchanged. Turning Final Cut A/V Output off alone does not restore normal Mac sound. **Sound settings…** offers manual selection.

## Scope and development setup

Offline ASan/UBSan tests cover guide geometry, pair alignment, white/yellow separation, legal-range pixels, independent toggle combinations, unchanged pixels outside the guide bands and exact identity when disabled at four raster sizes. Private-suite cross-process live preferences and UI persistence/hit-testing pass. Output and capture layouts were rendered and visually checked. Guide rendering averaged0.128ms per HD frame under sanitizers. Live HDMI guide qualification remains pending.

This is an unsigned installer with ad-hoc signed bundles for the existing Apple silicon/macOS27 SIP-disabled extension-development setup. It changes no security settings or firmware. It installs /Applications/Shuttle Camera.app and /Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver. Complete GPL source, dependencies and licences are installed in /Library/Application Support/Shuttle Camera/Source.zip. Existing bundles are backed up there; newer/unrelated bundles, symlinks and active capture are rejected before writes.

Build with installer/build.sh against the complete development source bundle. Exact host28/camera15/output12/HAL3 payloads and signatures are checked. Offline mocked installer tests never modify the installed system.
