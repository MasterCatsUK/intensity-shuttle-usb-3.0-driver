# Release 0.1.22 completion-notification correction

Host22/output10/camera15/HAL3 preserves every scheduled-output completion in arrival order rather than retaining only the latest acknowledgement. A burst regression reproduces three received completions becoming one notification on output9; the new queue delivers all three, with reset isolation. ASan/UBSan transport, readiness, reconnect and publication tests pass. Native and live Final Cut qualification of this correction are pending.

Release21 fixed device disappearance across normal CMIO stop/restart and passed five cached-device/queue cycles with135 callbacks. The user later reported intermittent internal-viewer stalls while HDMI kept playing, so the full Final Cut workflow remains unqualified. The new completion-loss fix may be related, but no causal claim is made before live tests.

After activating an updated HDMI extension, quit/reopen Shuttle Camera once, start Final Cut output and wait for Ready, then enable Final Cut A/V Output. Turn A/V Output off before stopping the sender. Movie selection, looping, PAL/NTSC choices, capture settings and explicit audio restoration remain.

Remaining: confirm sustained local-viewer and HDMI playback together; check long sessions and seeks; measure physical A/V alignment; qualify additional codecs and prepared Macs.
