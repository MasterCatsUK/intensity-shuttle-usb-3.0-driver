# Shuttle Video 0.1.48 — Virtual Shuttle

The main application is now **Shuttle Video**. Existing preferences and the internal bundle identity are retained. The installer backs up the old Shuttle Camera app and retires its old name after validating the new payload. Shuttle Player remains separate and unchanged.

## Final Cut on a chosen Mac display

1. In Shuttle Video, open **Output Settings** and choose **Final Cut Pro**.
2. Choose **Virtual Shuttle** as Destination, a Mac display, and a format matching the project cadence. Use **1080p25** for a 25 fps project or **1080p29.97** for a 29.97 fps project. Fit keeps the whole frame; Fill crops; Stretch fills the screen without preserving its aspect.
3. Click **Start Final Cut**. Wait for **Ready for Final Cut**.
4. In Final Cut **Settings → Playback → A/V Output**, select **Virtual Shuttle**. Enable **Window → A/V Output** and play, pause or scrub.
5. Turn A/V Output off before stopping output or changing destination/format in Shuttle Video.

This receives Final Cut's rendered A/V feed, including effects, grading and titles. It is independent of the viewer's position or size and does not capture a desktop. Each new supplied frame is displayed even if its PTS/timecode has not changed, so a newly rendered paused edit is not discarded as a duplicate. Final Cut controls when a render is ready; the app cannot display an edit before Final Cut supplies it.

![Virtual output controls](images48/virtual.png)

*Actual AppKit controls rendered with example devices and inactive output. This illustrates the interface, not a completed live qualification.*

No USB hardware or Screen Recording permission is needed for Virtual Shuttle. A borderless window fills the selected display. Use another display for editing where possible; if using the main display, switch back to Shuttle Video with Command-Tab to Stop. Disconnecting the selected screen stops output cleanly. This is distinct from **Extended display**, which creates a virtual desktop to send through physical Shuttle hardware.

The existing **Intensity Shuttle — HDMI Output** device retains its identity. Choose **Intensity Shuttle** in Destination to use it. Both identities are separate, but only the prepared destination is published and this app runs one output destination at a time. PAL/NTSC and the four existing HD formats are retained; the Mac display renderer runs at the selected video frame cadence. Interlaced modes may show combing on a progressive Mac display; use a progressive output format for normal desktop monitoring.

![Hardware output controls](images48/hardware.png)

## Listen, meters and guides

- **Use Shuttle Audio** selects the **Virtual Shuttle Audio** Core Audio device for Mac media audio. Final Cut links both video devices to this audio UID. It replaces the earlier audio display name but retains the UID.
- Enable **L/R audio meters** and select their position. Audio must actually be routed into Virtual Shuttle Audio; selecting the video device alone does not guarantee a particular editor's audio routing.
- **Listen** sends a copy to the chosen speakers/headphones. The volume slider affects local listening only. Meter levels and physical output PCM are measured before that gain and stay active with Listen off or volume zero.
- The audio receiver cannot be selected as its own listening destination, avoiding feedback. If the chosen speaker disconnects, listening turns off; choose a device and enable it again.
- Enable **Timecode**, **Title safe (80%)** or **Action safe (90%)** as needed. These are output-only monitoring overlays; they do not change captured files, the Final Cut project or exports. Overlay choices are shared by both destinations. They update while output runs.
- **Audio sync** uses separate saved values for Virtual Shuttle and physical output. Negative moves sound earlier, positive later. Listening adds the speaker's own hardware/buffering latency; measure on the actual destination.

Use Shuttle Audio saves the previous system media route. Stop, output failure or Quit restores it if it is still managed by the app; choosing a different route yourself is respected. Merely opening the app does not change the system sound output. Listening defaults off on launch.

## Installation

Stop all recording/output and quit camera apps, Final Cut, Premiere, Shuttle Player and Shuttle Camera/Video. Install **Shuttle-Video-0.1.48.pkg** using the Mac administrator prompt. Open **Shuttle Video** from Applications.

This release updates camera extension to **21**, output extension to **13**, audio HAL to **4** and Premiere plug-in to **2**. Use the app's driver activation commands and approve **Shuttle Camera Extension** and **Shuttle Video Output Extension** in **System Settings → General → Login Items & Extensions → Camera Extensions** when asked (the location/name varies by macOS version). A restart is needed only if macOS requests it or the audio service cannot refresh. The development signing/SIP requirement is unchanged; see the full security guide before installing on another Mac.

Both arm64 and x86_64 binaries are included. macOS **14.4 or later** is required to preserve CMIO stream-latency reporting used by the working output design. Intel and older macOS runtime are **untested**. An architecture-compatible binary is not a hardware qualification.

## Checks and limits

Offline tests cover the two device identities, six discrete output formats, producer/receiver interoperability, same-timestamp pixel refresh, exact per-frame acknowledgements, reconnects, display conversion/aspect/sizing, meter and listening gain separation, recording codecs/fields and installer migration/guards. No installed driver, audio route or security setting is changed by these tests.

A live test with Final Cut must still check effects/colour/title edits while paused and playing, play/pause/scrub responsiveness, selected-display sound/meter activity and the existing physical output. Long sessions, every editor version, HDR and Intel runtime are not qualified. No GitHub upload is performed by building or packaging this release.
