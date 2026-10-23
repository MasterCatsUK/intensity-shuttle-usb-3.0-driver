# Shuttle Player changes

## 0.1.1 — 19 October 2026

- Smooth local preview at the output frame rate, replacing the original roughly five-fps preview.
- Bounded preview buffering and common-mode UI refresh keep motion steady during normal playback and scrubbing.
- Centred native playback icons, with Play/Pause in the middle and a blue Loop indicator. Volume sits at the right.
- Quieter background diagnostics; TV output protocol, audio and scheduling remain unchanged.
- User confirmed both app preview and TV picture/sound are good on the development Mac Studio.

## 0.1.0 — 19 October 2026

Initial separate Player: movie chooser, Play/Pause/Stop, scrub bar, ten-second skip controls, looping, volume, Stretch default, format/connection choices and clean handover from Shuttle Camera. Starts with Camera's saved output format, with no inherited overlays. Universal binary; Intel hardware remains untested.
