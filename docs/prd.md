# SRS & PRD: iOS Song Cover Recording & Auto-Comping PoC

> **Version 3** — 31 Oct 2026. v2 incorporated the decisions from `docs/review-prd.md`; v3 adds the team ownership split (§12) and switches guide extraction to Basic Pitch on the vocal stem (from `docs/review-tech-flow.md`). Lives at `docs/prd.md` (outside the app target so it is not bundled). Previous version archived at `docs/archive/prd-v1.md`. Accuracy roadmap: `docs/roadmap-akurasi.md`.

## 1. Project Overview & Core Value Proposition
Build an iOS 18+ Proof of Concept (PoC) application in Swift & SwiftUI for independent Gen Z song cover creators.
The app eliminates repetitive trial-and-error recording (retaking the entire song from the beginning when making a single pitch mistake) through 5 core mechanisms:
1. **Vocal Range Test & Auto-Transpose:** The user's comfortable vocal range is measured once. The reference song (guide notes, earphone audio, and backing music) is transposed by semitones to fit that range.
2. **Reference Separation, Audio-to-MIDI & Auto-Segmentation:** Importing a full reference song (full mix with the original vocals, trimmed to 15–60 s), separating it into a vocal stem and an instrumental stem (see §3 for the two-track strategy), extracting the vocal melody into target MIDI notes, and slicing the song into phrase segments based on breathing pauses/silences.
3. **Continuous Camera Recording + Synced Reference Playback + Live Piano Roll:** Recording a single, uninterrupted 9:16 vertical video (`RawMasterVideo.mov`) while playing the reference audio through earphones and rendering a semi-transparent real-time Piano Roll overlay in the center of the screen.
4. **Segment Evaluation & Seamless Auto-Rewind Loop:** Evaluating pitch accuracy at the end of each phrase segment. If the score is `< 75%` (**TRY AGAIN**), highlight missed notes, show a `3.. 2.. 1..` countdown, and rewind the Piano Roll playhead + reference audio to the start of the current segment WITHOUT pausing the camera recording. If `>= 75%` (**PASSED**), log the valid video `CMTimeRange` and continue straight into the next segment.
5. **Automated Comping & Mixdown (Auto-Cut, Stitch & Mix):** When all segments pass — or the user ends the session early — slice `RawMasterVideo.mov` using the logged `CMTimeRange`s, place each passed take at its exact position on the song timeline, crossfade vocal takes (30 ms), mix the user's vocal with the **instrumental (no original vocals)**, and export a single `FinalCoverVideo.mp4` ready for social media upload.

---

## 2. Scope

### 2.1 In Scope (PoC)
* Vocal range test, auto-transpose (semitone level).
* Import (Files / Photos / bundled demo), trim 15–60 s, stem separation, guide extraction, segmentation.
* Continuous recording session with live piano roll, evaluation loop, early end with partial export.
* Comping, vocal + instrumental mixdown, export, preview, share, save to Photos.
* Debug settings screen for tuning thresholds (§8).

### 2.2 Out of Scope (PoC)
* Lyrics display, manual editing of guide notes, MIDI import.
* Choosing between multiple passed takes of the same segment, voluntarily re-recording a passed segment.
* Vocal effects (reverb, EQ, auto-tune), video transitions/filters (video cuts are hard cuts).
* Landscape, iPad, accounts/backend, direct upload to social platforms, cloud processing.

### 2.3 Platform
* **iOS 18.0+, iPhone only, portrait only.** Testing requires a physical iPhone (front camera + mic).
* **Swift 5 language mode** with the project's existing settings: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Approachable Concurrency. SwiftUI with `@Observable` (Observation framework). See §7.4 for the realtime-audio isolation rule.
* **UI language: English** (all strings, including statuses PASSED / TRY AGAIN).

---

## 3. Technical Stack & "Start Small, Scale Modularly" Strategy
* **Architecture:** Clean Architecture (`Presentation Layer` -> `Domain Layer` -> `Data & Infrastructure Layer`) using Protocol-Oriented Programming so implementations can be swapped easily.
  * **Presentation uses MVVM:** SwiftUI `View` → `@Observable` `ViewModel` → Use Case. ViewModels never touch AVFoundation/CoreML directly; they only call Use Cases (and, for the camera preview, `CameraPreviewSource`).
  * **Kept light for the PoC:** thin Use Cases that just forward to a repository are fine; no DTOs/mappers between layers (Domain entities are used directly); no Coordinator/Router (plain SwiftUI navigation in `AppContainer`).
* **Phase 1 (this PoC):**
  * Native `AVFoundation`, `AVFAudio`, `Accelerate`.
  * **Pitch detection: CREPE tiny (CoreML, bundled `CrepeTiny.mlmodel`, ~2 MB, MIT)** for **live** pitch, the vocal range test and the guide-extraction fallback. One shared `CrepePitchDetector`; voiced only when confidence ≥ 0.5 and RMS ≥ the noise gate. Credit both marl/crepe and torchcrepe in `Licenses/`. *(Team decision 2026-11-01: replaces YIN.)*
  * **Guide extraction: Spotify Basic Pitch (CoreML)** run on the **vocal stem**, followed by monophonic reduction (§5.3). Bundled as an `.mlpackage`, no SPM dependency. Verify the model license and the CoreML export before committing.
  * **Stem separation — two-track strategy:**
    * **Track A — Guaranteed demo:** a bundled, royalty-free demo song whose stems (`mix`, `vocal`, `instrumental`) were separated **offline on a Mac** (e.g. Demucs) plus a verified guide file. Guarantees the end-to-end demo sounds good. Copyrighted songs must NOT be bundled in the repo/app.
    * **Track B — On-device spike (time-boxed 3–5 days):** evaluate a CoreML separation model for user-imported songs. Measure model size, processing time for a 60 s clip (target < 30 s), peak memory, and separation quality. If the spike fails, imported songs use the **center-channel cancellation fallback** (L−R for instrumental, mid channel for vocal guide) with a disclaimer.
  * **Order decided 2026-11-01:** user import comes first (center-channel fallback + CREPE guide on the device), then the Track B spike; the Track A demo is a later safety net.
  * **Developer fallback:** a synthesized demo (sine melody as "vocal", simple chord pad as "instrumental", mix = sum) so the pipeline is testable before the Track A asset exists.
* **Phase 2+:** better ML pitch models, AudioKit, etc. — see `docs/roadmap-akurasi.md`. All swaps happen behind the repository protocols in §6.3.

---

## 4. End-to-End User & System Workflow
0. **Step 0 (Vocal Range Test — once, re-testable from Settings):** User sings their lowest comfortable note, then their highest, each held ~2 s. The stable pitch is stored as `VocalRange`.
1. **Step 1 (Import & Trim):** User picks a reference song (full mix) from Files/Photos or loads the bundled demo, then trims it to 15–60 s. The Phase 1 disclaimer (§5.2) is shown.
2. **Step 2 (Offline Preparation):** Stem separation → guide extraction from the vocal stem → segmentation → transposition plan → offline render of transposed earphone mix and transposed instrumental. Progress shown step by step.
3. **Step 3 (Ready Screen):** Shows segment count, chosen transposition (e.g. "−3 semitones"), and an earphone check. Record is disabled when audio output is the built-in speaker/receiver.
4. **Step 4 (Uninterrupted Session):** User taps Record. Front camera (9:16) + built-in mic record continuously into `RawMasterVideo.mov`. Pre-roll then Segment 1 plays in the earphones; the piano roll scrolls and the user's live pitch trail is drawn (green = within ±50 cents, red = off).
5. **Step 5 (Evaluation Loop):** At the end of Segment N (+ latency tail):
   * **TRY AGAIN (< 75%):** playback stops, missed notes flash red, `3.. 2.. 1..` countdown, pre-roll, Segment N again. Camera keeps rolling.
   * **PASSED (≥ 75%):** green badge flashes; playback has already continued seamlessly into Segment N+1 (no stop, no countdown).
6. **Step 6 (End):** Session ends when the last segment passes, or when the user taps **End Session** (confirmation: *Export N of M segments* / *Keep recording* / *Discard*), or on an interruption (§5.8).
7. **Step 7 (Comping & Export):** Passed takes are stitched onto the song timeline, mixed with the transposed instrumental, exported as `FinalCoverVideo.mp4`, and presented with player, Share, and Save to Photos.

---

## 5. Functional Requirements

### 5.1 Vocal Range Test
* Two prompts: "Sing your lowest comfortable note" and "Sing your highest comfortable note". Each records until ~2 s of stable pitch (pitch varies < ±50 cents) is captured; value = median MIDI of stable frames.
* Live pitch readout with note name during the test. Retry per prompt.
* Persisted locally (`UserDefaults`); "Re-test Vocal Range" in Settings.

### 5.2 Import, Trim & Disclaimer
* Formats: `.mp3`, `.m4a`, `.wav`, `.mov` (audio track extracted). DRM-protected files must show a clear error.
* Waveform trimmer, min 15 s, max 60 s.
* Disclaimer (processing screen + small badge on the recording screen):
  > **Experimental (Phase 1):** The pitch guide is extracted from the original song and may be inaccurate, especially in busy sections.
* When the center-channel fallback is used, additionally:
  > Background music uses basic vocal removal. Some original vocals may still be audible.

### 5.3 Guide Extraction & Segmentation
* **Extraction input:** the vocal stem (bundled or CoreML) or the mid channel (fallback).
* **Primary — Basic Pitch:** resample to the model's input rate, run inference, take note events (pitch, onset, offset, confidence). Basic Pitch is polyphonic, so apply **monophonic reduction**: at each moment keep only the highest-confidence note, drop notes < 120 ms or below a confidence threshold, merge consecutive same-pitch notes separated by < 50 ms.
* **Fallback — CREPE:** run `CrepePitchDetector` over the vocal stem every 50 ms → frames below the confidence threshold are unvoiced → stable regions ≥ 120 ms (< ±50 cents variation) become notes. Used when Basic Pitch fails to load or produces no notes.
* Notes are stored in the **original key**; transposition is applied at display/evaluation time.
* **Frequency → MIDI** (CREPE paths, live pitch): $M = 69 + 12 \log_2(f/440)$, implemented once in a shared helper.
* **Singable guide (`SimplifyGuideUseCase`, device feedback 2026-11-01):** extracted notes within a semitone and ≤ 0.35 s apart are merged into one block (dominant pitch), gaps ≤ 0.3 s are bridged, isolated notes < 0.25 s are dropped.
* **Segmentation (`SliceSegmentsUseCase`):**
  1. Split where the gap between consecutive notes is > 0.8 s.
  2. Merge segments shorter than 3.0 s into the neighbour with the smaller gap, as long as the result is ≤ 8.0 s.
  3. Split segments longer than 8.0 s at the largest internal gap (or the note boundary closest to the middle if there is no gap).
  4. **Segments tile the whole trimmed timeline with no holes:** each boundary is placed at the midpoint of its gap; the first segment starts at 0, the last ends at the trim end.
     * **Long gaps become instrumental-only segments with breathing room** *(team decision 2026-11-01)*: when a gap (intro, interlude, outro) is long enough that `gap − segmentGap ≥ minSegment`, its boundaries sit `segmentGap / 2` (0.4 s) away from the notes — the phrase before ends at `lastNote.end + 0.4`, the phrase after starts at `nextNote.start − 0.4`. Shorter gaps use the midpoint rule. A boundary never sits exactly on a note edge, so breaths and early onsets are not cut by the crossfade.
     * Time comparisons (equal gaps, overlaps, end of song) use a 1 ms tolerance. Notes from analysis are clamped to `[0, duration]` and tiny overlaps (< 1 ms) are trimmed before segmentation instead of failing.
     * Rule 3 prefers cut points that keep both sides ≥ `minSegment`; only if none exists may a shorter piece remain.
  5. A segment with no notes (instrumental intro/interlude) is marked instrumental-only: it is played and recorded but **auto-passes** without evaluation.

### 5.4 Transposition
* Song range = min/max MIDI of all target notes. Choose a total shift `k ∈ [−12, +12]` that minimizes notes outside the user's `VocalRange`; ties → smallest `|semitoneShift|`, then smallest `|k|`.
* Decompose `k = 12 × octaveShift + semitoneShift`, `semitoneShift ∈ [−6, +6]`.
  * `octaveShift` only shifts target notes (audio unchanged — singing an octave apart is natural).
  * `semitoneShift` is applied to audio: the earphone mix and the instrumental are rendered **offline** in Step 2 with `AVAudioEngine` manual rendering + `AVAudioUnitTimePitch` (`pitch = semitoneShift × 100` cents). The same rendered instrumental is used in the final mix so the vocal stays in key.
* Target notes for display/evaluation = original MIDI + `k`.

### 5.5 Recording Screen & Piano Roll
* Full-screen front camera preview (`AVCaptureVideoPreviewLayer`, aspect-fill) with a 9:16 frame guide showing the recorded area.
* **Center piano roll** (`Canvas` + `TimelineView`, 60 fps): semi-transparent horizontal lane centered on screen so the singer's eyes stay near the lens.
  * Vertical range: auto-fit to the current segment's notes ± 3 semitones; note names on the left edge.
  * Scroll: playhead fixed at 25% from the left; ~4 s visible (≈1 s past, ≈3 s look-ahead).
  * Blocks: target notes (transposed). Trail: user's pitch, green within ±50 cents, red otherwise, none when unvoiced.
  * During pre-roll, the previous material is shown greyed out.
* Top bar: `Segment 3 / 7 · Attempt 2`, Bluetooth warning when applicable, Phase 1 badge, **End Session** button.
* **The overlay is UI only and is never burned into the recorded video.**

### 5.6 Evaluation & Loop
* **Pitch frames:** every 50 ms; RMS noise gate −40 dBFS (below = unvoiced).
* **Evaluated frames:** frames where a target note is active, **excluding the first 100 ms of each note** (attack). Frames with no target note are ignored.
* **Hit:** user voiced AND `|Δcents| ≤ 50` against the target at time `t`, or any target note within ±100 ms of `t` (timing tolerance). $\Delta_{\text{cents}} = 100 \times (M_{\text{user}} - M_{\text{target}})$. A target-active frame where the user is silent is a **miss**.
* **Octaves are ignored** when comparing pitch (singing the melody an octave lower/higher is in tune), and the trail is drawn in the target's octave *(device feedback 2026-11-01)*.
* **Score** = hits / **voiced** evaluated frames when the singer is voiced for ≥ 60% of the evaluated frames; otherwise hits / all evaluated frames (silence = miss). PASSED if ≥ 0.75. A segment with zero evaluated frames auto-passes. *(Changed 2026-11-01: on a real song the original singer is voiced only ~74% of the time, so "silence = miss" failed 73% of the original singer's own segments; with this rule and ±80¢ the original passes 100%, while singing 2 semitones off or not singing passes 0%.)*
* **Missed note** (flashed red) = note whose own hit ratio < 50%.
* **Timing:** evaluation runs at `segment end + latencyOffset + 150 ms` (see §7.1).
* **Session start:** the first attempt also begins with the silent `3.. 2.. 1..` countdown, then the pre-roll, so the singer and the pitch detector are ready before the first note *(added 2026-11-01 after device testing)*.
* **On PASSED:** playback continues uninterrupted into the next segment.
* **On TRY AGAIN:** stop playback → result (~1 s, missed notes red) → `3.. 2.. 1..` (3 s, silent) → **pre-roll** of 2.0 s of reference audio before the segment start (from 0 if not available) → segment. Pre-roll and countdown are never part of a take's video range.

### 5.7 Session End & Partial Export
* Because progress is sequential, passed segments are always a prefix `1…N`.
* Full export when all M segments pass; partial export of `1…N` when the user ends early or on interruption. Instrumental is cut at the end of segment N with a 1.0 s fade-out over the final second.
* If N = 0: message "Nothing to export yet", option to restart.

### 5.8 Interruptions & Limits
* Phone call / Siri / app backgrounded / earphones unplugged (route → speaker) / camera taken by another app / low storage → stop session, finalize the file, offer partial export.
* Bluetooth earphones are allowed with a warning banner ("Wired earphones give the best sync"); wired is recommended.
* Max session (raw recording) length: 15 min. Require ≥ 1.5 GB free storage before Record.

### 5.9 Comping, Mixdown & Export
* Composition timeline = song timeline (trimmed reference, starting at 0).
* For each passed segment `i`: insert its take's video at composition time `segment.audioStartTime` with duration `segment.audioDuration` (video: hard cut).
* Vocal audio: takes alternate between two composition audio tracks (A/B) with 30 ms handles on each side and complementary `setVolumeRamp`s → true 30 ms crossfade. (A single track only produces a dip, not a crossfade.)
* Instrumental: transposed instrumental on its own track from 0 to the export end time.
* Default gains: vocal 1.0, instrumental 0.8 (tunable, §8).
* **Front camera mirrored** in the final video (matches the preview, like a selfie).
* Output: `FinalCoverVideo.mp4`, 1080×1920, 30 fps, H.264, AAC 48 kHz stereo. Raw recording: HEVC.
* Export preview: `VideoPlayer`, `ShareLink`, Save to Photos (add-only permission). Temp files cleaned on new session.

---

## 6. System Design & Clean Architecture Blueprint

### 6.1 Presentation Layer (`Views` & `@Observable ViewModels`)
1. **`VocalRangeTestView` & `VocalRangeViewModel`** — §5.1.
2. **`AudioImportView` & `PrepViewModel`** — importer, trimmer, disclaimer, step-by-step processing state, ready screen with earphone check.
3. **`RecordingPianoRollView` & `RecordingViewModel`** — camera preview, piano roll, top bar, End Session dialog.
4. **`CorrectionOverlayView` & `LoopStateController`** — drives the session state machine:
   `idle → preRoll → singing(segment) → evaluating → { passed → singing(next) | failed → showingResult → countdown → preRoll } → ended → exporting → done`
5. **`ExportPreviewView` & `CompingViewModel`** — progress, player, Share, Save.
6. **`DebugSettingsView`** — edits `PoCConfiguration` (§8).

The camera preview is provided through a presentation-side `CameraPreviewSource` protocol (implemented by the capture infrastructure) so `AVCaptureSession` never appears in the Domain layer.

### 6.2 Domain Entities
> **Source of truth is the code in `poc-c6/Domain/`** (entities, protocols, `ContractValidation`, `DomainFixtures`). The snippets in §6.2–6.3 are a readable summary; if they differ, the code wins. Change process: `docs/COLLABORATION.md` §3.

```swift
import Foundation
import CoreMedia

public struct TargetMIDINote: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let midiNote: Int            // Original key, e.g. 60 = C4
    public let startTime: TimeInterval  // Seconds, relative to trimmed reference
    public let duration: TimeInterval
}

public struct SongSegment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let index: Int
    public let audioStartTime: TimeInterval
    public let audioDuration: TimeInterval
    public let targetNotes: [TargetMIDINote]
    public var isInstrumentalOnly: Bool { targetNotes.isEmpty }
}

public enum StemSeparationMethod: String, Sendable {
    case bundled, coreML, centerChannelCancellation, synthesized
}

public struct SeparatedStems: Sendable {
    public let mixURL: URL           // Trimmed full mix (earphone guide)
    public let vocalGuideURL: URL    // Vocal stem or mid channel, used for extraction
    public let instrumentalURL: URL  // No original vocals, used in final mix
    public let method: StemSeparationMethod
}

public struct VocalRange: Sendable, Codable, Equatable {
    public let lowestMIDI: Float
    public let highestMIDI: Float
}

public struct TranspositionPlan: Sendable, Equatable {
    public let octaveShift: Int      // Applied to target notes only
    public let semitoneShift: Int    // -6...6, applied to audio and target notes
    public var totalSemitones: Int { octaveShift * 12 + semitoneShift }
}

public struct PreparedSong: Sendable {
    public let earphoneMixURL: URL       // Transposed by semitoneShift
    public let instrumentalURL: URL      // Transposed by semitoneShift
    public let segments: [SongSegment]
    public let transposition: TranspositionPlan
    public let duration: TimeInterval
    public let separationMethod: StemSeparationMethod
}

/// Raw output of the pitch detector. Knows nothing about targets.
public struct PitchSample: Sendable {
    public let captureTime: CMTime   // Capture session synchronization clock
    public let frequency: Float?     // nil when unvoiced / below noise gate
    public let rmsDecibels: Float
}

/// Output of TrackLivePitchUseCase, used by the piano roll and evaluation.
public struct PitchEvaluation: Sendable {
    public let referenceTime: TimeInterval
    public let detectedMIDINote: Float?
    public let targetNoteID: UUID?
    public let centDeviation: Float?
    public let isHit: Bool
}

public enum SegmentAttemptStatus: String, Sendable {
    case passed, failed
    public var displayLabel: String { self == .passed ? "PASSED" : "TRY AGAIN" }
}

public struct TakeAttemptLog: Identifiable, Sendable {
    public let id: UUID
    public let segmentIndex: Int
    public let attemptNumber: Int
    public let videoTimeRange: CMTimeRange // In RawMasterVideo.mov file time, incl. 30 ms handles
    public let accuracyScore: Float        // 0.0 ... 1.0
    public let missedNoteIDs: [UUID]
    public let status: SegmentAttemptStatus
}

public struct CompingCompositionPlan: Sendable {
    public let rawVideoURL: URL
    public let instrumentalURL: URL
    public let segments: [SongSegment]      // For timeline placement
    public let validTakes: [TakeAttemptLog] // 1 passed take per segment, prefix 1...N
    public let endTime: TimeInterval        // End of last passed segment
    public let crossfadeDuration: CMTime    // 30 ms
    public let instrumentalFadeOut: TimeInterval // 1.0 s for partial export, 0 for full
    public let vocalGain: Float
    public let instrumentalGain: Float
}
```

### 6.3 Domain Repository Protocols
```swift
import Foundation
import CoreMedia

public protocol StemSeparationRepository: Sendable {
    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems
}

public protocol AudioAnalysisRepository: Sendable {
    /// Input is already trimmed. Returns notes in the original key.
    func extractVocalGuideNotes(from vocalGuideURL: URL) async throws -> [TargetMIDINote]
}

public protocol AudioTranspositionRepository: Sendable {
    func renderTransposed(_ audioURL: URL, semitones: Int) async throws -> URL
}

public protocol VocalRangeRepository: AnyObject {
    func load() -> VocalRange?
    func save(_ range: VocalRange)
}

public protocol CaptureRepository: AnyObject {
    func prepare() async throws
    func startRecording() async throws
    func stopRecording() async throws -> URL
    func pitchSamples() -> AsyncStream<PitchSample>     // New stream per call
    func currentCaptureTime() -> CMTime
    func fileTime(forCaptureTime time: CMTime) -> CMTime? // nil before first frame
}

public protocol ReferencePlaybackRepository: AnyObject {
    func load(earphoneMixURL: URL) throws
    /// Schedules playback from `referenceTime` and returns the capture-clock time
    /// at which that point is *heard* (scheduled host time + output latency).
    func play(from referenceTime: TimeInterval) throws -> CMTime
    func stop()
}

public enum AudioOutputRoute: Sendable { case wired, bluetooth, speaker, other }

public protocol AudioRouteMonitor: AnyObject {
    var currentRoute: AudioOutputRoute { get }
    func routeChanges() -> AsyncStream<AudioOutputRoute>
    func interruptions() -> AsyncStream<Void>
}

public protocol SessionTakeLogRepository: AnyObject {
    func logAttempt(_ attempt: TakeAttemptLog)
    func allAttempts() -> [TakeAttemptLog]
    func passedTakesPrefix() -> [TakeAttemptLog]
    func clear()
}

public protocol VideoCompositionRepository: Sendable {
    func stitchAndExport(plan: CompingCompositionPlan,
                         progress: @Sendable (Double) -> Void) async throws -> URL
}
```

### 6.4 Domain Use Cases
* **`DetectVocalRangeUseCase`** — §5.1, stable-pitch detection over `PitchSample`s.
* **`PrepareSongUseCase`** — orchestrates: `StemSeparationRepository` → `AudioAnalysisRepository` → `SliceSegmentsUseCase` → `ComputeTranspositionUseCase` → `AudioTranspositionRepository` (earphone mix + instrumental) → `PreparedSong`.
* **`SliceSegmentsUseCase`** — §5.3.
* **`ComputeTranspositionUseCase`** — §5.4.
* **`TrackLivePitchUseCase`** — maps `PitchSample.captureTime` to reference time using the playback anchor, converts to MIDI, compares against transposed targets → `PitchEvaluation` (§5.6).
* **`EvaluateSegmentUseCase`** — §5.6 scoring; builds the take's `videoTimeRange` (§7.1); logs a `TakeAttemptLog`.
* **`AutoCompingVideoUseCase`** — builds `CompingCompositionPlan` from `passedTakesPrefix()` and calls `VideoCompositionRepository`.

### 6.5 Data & Infrastructure Layer
1. **Stem separation:** `BundledStemsRepository` (Track A demo), `SynthesizedDemoRepository` (developer fallback), `CenterChannelStemRepository` (L−R / mid fallback), `CoreMLStemSeparationRepository` (Track B spike, behind a feature flag).
2. **Guide extraction:** `BasicPitchAnalysisRepository` (CoreML + monophonic reduction) and `CrepeAnalysisRepository` (`AVAssetReader` → PCM float → `CrepePitchDetector`), both conforming to `AudioAnalysisRepository` (§5.3). Fallback chosen in `PrepareSongUseCase`.
3. **`AudioTranspositionRepositoryImpl`** — `AVAudioEngine` offline manual rendering + `AVAudioUnitTimePitch`.
4. **`CaptureRepositoryImpl`**
   * `AVCaptureSession` with `automaticallyConfiguresApplicationAudioSession = false`, front `builtInWideAngleCamera` (1080×1920 @ 30 fps, video connection mirrored), built-in mic.
   * `AVCaptureVideoDataOutput` + `AVCaptureAudioDataOutput` → `AVAssetWriter` (`RawMasterVideo.mov`, HEVC + AAC), `startSession(atSourceTime: firstVideoPTS)`; audio samples before `firstVideoPTS` dropped.
   * The same audio sample buffers feed `CrepePitchDetector` (1024-sample window at 16 kHz, 50 ms hop) → `PitchSample`. No second mic consumer.
5. **`ReferencePlaybackRepositoryImpl`** — `AVAudioEngine` + `AVAudioPlayerNode`, `scheduleSegment` started with `play(at: AVAudioTime(hostTime:))` a few ms in the future; converts host time to the capture clock (§7.1).
6. **`AudioRouteMonitorImpl`** — `AVAudioSession` route-change and interruption notifications.
7. **`SessionTakeLogRepositoryImpl`** — thread-safe in-memory storage.
8. **`VideoCompositionRepositoryImpl`** — §5.9: `AVMutableComposition` (1 video track, 2 vocal tracks A/B, 1 instrumental track), `AVMutableAudioMix` ramps/gains, `AVMutableVideoComposition` 1080×1920 preserving `preferredTransform`, `AVAssetExportSession` → `.mp4`.

---

## 7. Critical Technical Guardrails

### 7.1 Master Clock Synchronization (`CMTime`)
* NEVER use `Date()` or `Timer` elapsed time for cut points.
* Single reference clock: `captureSession.synchronizationClock`.
* **File time** = `captureTime − firstVideoPTS` (exact, because the writer session starts at `firstVideoPTS`).
* **Playback anchor:** `ReferencePlaybackRepository.play(from:)` schedules at host time `H`, converts with `CMSyncConvertTime(H, from: CMClockGetHostTimeClock(), to: synchronizationClock)`, and adds `latencyOffset`.
* `latencyOffset = AVAudioSession.outputLatency + ioBufferDuration + manualLatencyCalibration` (calibration default 0, editable in Debug Settings; mostly needed for Bluetooth).
* Capture time of reference time `r` = `anchor + (r − playFromReferenceTime)`. A take's `videoTimeRange` = file times of `[segment.start − 30 ms, segment.end + 30 ms]`.

### 7.2 Audio Session
* Category `.playAndRecord`, mode `.videoRecording`, options `[.allowBluetoothA2DP]` only (**no** `.defaultToSpeaker`, **no** `.allowBluetooth`/HFP).
* `setPreferredInput` → built-in mic, always (even with Bluetooth output).
* Record is blocked when the output route is the built-in speaker or receiver.

### 7.3 Portrait & Mirroring
* Copy `preferredTransform` to the composition video track; render size 1080×1920. Front camera mirrored at capture so preview, raw file, and final video all match.

### 7.4 Concurrency (Swift 5 mode, default MainActor isolation)
* With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, every type is MainActor-isolated by default. **All capture, DSP, playback, analysis, and composition types must be declared `nonisolated`** and run on their own serial queues/tasks.
* Realtime callbacks (sample buffer delegates, audio taps) must never call MainActor code or allocate heavily; results flow to the UI through `AsyncStream`.

### 7.5 Zero-Friction Demo
* "Load Demo Song" uses Track A (bundled stems + verified guide) or, until that asset exists, the synthesized fallback — so the whole pipeline is testable on a physical iPhone without external files.

---

## 8. Tunable Configuration (`PoCConfiguration`, editable in Debug Settings)

| Key | Default |
|---|---|
| `passThreshold` | 0.75 |
| `hitToleranceCents` | 50 |
| `noiseGateDBFS` | −40 |
| `pitchHop` | 0.05 s |
| `attackIgnore` | 0.10 s |
| `timingTolerance` | 0.10 s |
| `missedNoteThreshold` | 0.50 |
| `segmentGap` / `minSegment` / `maxSegment` | 0.8 s / 3.0 s / 8.0 s |
| `preRoll` | 2.0 s |
| `countdown` | 3 s |
| `crossfade` | 0.03 s |
| `vocalGain` / `instrumentalGain` | 1.0 / 0.8 |
| `manualLatencyCalibration` | 0 ms |
| `maxSessionDuration` | 15 min |
| `useCoreMLSeparation` | false (Track B flag) |

---

## 9. Error Handling
| Case | Behaviour |
|---|---|
| Camera / mic permission denied | Explanation screen + button to open Settings |
| DRM-protected or unreadable file | "This file can't be used. Try an MP3, M4A or WAV file." |
| Trimmed clip < 15 s | Trimmer prevents it |
| No vocal notes detected | "We couldn't find a vocal melody in this section. Try another part of the song." |
| Separation fails / too slow | Fall back to center-channel method + disclaimer |
| Output is speaker | Record disabled, "Plug in earphones to record" |
| Low storage | Record disabled, required space shown |
| Export fails | Error with Retry; raw file kept until a new session starts |

---

## 10. Acceptance Criteria (PoC)
1. Demo song: full flow (range test → import → record with at least one TRY AGAIN → export) runs on a physical iPhone without crashes.
2. Vocal vs instrumental sync in the final video: drift < 40 ms over the whole clip (wired earphones).
3. Cut accuracy: each take starts within ±1 frame of its planned file time.
4. No audible clicks at segment boundaries.
5. On-screen pitch trail latency < 100 ms.
6. Export time < 2× clip duration.
7. Partial export works after ending at segment N (1 ≤ N < M).
8. Track B spike produces a written result: model, size, processing time, memory, quality verdict, go/no-go.

---

## 11. Implementation Guide for AI Coding Agent
Implement the PoC so it runs end-to-end on a physical iPhone. Phase 2 extension points are marked with `// MARK:` (no `// TODO` stubs in Phase 1 paths). Use one folder per layer and one primary type per file:

```
poc-c6/
  App/            poc_c6App.swift, AppContainer.swift (dependency wiring)
  Domain/
    Entities/     TargetMIDINote, SongSegment, SeparatedStems, VocalRange, TranspositionPlan,
                  PreparedSong, PitchSample, PitchEvaluation, TakeAttemptLog,
                  CompingCompositionPlan, PoCConfiguration
    Repositories/ protocols from §6.3
    Contracts/    ContractValidation, DomainFixtures
    UseCases/     use cases from §6.4
  Shared/DSP/     CrepePitchDetector (live pitch, vocal range test, guide fallback)
  Shared/Storage/ SessionFiles (raw + final video locations, cleanup per session)
  Fakes/          fake implementations of every protocol (used until real ones land)
  Data/
    Separation/   Bundled, Synthesized, CenterChannel, CoreML (flagged)
    Audio/        BasicPitchAnalysisRepository, CrepeAnalysisRepository, AudioTranspositionRepositoryImpl,
                  ReferencePlaybackRepositoryImpl, AudioRouteMonitorImpl
    Capture/      CaptureRepositoryImpl
    Composition/  VideoCompositionRepositoryImpl
    Session/      SessionTakeLogRepositoryImpl, VocalRangeRepositoryImpl
  Presentation/
    VocalRange/ Import/ Recording/ Export/ Debug/
  Resources/      demo stems + guide (Track A, when available), BasicPitch.mlpackage
```

**Configuration notes:** the project uses `GENERATE_INFOPLIST_FILE = YES`, so permissions are build settings: `INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSMicrophoneUsageDescription`, `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`. No SPM dependencies in Phase 1.

**Suggested build order:**
1. Domain entities, protocols, use cases + unit tests for `SliceSegmentsUseCase`, `ComputeTranspositionUseCase`, `EvaluateSegmentUseCase`.
2. Synthesized demo + capture/playback with clock sync; verify cut accuracy (§10.2–10.3) before building UI polish.
3. Recording screen, piano roll, loop state machine.
4. Comping & mixdown, export screen.
5. Vocal range test, import/trim, center-channel fallback, transposition rendering.
6. Track A demo asset; Track B spike in parallel.

---

## 12. Team Ownership & Handoff Contracts

Mapped from the team's tech flow board (4 rows). Items marked *(proposed)* were not on the board and are a suggestion to confirm as a team.
Detailed per-person backlogs: `docs/backlog/ikzaz.md`, `docs/backlog/takin.md`, `docs/backlog/zildjian.md`. Working agreement (contract changes, git flow, conventions): `docs/COLLABORATION.md`. Handoff contracts are enforced in code by `poc-c6/Domain/Contracts/ContractValidation.swift`; run `./scripts/check-contracts.sh`.

### 12.1 Ownership

| Owner | Board rows | Scope (PRD sections) |
|---|---|---|
| **Ikzaz** | Row 1 — Import → Audio→MIDI → Guide | Vocal range test UI + persistence (§5.1); import, trim, disclaimer (§5.2); stem separation incl. center-channel fallback (§3); Basic Pitch + CREPE fallback, segmentation (§5.3); transposition plan + offline render (§5.4); `PrepareSongUseCase`. *(proposed)* Track A demo asset prep on Mac; Track B CoreML separation spike + written result; import error messages. |
| **Takin** | Row 2 — Record → Sing → Live feedback<br>Row 3 — Evaluate → Rewind / Continue | Capture + `AVAssetWriter` + master clock (§6.5.4, §7.1); reference playback with pre-roll (§6.5.5); audio session + earphone/route check (§7.2); live CREPE pitch (`CrepePitchDetector`, shared) + `TrackLivePitchUseCase`; recording screen + piano roll (§5.5); `EvaluateSegmentUseCase`, `LoopStateController` state machine, countdown, missed-note highlight (§5.6); `SessionTakeLogRepository`; End Session trigger + interruption detection (§5.7–5.8). |
| **Zildjian Vito** | Row 4 — End Record → Pick takes → Cut + stitch | `AutoCompingVideoUseCase`, `VideoCompositionRepositoryImpl`: timeline placement, A/B crossfade, instrumental mix, mirroring, export (§5.9); partial export (§5.7). *(proposed)* Export Preview screen (player, Share, Save to Photos); app shell, navigation, `AppContainer` wiring; synthesized demo fallback (§7.5) so everyone can test early; Debug Settings (§8); permission screens + error handling UI (§9); PRD owner / integrator. |
| **All (day 1)** | — | Agree and freeze Domain entities + repository protocols (§6.2–6.3) before parallel work starts. Changes after that go through a quick team review. |

### 12.2 Handoff contracts

| From → To | Contract | Must guarantee |
|---|---|---|
| Ikzaz → Takin | `PreparedSong` | `segments` tile the timeline with no holes (§5.3); `earphoneMixURL` already transposed by `semitoneShift`; target notes in original key + `transposition` provided |
| Ikzaz → Zildjian | `PreparedSong.instrumentalURL` | No original vocals; transposed by the **same** `semitoneShift` as the earphone mix; same start (t = 0) and duration as the trimmed song |
| Takin → Zildjian | Raw video URL + `passedTakesPrefix()` (`[TakeAttemptLog]`) | `videoTimeRange` in **file time** of `RawMasterVideo.mov`, aligned to what the user heard (latency compensated), incl. 30 ms handles; exactly one passed take per segment, prefix `1…N`; front camera already mirrored |
| Zildjian → all | `AppContainer` + synthesized demo | Fake/synthesized implementations of every protocol so each owner can run their part without the others being done |

### 12.3 Integration milestones
1. **M1 — Contracts frozen:** Domain entities + protocols merged; fakes available.
2. **M2 — Synthesized end-to-end:** synthesized demo → record → at least one TRY AGAIN → export. Proves clock sync and cutting (§10.2–10.4) before real audio analysis is plugged in.
3. **M3 — Real song end-to-end:** Track A demo with Basic Pitch guide, transposition, and instrumental mix.
4. **M4 — Track B verdict:** go/no-go for on-device separation of imported songs.

> Workload note: Takin's scope sits on the critical path (clock sync + realtime pitch). Plan to pair on §7.1 with Zildjian, since cut accuracy depends on it.
