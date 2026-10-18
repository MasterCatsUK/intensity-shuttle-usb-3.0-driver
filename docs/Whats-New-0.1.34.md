# Shuttle Camera 0.1.34 — camera readiness fix

The app could retain an Enable picture controls button after camera17 became active. Pressing it requested another driver replacement and could disconnect a QuickTime preview. This update checks the current camera before that action: when live controls are already available it refreshes the panel and returns without a replacement request. Opening Picture also refreshes readiness without overwriting unapplied Capture-tab settings. Bounded readiness refreshes after activation cover delayed reconnection.

If a preview was disconnected by an earlier activation, close QuickTime’s movie-recording window and open File → New Movie Recording again. Reselect the Shuttle camera. In Shuttle Camera, Capture → Refresh reloads settings; Picture → Live adjustments enables the sliders. Enable picture controls is a setup action, not the switch for live adjustments.

Host34 only; camera17, output12, HAL3 and Premiere1 retain their versions. No reactivation is needed when17 is already enabled. Fresh/older installations still need camera activation with previews closed. The idle delay defaults to two minutes and all previous options remain.

Offline UI regression tests reproduce stale controls, refresh them while retaining an unapplied NTSC selection, and dispatch the stale Enable action against a ready fake camera. It returns before any system-extension request, device write, audio change or helper launch. Installer tests and expanded payload/signatures are verified during packaging. Physical preview recovery/live-slider confirmation is still pending.
