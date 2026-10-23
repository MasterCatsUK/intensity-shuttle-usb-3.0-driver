# 0.1.53 validation

23 October 2026. Explicit Mac screen / Shuttle output modes replace Controls for / View. Both editors support all nine Video / Video scopes / Off combinations. Scope-type controls and video overlay settings are independent. Existing destination/view settings migrate once. Off changes are blocked while a sender is running; Video/Scopes stays live. Both Off disables Start.

Premiere Mac-only now receives Transmit port47540 directly; paired uses the same clean shared frame fan-out as FCP. No duplicate audio receiver is created by the paired tap. Ready waits for the output/window. Final Cut A/V identity follows Mac-enabled vs hardware-only. Scope renderers, USB pacing, FCP clock/credits and audio processing are unchanged.

Offline combined UI regression: zero failures, all18 editor routing combinations, scope styles, preference separation, live view changes, on/off rejection and inherited capture/recording regressions. Startup regression: zero failures, readiness gating/split logs, exact formats/UID, timeouts, legacy migration and Premiere Mac-only with no CMIO enumeration. All subprocess/defaults/device APIs in host tests are fakes. No actual camera, USB transfer or audio route is opened/modified. Screenshot fixtures render native controls with example devices.

Native screen conversion/ownership, fullscreen geometry/Escape and six-mode sizing/metering pass. Actual USB packet-generator fixture verifies exact Video packets and clean scopes despite all overlays enabled, preserving pre-overlay Mac fan-out, across six wire modes. Installer filesystem mocks:24 pass. Nine Mach-O programs universal arm64/x86_64, minOS14.4 and deep signatures verified. Camera/output extension directories, HAL and Premiere payloads byte-identical52. Expanded installer and source payload checked at packaging.

Live53 routing, HDMI scopes and new Premiere Mac/paired modes need testing after installation. Intel runtime untested. No publication, driver activation, security or live display/audio changes made during offline verification.
