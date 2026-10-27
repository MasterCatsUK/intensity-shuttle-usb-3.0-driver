# 0.3.2 — 27 October 2026

Streaming scrub bar and ten-second skip controls. Release the slider to jump forward/backward online; preserve paused/playing state. Decoder restart and cleanup happen asynchronously while USB sends held picture/silence. Coalesce repeated requests to the latest target. Generation-aware preview acknowledgement prevents the playhead jumping back to old frames. Replay at EOF; empty end seeks finish cleanly. Retains the0.3.1 bounded YouTube transport fix, three-second buffer and separate Download first option. Stream Loop remains disabled. No driver or security changes.

# 0.3.1 — 27 October 2026

Fix repeated YouTube streaming buffer starvation on long videos. Use bounded 1 MiB HTTP range requests and persistent connections for Google video delivery; update the bundled LGPL FFmpeg build to 8.1.3 for native bounded-request support. Three-second paired buffer and memory limits retained. More detailed video/audio buffer diagnostics. Download first, other sites, USB scheduling and drivers unchanged. Sustained real-time test added using the reported long video.

# 0.3.0 — 27 October 2026

File → Open Video URL now offers Download first (default) or Stream. Stream resolves public on-demand links, decodes picture/stereo sound in a supervised FFmpeg process and starts with about three seconds buffered. Bounded RAM queues, picture hold/silence on starvation, refill progress, pause, Stop and volume. Stream disables seek/skip/Loop; Download first retains them. Source up to 1080; PAL/NTSC/1080 output and Stretch/Fit/Fill retained. HTTP(S)/HLS support added to the bundled LGPL FFmpeg build with native TLS verification. No camera/audio driver, editor plug-in or security changes. Actual live broadcasts remain unsupported. New streaming HDMI check pending; Intel untested.

# 0.2.1 — 27 October 2026

Native loading progress bar: percentage for each video/audio download, animation during lookup/merge/cancellation, hidden when idle or finished. URL dialog opens only from File → Open Video URL; verified normal launch without a sheet. Playback engine unchanged.

# 0.2.0 — 27 October2026

File → Open Video URL (Shift–Command–O) for YouTube, Dailymotion, Vimeo. Background private-cache preparation with progress/Cancel, then existing HDMI picture/stereo playback, controls, scrubbing and Stretch. Pinned bundled helpers, per-job subprocess supervision/cancellation, error messages and cleanup. No capture/audio driver changes. User HDMI URL check pending; Intel untested.

# Shuttle Player changes

## 0.1.1 — 19 October 2026

- Smooth local preview at the output frame rate, replacing the original roughly five-fps preview.
- Bounded preview buffering and common-mode UI refresh keep motion steady during normal playback and scrubbing.
- Centred native playback icons, with Play/Pause in the middle and a blue Loop indicator. Volume sits at the right.
- Quieter background diagnostics; TV output protocol, audio and scheduling remain unchanged.
- User confirmed both app preview and TV picture/sound are good on the development Mac Studio.

## 0.1.0 — 19 October 2026

Initial separate Player: movie chooser, Play/Pause/Stop, scrub bar, ten-second skip controls, looping, volume, Stretch default, format/connection choices and clean handover from Shuttle Camera. Starts with Camera's saved output format, with no inherited overlays. Universal binary; Intel hardware remains untested.
