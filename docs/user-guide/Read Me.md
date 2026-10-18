# Shuttle Camera 0.1.31 — Read Me

Installation & user guide · 18 October 2026

## Read this first

**Shuttle Camera 0.1.31** · Installation and user guide · 18 October 2026

Capture VHS and other standard-definition sources, play movie files through HDMI, or monitor Final Cut Pro and Premiere Pro through the USB 3 Intensity Shuttle.

> **Development build — security changes required.** The installer is unsigned; its app and extensions are ad-hoc signed and not Apple-notarized. This build requires SIP to be disabled. Apple describes disabling these checks as a temporary development measure, not a normal public-release setup. Read page 2 before deciding whether to install. [Apple: testing system extensions](https://developer.apple.com/documentation/driverkit/debugging-and-testing-system-extensions).

### What you need

- An Apple-silicon Mac. This installer requires macOS 27 or later; testing was on a Mac Studio with macOS 27.0.1. Other machines and later macOS releases are not guaranteed.
- A Blackmagic Intensity Shuttle **USB 3**, a working USB 3 cable/adapter, and administrator access. The Thunderbolt Shuttle and Intel Macs are not supported by this installer.
- For VHS: a working VCR, S-Video or composite video, and red/white RCA audio cables. For output: a TV or monitor connected to the Shuttle’s HDMI OUT.
- A current backup and permission to change security settings. Do not change security on a managed/work Mac without its administrator’s approval.

### How it works

Shuttle Camera configures the device. Record into a separate camera app such as QuickTime Player. For movie or editor HDMI output, leave Shuttle Camera open with output started. Capture and playback share the USB interface: use one at a time.

### Guide map

| Page | Topic |
| --- | --- |
| 2 | Security preparation |
| 3 | Install and enable the extensions |
| 4 | Capture VHS |
| 5 | HDMI movie playback and formats |
| 6 | Final Cut Pro and Premiere Pro |
| 7 | Sound, sync and overlays |
| 8 | Troubleshooting and limitations |
| 9 | Removal, security restoration and files |

Screenshots show the real 0.1.31 interface with example settings. Your selected input, output device and positions may differ. This guide is independent of Blackmagic Design, Apple and Adobe; it is not their official driver documentation.

## Security preparation

**Make this decision before installing.** SIP protects parts of macOS against unauthorized changes. Turning it off weakens protection across the Mac, not just this app. Developer mode relaxes extension validation. Neither setting makes downloaded software trustworthy. [Apple: disabling and enabling SIP](https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection); [Apple: testing system extensions](https://developer.apple.com/documentation/driverkit/debugging-and-testing-system-extensions).

### 1. Turn off SIP in Recovery — Apple silicon only

1. Save your work and shut down the Mac. Press and hold its power button until startup options appear. Choose **Options → Continue**; select an administrator and authenticate if asked.
2. In Recovery, choose **Utilities → Terminal**. Enter the command below. Follow the displayed prompts for the intended startup system, then restart normally.

```sh
csrutil disable
```

These are Recovery instructions; running the command in an ordinary desktop Terminal will not complete the change. [Apple: Recovery on Apple silicon](https://support.apple.com/guide/mac-help/mchl82829c17/mac).

### 2. Check the status in normal macOS

```sh
csrutil status
```

The installer checks for **System Integrity Protection status: disabled.** Do not use partial-disable flags as a substitute: this installer has not been qualified with them.

### 3. Enable extension developer mode

In normal macOS, open Terminal and run:

```sh
sudo systemextensionsctl developer on
```

Enter your Mac administrator password; Terminal does not show password characters. This is the development configuration used during testing. It is separate from SIP. [Apple: testing system extensions](https://developer.apple.com/documentation/driverkit/debugging-and-testing-system-extensions).

### What is not required

These are camera system extensions and a Core Audio plug-in, not a kernel extension. This guide does not ask you to enable third-party kernel extensions, disable FileVault, disable authenticated-root protection or globally disable Gatekeeper. Follow the specific SIP procedure rather than unrelated kext instructions.

> **Can SIP be turned on immediately afterwards?** Do not assume this build will continue working with SIP enabled. That configuration has not been qualified, and its installer refuses installation/updates while SIP is enabled. Restore SIP when you finish testing or remove this build; page 9 explains how.

## Install and enable

### Install the package

1. Disable external output in Premiere/Final Cut and quit those editors. Stop output and quit Shuttle Camera. Close QuickTime recording windows and other camera previews.
2. Open **Shuttle-Capture-0.1.31.pkg**. Install on the current macOS startup volume and enter your administrator password when macOS asks.
3. If Gatekeeper blocks the package, first verify that it came from a source you trust. Where macOS offers it, use **System Settings → Privacy & Security → Open Anyway** for this specific package. Do not turn off Gatekeeper globally. [Apple: opening apps safely](https://support.apple.com/en-gb/102445).
4. Let installation finish. Open **Shuttle Camera** from Applications. The installer preserves existing settings and backs up older Shuttle bundles.

### Verify a downloaded copy

In Terminal, type the following and drag the downloaded package into the window after the final space, then press Return:

```sh
shasum -a 256 
```

Compare the result with the SHA256SUMS.txt supplied with this exact release:

```sh
shasum -a 256 /path/to/Shuttle-Capture-0.1.31.pkg
```

Compare all 64 checksum characters. A matching hash detects a different file; it does not replace trusting the publisher or Apple notarization.

### First installation: enable both camera extensions

1. In Shuttle Camera, choose **Help → Driver Setup → Enable Camera**.
2. Choose **Help → Driver Setup → Enable HDMI Output** if you want editor HDMI output.
3. If macOS asks for approval, open **System Settings → General → Login Items & Extensions → Camera Extensions**. Enable **Shuttle Camera Extension** and **Shuttle HDMI Output Extension**.
4. Quit and reopen Shuttle Camera after activation. Restart if macOS says a restart is required. Approve camera/microphone access for the recording app when requested.

An existing installation with both extensions already enabled does not need reactivation for the 0.1.31 interface update. First-time installation may refresh Core Audio and briefly interrupt sound; restart if the audio devices are missing.

## Capture VHS

![Capture panel. This example uses PAL composite video and 768 × 576 square-pixel output; select S-Video when using that cable.](images/capture.png)

1. Connect VCR video OUT to the matching Shuttle input. Connect red/white audio OUT to the Shuttle’s analog RCA inputs. Connect the Shuttle to USB 3 and press Play on the VCR.
2. Choose **PAL** or **NTSC**, the correct **Video input**, and **Analog RCA**. Choose a resolution and video-loss behavior, then click **Apply**. Close capture previews before changing settings.
3. In QuickTime Player, choose **File → New Movie Recording**. Select the Intensity Shuttle camera and **Intensity Shuttle — Stereo Audio** as the microphone. Check both picture and audio meter before recording.

PAL: native 720 × 576 or square-pixel 768 × 576. NTSC: native 720 × 480 or square-pixel 640 × 480. Both also offer 1280 × 960 and 1440 × 1080 (4:3). Larger sizes are scaled, with no extra tape detail. PAL 50 fps / NTSC 59.94 fps capture uses bob deinterlacing of the source fields.

**On video loss:** Hold last frame repeats the last picture; Black substitutes black. Dropout handling preserves the timing rather than shortening the recording, but it cannot recover a damaged tape signal. Check a short recorded clip for sound and sync before a long transfer.

## Play a movie over HDMI

![Movie file controls with illustrative settings. Example movie.mov is a placeholder; no movie was opened or played to make this screenshot.](images/movie.png)

1. Connect the display directly to the Shuttle’s **HDMI OUT**. Close all Shuttle camera previews.
2. Choose **Video Output → Source → Movie file**, then **Choose movie…**. Select the HDMI format.
3. Enable **Loop** to repeat the movie. Click **Start output**; use **Stop** when finished. Movie audio travels through the Shuttle; Use HDMI audio is not needed for the movie file’s own sound.

| HDMI format | Picture format / cadence |
| --- | --- |
| PAL · 576i50 | 720 × 576; 50 fields/s |
| NTSC · 480i59.94 | 720 × 486 output raster; 59.94 fields/s |
| 1080i50 / 1080i59.94 | 1920 × 1080; 50 / 59.94 fields/s |
| 1080p25 / 1080p29.97 | 1920 × 1080; 25 / 29.97 frames/s |

A TV may round 59.94 to “60” and 29.97 to “30”. Use Test pattern for a short display/cable test. Capture resolution and HDMI output format are separate settings. Capture cannot run at the same time as USB playback.

## Final Cut Pro and Premiere Pro

### Final Cut Pro — tested with 11.2

1. Close Shuttle capture previews. In Shuttle Camera → Video Output choose **Final Cut Pro** and a format matching the timeline, for example **1080p25** for 25 fps.
2. Click **Use HDMI audio**, then **Start Final Cut**. Wait for **Ready for Final Cut**. Keep Shuttle Camera open.
3. In Final Cut, choose **Settings → Playback → A/V Output → Intensity Shuttle — HDMI Output**. Enable **Window → A/V Output**, then scrub and play.
4. When finished, turn **Window → A/V Output** off first; then click Stop in Shuttle Camera. Restore audio if needed. Turning A/V Output off alone does not restore the Mac’s normal sound route.

### Premiere Pro — tested with 25.2.3 (2025)

1. In Shuttle Camera → Video Output choose **Premiere Pro** and the matching HDMI format. Click **Start Premiere** and wait for **Ready for Premiere**.
2. In Premiere, choose **Settings/Preferences → Playback**. Enable **Mercury Transmit** and tick the video stream for **Intensity Shuttle — HDMI Output**. This is separate from the original Blackmagic Playback entry.
3. For sound, choose **Intensity Shuttle — HDMI Audio** in Premiere’s **Audio Hardware → Default Output**. The Mercury Transmit plug-in is video-only; its empty Transmit audio-stream column is expected.
4. Play or scrub the sequence. Leave Shuttle Camera running. If output disappears when Premiere is in the background, check Premiere’s Disable video output when in the background setting.
5. Disable Mercury Transmit before stopping output. If you explicitly selected the HDMI audio device in Premiere, select your normal output in Premiere Audio Hardware afterwards.

### If the output device is missing

Restart Premiere after installing its plug-in. Final Cut publishes the device after the matching USB sender is ready. Start with matching timeline/output rates; conversion between arbitrary frame rates has not been qualified. The current installer places Premiere’s transmitter in the legacy **Plug-ins** folder used by the tested Premiere 2025 installation, not the differently named Plugins folder.

Close one editor’s external output before using another. The same physical Shuttle cannot serve two simultaneous playback sessions.

## Sound, sync and overlays

### Choose the right audio device

| Task | Audio selection |
| --- | --- |
| VHS recording | Intensity Shuttle — Stereo Audio as the recording app’s microphone |
| Final Cut HDMI monitoring | Use HDMI audio in Shuttle Camera before starting editor output |
| Premiere HDMI monitoring | Intensity Shuttle — HDMI Audio in Premiere Audio Hardware |
| Movie file output | Sound comes from the selected movie file |

**Use HDMI audio** changes the Mac’s default media output and saves its previous choice. Stop, helper exit or app quit restores that choice only if the route is still Shuttle HDMI. A later manual change is respected. This does not restore an explicit per-application output selected inside Premiere; change that in Premiere itself.

### Adjust audio sync

Use **Audio sync** in Video Output while timeline monitoring. Negative values move sound earlier; positive values delay it. Range: −100 to +500 ms. If sound is slightly late, try −20 ms, press Return, and compare again. Wait about a second between adjustments. The stepper changes by 10 ms; Reset returns to zero. A live adjustment can briefly click or skip. This setting is for timeline HDMI sound, not capture recording.

### HDMI overlays

- **Timecode:** TC HH:MM:SS:FF from the editor, with a DF marker for drop-frame. Dashes mean valid timecode was not supplied. It is not an invented elapsed counter.
- **L/R audio meters:** independent stereo levels with peak hold and clip indication. The meters show sound sent to HDMI.
- **Positions:** top left, top right, bottom left, bottom right, top centre or bottom centre. Timecode and meters have separate positions.
- **Title safe (80%) / Action safe (90%):** optional white/yellow guides. These are the app’s guide percentages, not a guarantee of compliance with a broadcaster’s delivery specification.

Overlays affect the outgoing HDMI picture only; they do not burn into the source file or editor project. Settings are saved and update live. Timecode is available for editor output; meters and safe guides also work with movie playback.

### Menus

**Shuttle Camera → About** shows the version; **Quit (⌘Q)** closes the app. **Help → Output Setup** gives source-specific instructions. **Help → Diagnostics** opens the technical log. **Help → Driver Setup** contains the extension enable/disable actions.

## Troubleshooting and limits

| Problem | What to check |
| --- | --- |
| Installer fails | Quit both editors and Shuttle Camera, close capture previews, check SIP status, and use the current startup volume. Installer → Window → Installer Log shows the precise reason. |
| Camera missing | Use Help → Driver Setup → Enable Camera. Approve Camera Extensions in System Settings, then reopen Shuttle Camera and the recording app. |
| No capture sound | Use the separate Stereo Audio microphone, Analog RCA for VCR red/white cables, and check app microphone permission. |
| Ready never appears | Close capture previews, check USB 3 cable/adapter and power, reconnect the Shuttle after stopping clients, then retry. Read Help → Diagnostics. |
| Premiere device missing | Restart Premiere; confirm the Shuttle transmitter exists in the Plug-ins path on page 9. Do not select Blackmagic Playback as a substitute for this plug-in. |
| Picture, no HDMI sound | Check Premiere Audio Hardware or Final Cut’s Use HDMI audio route. TV speakers must be enabled; HDMI-to-DVI connections do not provide TV audio. |
| Purple blacks / wrong colours | On the tested Dell P2213t with HDMI-to-DVI, set its Input Color Format to YPbPr. RGB selection in this app is not implemented. Direct HDMI to the tested TV worked. |
| Mac sound missing afterwards | Click Restore audio or choose normal speakers in Sound settings. Also undo any explicit HDMI output selection inside Premiere. |
| Editor freezes / viewer stops | Disable external output, then stop Shuttle output. Relaunch only after saving work. Report the format, editor version and Diagnostics log; do not keep toggling output during a hung session. |

### Current limitations

This build is Apple silicon only. Capture is standard-definition; S-Video/composite VHS capture is the main tested workflow. Listed Component/HDMI capture options do not imply HD capture support. There is no DaVinci Resolve output integration, selectable RGB HDMI mode, simultaneous capture/playback or qualified 1080p50/60 output.

Testing covered the listed PAL/NTSC/1080 modes on one Mac Studio setup. It is not proof of compatibility with every USB controller, display, movie codec, editor update or tape. Very long sessions, exact measured physical A/V latency and fresh installs on other Macs have not been comprehensively qualified.

For a useful report, include the app/macOS/editor versions, source and HDMI format, connection type, whether the camera is in use, and relevant Diagnostics/Installer Log lines. Review logs for private file names before sharing them.

## Remove it and restore security

### Remove the development components

1. Save your work. Disable editor external output, quit the editors, stop Shuttle output and restore normal audio. Close recording/camera previews.
2. In Shuttle Camera, use **Help → Driver Setup → Disable Camera**. In System Settings → Camera Extensions, turn off both Shuttle extensions.
3. Move **Shuttle Camera.app** from Applications to the Bin using Finder. Allow macOS to remove its bundled extensions if prompted. Do not manually delete files from /Library/SystemExtensions.
4. In Finder → Go → Go to Folder, visit the HAL path below and move only **Shuttle Audio.driver** to the Bin. Visit the Premiere path and move only **Shuttle Transmit.bundle** to the Bin. Administrator approval may be required.
5. Restart to unload audio and finish any pending extension removal. Check that other audio devices work normally. Do not use systemextensionsctl reset; it would affect unrelated extensions.

### Turn extension developer mode off in normal macOS

```sh
sudo systemextensionsctl developer off
```

### Turn SIP back on in Recovery

Boot to Recovery as on page 2, choose Utilities → Terminal, run the command below, then restart normally. Verify with csrutil status in the desktop Terminal. If you separately changed Startup Security policies, consult Apple’s Recovery guidance to restore the appropriate policy for your startup system. [Apple: disabling and enabling SIP](https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection).

```sh
csrutil enable
```

The ad-hoc development extensions may stop working after restoring SIP; do not treat this as a supported way to keep using this build. Retain backups until you have checked your files and normal audio. Accessing installer backups may require administrator rights.

### Installed files and source

- App: `/Applications/Shuttle Camera.app`
- Audio: `/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver`
- Premiere: `/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle`
- Source archive, licences, installation status and backups: `/Library/Application Support/Shuttle Camera/`

Project source includes GPL/LGPL components; consult COPYING and component licences in Source.zip. Adobe’s SDK must be obtained separately for rebuilding the Premiere adapter. The new original SVHS project artwork was generated from a text-only prompt without the previous icon as an input; it is included under the project GPL-2.0-or-later terms. See ICON-NOTE.md in the source resources.
