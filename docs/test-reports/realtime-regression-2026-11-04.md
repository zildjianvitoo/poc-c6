# Realtime pitch and missing guide blocks — 4 November 2026

The investigation reproduced four code-level regressions before changing the algorithms.
No physical headset trace or recording was available; these results establish failures
in deterministic pipeline logic, not a measurement of a particular headset's sound quality.

| Case | Before | After |
| --- | --- | --- |
| Two seconds of continuous 16 kHz PCM with alternating 0 / 0.75 ms timestamp jitter | 0 pitch windows; clean timestamps produced 39 | 39 windows, identical PCM and sample-anchored times |
| Four-second MIDI 60 note, ±70-cent vibrato at 5 Hz | Zero extracted notes in the initial probe | One continuous four-second block |
| Sustained semitone melody 60 → 61 → 62 → 63 | Simplification returned 60 → 62 | All four pitches retained |
| Measured 60 → 64 → 60 at 50 ms hops | Display held the preceding note for the first frame of each change | Changes shown on their original frame |

The first median-filter change still failed for some vibrato phases. A sweep exposed that
failure before handoff. The final algorithm passed all 56 frequency/phase combinations:
4–7 Hz in 0.5 Hz steps, eight phases, ±70 cents, four seconds each. Each produced one MIDI 60
block spanning the full four seconds. A separate regression preserves a genuine 150 ms
60 → 61 → 60 turn, including its original note timing.

## Causes and corrections

1. PitchFrameBuffer used a two-sample discontinuity threshold (125 microseconds at
   16 kHz). Small timestamp fluctuations repeatedly discarded the partial analysis window.
   It now tolerates at most 2 ms of timestamp jitter and anchors expected timestamps to
   accumulated sample counts. True gaps and sample-rate changes still reset the buffer;
   tests verify unrelated audio is not joined.
2. Guide extraction compared every growing region against its running median. An
   imbalanced vibrato half-cycle shifted that median and split the region into fragments
   shorter than the minimum note duration. Offline centred median filtering removes
   brief salience spikes; a strict pitch-interval bound avoids the running-median split
   while keeping true adjacent-semitone transitions separate. Note pitch remains the
   region's median, and time boundaries remain on the original analysis timeline.
3. SimplifyGuideUseCase merged different pitches separated by one semitone and separately
   discarded isolated notes shorter than 250 ms, even though extraction already validated
   notes from 120 ms. It now merges only identical pitches and preserves validated short
   notes, with floating-point tolerance at the minimum duration. Existing short-pause
   legato repair remains bounded; genuine long rests remain empty.
4. The display-only large-jump confirmation retained the old pitch for a frame. Colour was
   also recomputed from the smoothed value, so a green displayed point could disagree with
   the raw score. Within-note jitter is still smoothed, but real note changes appear
   immediately; target changes reset display history, and colour uses the same isHit as
   evaluation. The pass threshold and pitch tolerance have not been increased.
5. In the separate range-test path, a fixed 4096-frame input tap requests 256 ms per buffer
   at 16 kHz. The requested tap size now follows the negotiated input sample rate and the
   configured 50 ms pitch hop. Actual buffer delivery remains controlled by iOS and must
   be checked on a device.

The headset microphone policy, three range prompts, and one-second stable low/high holds
remain in place. Re-prepare the selected song so its guide uses the corrected extraction;
previously prepared in-memory notes cannot change retroactively.

## Verification

- RealtimeRegressionChecks: 83 assertions passed, including the 56-case vibrato sweep,
  8/16/24/48 kHz PCM continuity, true gaps, sample-rate changes, short notes and real rests.
- RealtimePitchChecks: 25 passed with the revised immediate-transition behaviour.
- VocalKeyChecks: 44 passed.
- Existing Domain suites and contract checks passed. Changed regression expectations in
  GuideAndPitchChecks now require preserving a validated short note, rather than deleting
  it. DetectVocalRange checks still verify the requested one-second hold.
- All app Swift sources typechecked for arm64 iOS Simulator with Swift 5, default MainActor
  isolation, NonisolatedNonsendingByDefault and MemberImportVisibility, without warnings.
- Full xcodebuild attempted; CoreML build subprocesses remain blocked by
  `sandbox-exec: sandbox_apply: Operation not permitted`. Simulator services are unavailable.
  No full app build or device audio-quality verification is claimed.

Run the new standalone regression suite from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 - <<'PY'
from pathlib import Path
import subprocess
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
sources = [str(p) for p in Path('poc-c6/Domain').rglob('*.swift')]
sources += ['poc-c6/Shared/DSP/PitchFrameBuffer.swift', 'Tests/RealtimeRegressionChecks.swift']
subprocess.run(['xcrun', 'swiftc', '-sdk', sdk, '-module-cache-path', '/tmp/songkey-module-cache',
                *sources, '-o', '/tmp/realtime-regression-checks'], check=True)
subprocess.run(['/tmp/realtime-regression-checks'], check=True)
PY
```

Device follow-up: prepare the same clip again; compare the original melody with the blocks,
hold a note with light vibrato, then sing deliberate semitone and larger jumps. Check that
the displayed mic is the intended headset and the Debug pitch sample rate stays near 20/s
while singing. If the headset still produces low voiced coverage, capture a pitch/audio
trace to distinguish input quality, model confidence and inference throughput before
changing scoring thresholds or filling further gaps.

## User device feedback before push

The user confirmed that the three-screen vocal-range test with one-second low/high holds
is acceptable. Pitch detection is still insufficient in actual use and remains an open
issue. The synthetic regression passes above do not mean that on-device detection quality
is resolved. Preserve the accepted range flow and recommendation formula while investigating
future detection changes.
