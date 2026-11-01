# poc-c6 — Takin / Twinkle demo

Open `poc-c6.xcodeproj`, select scheme `poc-c6`. Work is on branch `takin`.

## Implemented

- CREPE tiny on CPU; confidence 0.5, RMS gate 0.01 (-40 dBFS).
- Buffered audio windows with a 50 ms hop, timestamp continuity checks and bounded serial processing. Missing buffers are not interpolated into voiced frames.
- Six Twinkle segments mapped to shared SongSegment/TargetMIDINote contracts. The practice screen uses EvaluateSegmentUseCase, including 75% pass, 100 ms attack exclusion, 100 ms pitch matching tolerance, missing frames as misses and missed-note identification.
- Initial 2-second pre-roll; retries show results, a 3-second countdown, then 2 seconds of pre-roll context when earlier song audio is available. Passed segments continue playback.
- Correction badge, missed-note list and red target highlights; auto-fit target range, playhead at 25%, green/red pitch trail.
- End Session confirmation: finalize/save recording, continue or discard. Discard removes the current raw recording after finalization.
- Audio playAndRecord/videoRecording with Bluetooth A2DP and built-in mic preference. Live earphone checks, disabled start on speaker, Bluetooth sync advisory, interruption/route streams.
- 1.5 GB storage guard and 15-minute session limit. Playback is scheduled with AVAudioPlayerNode host time converted to the capture clock; output latency, IO buffer and persistent manual calibration are added to the audible anchor. Physical-device verification is outstanding.
- Original team Domain contracts, fixtures and validation restored. Thread-safe take repository, TrackLivePitchUseCase and EvaluateSegmentUseCase are available for capture integration.

## Validation

```sh
rtk proxy python3 Tests/run-session-checks.py
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer SWIFT_MODULECACHE_PATH=/tmp/takin-swift-cache CLANG_MODULE_CACHE_PATH=/tmp/takin-clang-cache ./scripts/check-contracts.sh
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project poc-c6.xcodeproj -scheme poc-c6 -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/poc-c6-takin-build CODE_SIGNING_ALLOWED=NO build
```

Session checks cover all six Twinkle segments (correct >=95%, silence/wrong pitch 0%), missed notes, 50 ms frame spacing, discontinuity reset, instrumental auto-pass, take-prefix ordering, duplicate protection and transposed pitch. Legacy tests copied from the old project retain older duration-based scoring assumptions.

## Camera and handoff

- CaptureRepositoryImpl uses the front camera and built-in microphone, portrait/mirrored video output and a HEVC/AAC AVAssetWriter. The writer starts its session at the first video PTS; earlier audio is dropped.
- One capture session feeds both the writer and CREPE. There is no second mic tap. The camera stays running during retries.
- A camera preview with a piano-roll overlay is shown during recording. Target mistakes pulse red; the moving pitch trail is green/red.
- ReferencePlaybackRepositoryImpl schedules AVAudioPlayerNode playback on host time and maps the audible anchor to the capture synchronization clock.
- TakeRangeBuilder maps reference time to video file time with 30 ms handles. Finalization checks the actual asset duration and preserves only complete passed takes, then validates the handoff contract.
- RawMasterVideo.mov and PassedTakes.json are stored in a unique Documents/Recordings directory per session and can be shared together. The JSON contains relative raw-file name, segment definitions, passed take ranges, scores and handles.
- Phone/audio/camera interruptions, background, session timeout and low storage trigger finalization. A background task gives finalization time when the app leaves foreground.
- The latency field accepts -1000...1000 ms and persists locally. Use a wired-earphone click recording to calibrate.

## Remaining / device validation

- Actual camera resolution/orientation/mirroring, 30 fps, AAC channel format, CREPE accuracy and end-to-end latency must be verified on a physical iPhone. Simulator build success is not proof of device capture correctness.
- Run the wired-earphone click test (<=1 frame timing error), continuous retry/no dropped video frames, earphone unplug/phone/background, low-storage and partial-session handoff tests.
- Final comping/mixdown and shareable FinalCoverVideo.mp4 belong to Zildjian's export integration. Current sharing provides raw recording plus validated take metadata, not the final assembled cover.
- Ikzaz song preparation integration is deferred; Twinkle remains the session source.
- Some legacy history/diagnostics UI remains Indonesian; the recording controls are being migrated to English.
- CREPE replaces YIN by user instruction; interoperability with Ikzaz's YIN requirement remains a team decision.

Original external source folder is unchanged. Model license: Licenses/CREPE-LICENSE.txt.
