# Shuttle Camera 0.1.42 — direct recording and live Capture panel

The tabs are now **Capture**, **Input Setting**, **Output Setting**, and **Idle Settings**.

![Capture controls and preview area](images42/capture.png)

## Record a tape

1. In **Input Setting**, select PAL or NTSC, the video/audio input, resolution, source aspect and (for interlaced modes) field order. Close other camera previews and click **Apply**. Returning to this tab closes the app's own preview automatically.
2. Open **Capture**. The live preview fits the whole image and honours the input's pixel aspect. Adjust Brightness, Contrast, Colour and Sharpness beneath the picture. Keep **Live adjustments** checked for immediate changes; Reset picture restores neutral controls.
3. Click **Record…**, choose a new `.mov` filename, and play the tape. The recorder uses the applied camera format and the Shuttle's stereo audio input, independent of the Mac's selected microphone or speakers.
4. Click **Stop** and wait for **Saved** before using the movie. Quitting the app requests a clean recording stop and waits for finalization. Moving to another tab closes the preview but keeps an active recording running; return to Capture to stop it.

![Input format settings](images42/input.png)

Recordings use **Apple ProRes 422** with **48 kHz stereo float PCM**. Files can be large. Software ProRes encoding is selected deliberately because the default encoder rejected the interlaced settings in our test. Native SD is the preferred preservation starting point; HD upscale settings add no original tape detail and require more processing/storage. This is ProRes, not DV encoding.

For interlaced recordings choose **576i50**, **480i59.94**, **1080i50** or **1080i59.94** in Input Setting. PAL interlace has 25 frames / 50 fields per second; NTSC has approximately 29.97 frames / 59.94 fields. The direct recorder preserves both fields, their order, the selected pixel aspect and the camera timestamps. Progressive choices stay progressive. A modern player may deinterlace during display, so a smooth-looking preview alone cannot establish whether the saved fields were retained. In VLC choose Video > Deinterlace > Off to inspect combing on motion.

The new preview receives CMIO frames directly; it is not a QuickTime camera-effects preview. It refreshes at up to 30 fps for monitoring; the recording keeps the camera's full sample cadence. Preview resizing is only for display. Applied picture adjustments do affect the recording.

## Installation

Stop capture/output and quit camera apps, editors and Shuttle Camera, then install **Shuttle-Capture-0.1.42.pkg**. Host42 adds the recorder and preview; **camera19 / output12 / HAL3 / Premiere1 are unchanged**, so updating from an already enabled 0.1.41 setup needs no driver reactivation. A fresh install still needs the documented development security setup and driver approvals. No new security changes are introduced by this update. It remains an unsigned development installer.

## Validation and limits

Actual encode/decode tests cover 16 combinations: PAL/NTSC, native/HD, top/bottom field order, and progressive/interlaced. Checks verify saved field metadata, distinct alternating rows, frame duration, stereo PCM and recording duration. Error tests cover existing filenames, format changes, backwards video timing and audio-buffer overflow. A preview fixture checks whole-frame display and 4:3 / 16:9 pixel aspect. Native UI and installer checks also pass.

A short live PAL recording saved two fields per frame with the correct aspect metadata. That sample's audio was silent, so physical sound and A/V synchronization still need a tape test after installation. Long recordings and real-time HD software-encoding performance also need qualification. On an error the app reports the problem and attempts to finish the partial file; inspect that file before using it. There is no guarantee a file can be recovered after power loss or force quit.

No recording of personal tape footage or private QA files is included in the release.
