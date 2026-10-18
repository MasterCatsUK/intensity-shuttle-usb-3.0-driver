# Shuttle Camera 0.1.35 — retain resolution display

A temporary failed settings read during camera reconnection used to replace displayed capture choices with defaults, including Native resolution. The camera could still be using the selected higher resolution. The app now retains its current choices, shows a reconnecting message and retries rather than replacing them with defaults.

Accepted/read capture settings are cached locally for app startup. A successful device read remains authoritative. Automatic retries preserve input/resolution changes that have not yet been applied; pressing Refresh explicitly reloads active device settings. Choose Apply with previews closed to commit hardware/format changes. This is not an automatic-format-change setting.

The camera reported1440×1080 during diagnosis. Tests simulate an unavailable camera after a valid1440 read and verify the UI retains that choice and cache, schedules retry, preserves an unapplied1280 draft and loads actual settings on explicit Refresh. Tests fake all device/preferences/audio/tasks. The change does not alter the driver’s capture pipeline or persistence implementation.

Host35; capture17/output12/HAL3/Premiere1 unchanged. The stale Enable button fix is included. Live picture controls were confirmed working by the user on33. No camera reactivation is needed when17 is already active. Installer checks run during packaging. Installed UI/reopen behaviour still needs confirmation; reboot persistence has not been newly qualified. Existing development security requirements are unchanged.
