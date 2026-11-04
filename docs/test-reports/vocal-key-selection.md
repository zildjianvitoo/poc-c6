# Vocal range and key comparison — updated 4 November 2026

Scope: C6 main app, vocal-range/import preparation (IK-03, IK-09, IK-10, IK-11).

## Behaviour

- Three prompts: normal speaking baseline, comfortable low hum, comfortable high note.
  Speaking pitch is the median of voiced
  frames over a six-second sample, with at least two seconds of voiced frames. It is a
  starting reference only and never contributes to key scoring.
- Both sung notes must be stable for one second using the existing detector. These
  stable holds confirm consistency, with no extra repeated-note prompts.
- Analyse/separate the selected clip once. Score the original sanitised vocal notes,
  before guide simplification can remove extremes or change their durations.
- Reject every shift with any detected note outside the confirmed range. Use the supplied
  duration-weighted squared penalty, with b = min(3, (H-L)/4), and return at most three
  keys. Ties prefer the smallest absolute shift, then the lower shift.
- Candidates use the existing supported audio shifts, -6 through +6 semitones, with
  octaveShift = 0. No target-only octave recommendations are used in this flow.
- Select the breath-delimited phrase containing the highest vocal note. For equal peaks,
  prefer the longest held occurrence, then the earliest. Include half of segmentGap as
  breathing room at either end and clamp to the selected clip.
- Each Listen button copies that exact frame interval from the pitch-shifted original
  instrumental stem into a temporary preview file. All candidates preview the same
  interval. No synthesised note, replacement instrument, or original vocal stem is used.
- User explicitly selects a key; its prepared mix, instrumental, targets and transposition
  are passed to Ready and recording. Ready offers Compare Keys Again.
- Zero fitting candidates shows an explanation and options to retest or select another
  section. One or two candidates remain one or two; no unsuitable keys are added.
- Preview stops when leaving, selecting another preview, receiving an interruption, or
  changing output route. Repeated route notifications for the same route do not stop it.

Existing shared Entities, Repositories, Contracts, Xcode project settings and scripts are
unchanged. Feature defaults extend PoCConfiguration through computed properties, preserving
its existing Codable storage. The legacy single-plan use case remains compatible for
existing callers; the main import and demo flows now use the new choice preparation API.

## Verification

- Existing domain checks: passed, including 5,000 segment layouts and 3,000 transposition
  comparisons. Existing contract checks: passed.
- Updated `Tests/VocalKeyChecks.swift`: 44 checks passed. Covers candidate counts, strict
  rejection, deterministic ties, numeric quadratic/duration scores, narrow range handling,
  peak phrase selection, one analysis/separation per clip, matching audio/target shifts,
  validated prepared songs, explicit user selection, stale completion handling, visible
  preview failures, three-step flow, baseline/stable-hold/silence, and exact original stereo PCM copying.
- All app Swift sources typechecked for arm64 iOS Simulator, Swift 5, default MainActor
  isolation and NonisolatedNonsendingByDefault: passed without warnings. The compiler was
  explicitly supplied Xcode's macOS-host Observation/SwiftUI/Preview macro libraries.
- Full xcodebuild attempted for Simulator and unsigned iPhone. Blocked by the environment:
  CoreML's build subprocess reports `sandbox-exec: sandbox_apply: Operation not permitted`.
  Simulator runtime services are also unavailable. A full app build and physical-device
  microphone/playback validation remain pending.
- The stock domain/contract shell scripts split absolute paths containing spaces. Their
  exact Swift source lists were compiled and executed via Python subprocess argument arrays
  instead; the scripts were not edited.

Before pushing to `takin`, another run was attempted with an explicit matching macOS SDK
and writable module cache. This environment blocked the Observation macro subprocess
with `sandbox_apply: Operation not permitted`; the earlier 41-check pass is retained
as the last completed feature run.

## Run feature checks on a Mac

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 - <<'PY'
from pathlib import Path
import subprocess
sources = list(Path('poc-c6/Domain').rglob('*.swift'))
sources += [Path('poc-c6') / path for path in [
    'Shared/DSP/PitchMath.swift',
    'Presentation/Common/MediaPermissionProviding.swift',
    'Presentation/Common/UserFacingError.swift',
    'Presentation/Common/UserFacingConvertible.swift',
    'Presentation/Common/MicrophoneInputProviding.swift',
    'Presentation/Common/HeadsetMicrophoneErrors.swift',
    'Data/Audio/HeadsetMicrophoneError.swift',
    'Presentation/VocalRange/LivePitchSource.swift',
    'Presentation/VocalRange/VocalRangeViewModel.swift',
    'Presentation/Import/AudioPreviewing.swift',
    'Presentation/Import/KeySelectionViewModel.swift',
    'Fakes/FakeVocalRangeRepository.swift',
    'Data/Audio/AudioExcerptRenderer.swift',
]]
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'swiftc', '-sdk', sdk,
    '-module-cache-path', '/tmp/songkey-module-cache', '-swift-version', '5',
    '-default-isolation', 'MainActor', *map(str, sources),
    'Tests/VocalKeyChecks.swift', '-o', '/tmp/vocal-key-checks'], check=True)
subprocess.run(['/tmp/vocal-key-checks'], check=True)
PY
```

## Device acceptance still required

1. Re-test an existing saved range using a headset mic; read naturally, hum low, and sing high. Confirm there are exactly three prompts, and each sung limit requires a stable one-second hold.
2. Import a stereo song with a known high phrase. Confirm each candidate plays its original
   accompaniment at that phrase, with matching tempo and different keys.
3. Sing along with each choice, select a non-first choice, and confirm Ready/recording use it.
4. Reopen comparison; switch previews rapidly, stop mid-playback, unplug headphones, and
   interrupt audio. Check the play buttons recover and no stale clip continues playing.
5. Test one, two and zero fitting keys. Confirm there is no forced third candidate and that
   retesting/choosing another section works.

Phrase boundaries come from detected vocal pauses, not lyrics or musical verse markers.
Pitch extraction/separation quality affects recommendations; the scoring is a heuristic,
not a measured guarantee of singing comfort.

## Realtime pitch and headset microphone fixes — 4 November 2026

- The range UI now has exactly three prompts: speaking, lowest comfortable hum, highest
  comfortable sung note. The one-second stable hold is the consistency check. Simulator
  fixtures and regression checks follow the same three-prompt sequence.
- Range note labels, the recording note readout and piano-roll trail use a display-only
  stabiliser. It smooths small jitter and shows note changes immediately, without a
  confirmation delay. Silence, rewinds and callback gaps reset it.
  Raw samples still determine stable holds, key recommendations and recording scores.
- Both range capture and video recording use HeadsetMicrophoneSession, with HFP enabled
  for Bluetooth input. Wired headset inputs take priority over USB, then Bluetooth. Built-in
  and output-only devices are rejected. The active input UID is verified before sampling,
  and the actual microphone name is shown on screen.
- The shared audio session is explicitly used by AVCaptureSession. Bluetooth HFP output
  is recognised by the route monitor. Input loss/replacement ends range capture and stops
  video recording; it does not silently continue with the phone's microphone. Route loss
  is handled as an interruption, allowing the video to finalise and passed takes to remain
  available for partial export. Audio buffers from a fallback microphone are not appended
  after the input-change notification is processed.
- Centralised microphone errors tell the user to connect a headset with a microphone.
- Updated PRD §§4, 5.1, 6.5 and 7.2 supersede the previous built-in-microphone policy.

Verification: 25 RealtimePitchChecks and 44 VocalKeyChecks passed, alongside the existing
Domain and contract suites. All app Swift sources typechecked for arm64 iOS Simulator,
Swift 5, default MainActor isolation, NonisolatedNonsendingByDefault and MemberImportVisibility,
without warnings. The full Xcode build remains blocked by the environment's CoreML sandbox
subprocess restriction and unavailable Simulator services. Hardware routing, actual sound
quality, Bluetooth latency and unplug/reconnect behaviour still require a physical iPhone.

To run the display and input-selection checks, compile all Domain Swift files plus
`Tests/RealtimePitchChecks.swift` into a separate executable (it has its own `@main`),
using the same SDK/module-cache settings as the feature-check command above.

Device acceptance: connect a wired headset and then a Bluetooth headset in separate runs;
confirm the displayed microphone matches the headset in both the range test and recording.
Try singing a held note and then a deliberate interval jump, disconnect the microphone
mid-recording, and confirm recording stops while previously passed segments can be exported.
With no compatible microphone, check that the app explains what must be connected.

The follow-up investigation and corrected guide/PCM continuity behaviour are documented
in `realtime-regression-2026-11-04.md`. Re-prepare songs to regenerate existing guide blocks.
