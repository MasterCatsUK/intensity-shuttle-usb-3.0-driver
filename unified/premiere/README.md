# Shuttle Premiere Pro output — host 0.1.53 / Transmit plug-in 2

Universal arm64/x86_64 Mercury Transmit video plug-in. Adobe's downloaded 26.0 SDK was used to build against the version1 API. The previously tested installed editor was Premiere25.2.3; Intel runtime and the new Mac-only/paired routes still need live qualification.

## Use

1. In Shuttle Video → Output Settings, choose Premiere Pro, a matching Format and **Mac screen / Shuttle output** independently: Video, Video scopes or Off. Choose a Mac display if enabled.
2. Start Premiere output and wait for Ready. Keep Shuttle Video running.
3. In Premiere Playback settings enable Mercury Transmit and **Intensity Shuttle — HDMI Output**. This same plug-in supplies Mac-only, Shuttle-only and both outputs.
4. In Premiere Audio Hardware choose **Virtual Shuttle Audio** for meters and output sound. Use Shuttle Audio in the app changes only the system media route; an explicit Premiere selection must be made/restored inside Premiere. Enable Listen on Mac for local hearing.
5. Video/Scopes and scope types can change live. Disable Mercury Transmit and Stop before changing outputs to/from Off or changing format. Stop restores a system audio route owned by the app, respecting later manual changes.

Scopes omit TC/meters/safe guides; Video overlays are saved independently for Mac/Shuttle. Timecode uses Adobe sequence time plus sequence zero point/drop-frame metadata; missing timestamps display dashes. Both outputs receive rendered edits/effects/titles when Premiere supplies the frame. No audio transport or playback clock is advertised by Transmit.

## Transport and build

Run `premiere/build.sh '/path/to/Adobe SDK/Examples'`. Obtain the SDK separately; no Adobe headers/sample code are distributed. Original project plug-in sources are GPL-2.0-or-later.

Install path: `/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle`. Premiere25 scanned this legacy Plug-ins path in Plugin Loading.log.

Premiere video uses localhost TCP47540. Mac-only uses ShuttleScreenOutput directly; paired uses one ShuttlePlayback receiver and a clean shared-memory frame feed to the Mac helper. The paired Mac tap does not bind another audio receiver. USB runs outside Premiere. PPix buffers are copied and released exactly once, with bounded worker/backpressure. Final Cut ports remain47539/47541; output13/HAL4/Transmit2 stay unchanged.

Offline tests cover launch plans, split readiness logs, scoped display conversion, clean fan-out and bounded transport. A successful build is not a live playback qualification.
