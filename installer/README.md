# Shuttle Camera 0.1.39 installer

Host39 / capture extension17 / output extension12 / audio HAL3 / Premiere transmitter1.

Stretch desktop output now follows live desktop resolution changes and fills the selected video frame. Includes the PAL/NTSC display visibility fix. Includes Fit/Fill/Stretch, silent looping idle movies, connector-format choices, and an experimental separate extended desktop. Existing capture resolution retention and live picture controls are included. Camera/output/audio/Premiere driver versions stay unchanged. No reactivation is needed when already enabled.

Stop capture/output and quit camera clients, editors and Shuttle Camera before installing. The installer checks that capture is idle and preserves a backup. It does not change SIP, security settings or firmware. An identical audio driver does not trigger a Core Audio restart.

Desktop mirroring and extended desktop require explicit screen-recording permission. The virtual display uses an undocumented macOS interface and may fail after a system update. See Guide/Whats-New-0.1.39.md in the release, or docs/Whats-New-0.1.39.md in the source, for instructions, screenshots and qualification limits.

Build with installer/build.sh against the staged complete development bundle. The builder verifies exact versions, signatures, expanded payloads and embedded corresponding source. The installer remains unsigned; this is an experimental development build.
