# Shuttle Camera 0.1.37 — clearer audio wording

The Video Output button is now **Use Shuttle Audio**. Its tooltip, desktop/Final Cut instructions and diagnostic messages use the same wording. Sound routing and automatic restoration remain unchanged. The Core Audio device still has its existing name, **Intensity Shuttle — HDMI Audio**, so saved editor/device selections remain compatible.

macOS Displays shows **Shuttle Extended Display** for the separate virtual desktop. HDMI, composite and S-Video are physical outputs of that one stream, rather than separate macOS display devices. Choose the desired connector and compatible format in Shuttle Camera. Multiple compatible connectors may carry the picture simultaneously.

On0.1.36, the user confirmed PAL composite playback with stable colour bars and a moving white block. The60-second test completed with zero transfer/packet errors and restored the input alternate successfully. Composite/S-Video output during capture were also confirmed. Those observations do not newly qualify NTSC analogue, component or every playback mode.

Host37 only; camera17/output12/HAL3/Premiere1 unchanged. Stop capture/output and quit camera apps, editors and Shuttle Camera before installation. No driver reactivation is needed when already enabled. Screen-recording permission may need refreshing after ad-hoc app updates: quit the app, remove its old entry from Screen & System Audio Recording, add /Applications/Shuttle Camera.app again, enable it and reopen. A computer restart is normally unnecessary. Do not modify the privacy database.

Use Whats-New-0.1.36.md for sizing, idle movies and extended-desktop instructions. Earlier screenshots show the previous audio-button caption.
