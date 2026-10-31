# SRS & PRD: iOS Song Cover Recording & Auto-Comping PoC

## 1. Project Overview & Core Value Proposition
Build an iOS 18+ Proof of Concept (PoC) application in Swift & SwiftUI for independent Gen Z song cover creators.
The app eliminates repetitive trial-and-error recording (retaking the entire song from the beginning when making a single pitch mistake) through 4 core mechanisms:
1. **Reference Audio-to-MIDI & Auto-Segmentation:** Importing a full reference song (15–60s clip), isolating/extracting the vocal melody into target MIDI notes, and automatically slicing the song into phrase segments based on breathing pauses/silences.
2. **Continuous Camera Recording + Synced Reference Playback + Live Piano Roll:** Recording a single, uninterrupted 9:16 vertical video (`RawMasterVideo.mov`) while playing the current segment's reference audio (via earphones) and rendering a transparent real-time Piano Roll overlay in the center of the screen.
3. **Segment Evaluation & Seamless Auto-Rewind Loop:** Evaluating pitch accuracy at the end of each phrase segment. If the score is `< 75%` (`BELUM`), highlight missed notes, trigger a `3.. 2.. 1..` visual countdown, and rewind the Piano Roll playhead + reference audio to the start of the current segment WITHOUT pausing the camera recording. If `>= 75%` (`SUDAH`), log the valid video `CMTimeRange` and advance to the next segment.
4. **Automated Vocal/Video Comping (Auto-Cut & Stitch):** Once all segments pass, automatically slice the uninterrupted `RawMasterVideo.mov` using the saved `CMTimeRange` logs, discard failed attempts and countdown gaps, apply a 30ms audio crossfade between segments, and export a single `FinalCoverVideo.mp4` ready for social media upload.

---

## 2. Technical Stack & "Start Small, Scale Modularly" Strategy
* **Target OS & Language:** iOS 18.0+, Swift 6 / Swift 5.10, SwiftUI with `@Observable` macro (Observation framework).
* **Architecture:** Clean Architecture (`Presentation Layer` -> `Domain Layer` -> `Data & Infrastructure Layer`) using Protocol-Oriented Programming so implementations can be swapped easily.
* **Phased Dependency Strategy (Start Small + SPM Ready):**
  * **Phase 1 (Immediate PoC / Start Small Native):** 
    * Use Apple's native `AVFoundation`, `AVFAudio`, and `Accelerate` (`vDSP` autocorrelation / YIN pitch estimation + band-pass filtering for vocal frequency range `80 Hz – 1100 Hz`) so the project compiles and runs End-to-End immediately with zero external setup friction.
  * **Phase 2 (SPM Drop-in Upgrade via Repository Protocols):**
    * Structure the `AudioAnalysisRepository` and `CaptureAndPlaybackRepository` protocols to support **Swift Package Manager (SPM)** packages:
      * `AudioKit` & `SoundpipeAudioKit` (for `PitchTap` real-time tracking).
      * `CoreML` (for vocal stem separation / Spleeter / Demucs + Spotify `BasicPitch` `.mlmodel` for polyphonic full-song to MIDI extraction).

---

## 3. End-to-End User & System Workflow
1. **Step 1 (Import & Trim):** User selects a reference song (full mix with vocals and instruments) from Files/Photos or loads a built-in demo track, then trims it to 15–60 seconds.
2. **Step 2 (Offline Extraction & Slicing):** System processes the trimmed audio, extracts dominant vocal frequencies ($F_0$), converts them into `TargetMIDINote` blocks, and splits the timeline into `[SongSegment]` chunks whenever a silence/pause $> 0.8\text{s}$ is detected.
3. **Step 3 (Start Uninterrupted Session):** User wears earphones and taps "Record". Front camera (9:16) and microphone start recording into `RawMasterVideo.mov` continuously.
4. **Step 4 (Sing & Live Visual Feedback):** Reference audio for Segment 1 plays in the user's earphones. The semi-transparent Piano Roll in the center of the screen scrolls horizontally. User's live vocal pitch is drawn over the MIDI blocks (Green = within $\pm 50\text{ cents}$, Red = off-pitch).
5. **Step 5 (Segment Evaluation & Auto-Loop):**
   * At the end of Segment $N$, system calculates hit percentage.
   * **Branch A (`BELUM` / Score < 75%):** System marks the attempt's `CMTimeRange` as `.buang`, highlights the missed MIDI bars in red, shows a `3.. 2.. 1..` countdown overlay, seeks the reference audio player back to `segment.audioStartTime`, and rewinds the Piano Roll playhead to re-record Segment $N$ while `AVCaptureSession` keeps rolling.
   * **Branch B (`SUDAH` / Score >= 75%):** System marks the attempt's `CMTimeRange` as `.simpan`, flashes a green pass indicator, and advances the playhead to Segment $N+1$.
6. **Step 6 (Auto-Comping & Export):** Once the final segment passes (or user ends recording), `AVCaptureSession` stops. System filters all `.simpan` time ranges, splices `RawMasterVideo.mov` using `AVMutableComposition`, applies a $30\text{ms}$ audio crossfade between cuts, exports `FinalCoverVideo.mp4`, and presents the preview/share screen.

---

## 4. System Design & Clean Architecture Blueprint

### A. Presentation Layer (`Views` & `@Observable ViewModels`)
1. **`AudioImportView` & `PrepViewModel`**
   * `fileImporter` / `PhotosPicker` to load a reference song (`.mp3`, `.m4a`, `.wav`, or `.mov`) + a "Load Bundled Demo Track" button.
   * Waveform trimmer UI to crop a 15–60 second target section.
   * Displays processing state: *"Isolating Vocal Melody & Generating Segments..."*
2. **`RecordingPianoRollView` & `RecordingViewModel`**
   * **Full-Screen 9:16 Vertical Camera Preview (`AVCaptureVideoPreviewLayer`).**
   * **Center Overlay Piano Roll (`SwiftUI Canvas` + `TimelineView`):** Semi-transparent horizontal pitch lane positioned in the **center of the screen** so the singer's eyes stay focused near the front camera lens.
   * Renders target MIDI blocks and the user's live vocal pitch trail (Green = within $\pm 50\text{ cents}$ tolerance, Red = off-pitch).
3. **`CorrectionOverlayView` & `LoopStateController`**
   * Triggered when a segment finishes.
   * **State `BELUM` (Score < 75%):** Flashes missed MIDI blocks in red, shows a `3.. 2.. 1..` countdown overlay, and rewinds the Piano Roll playhead to the start of the active segment while camera recording continues.
   * **State `SUDAH` (Score >= 75%):** Flashes green badge and smoothly transitions playhead to `segmentIndex + 1`.
4. **`ExportPreviewView` & `CompingViewModel`**
   * Displays stitching progress bar and a native `VideoPlayer` playing the final auto-comped `.mp4` cover with a `ShareLink` button and "Save to Photos" action.

---

### B. Domain Layer (`Entities`, `Use Cases`, & `Repository Protocols`)

#### 1. Domain Entities (Core Data Contracts)
```swift
import Foundation
import CoreMedia

public struct TargetMIDINote: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let midiNote: Int           // e.g., 60 = C4
    public let startTime: TimeInterval // Relative to trimmed reference audio (seconds)
    public let duration: TimeInterval
}

public struct SongSegment: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let index: Int
    public let audioStartTime: TimeInterval
    public let audioDuration: TimeInterval
    public let targetNotes: [TargetMIDINote]
}

public struct LivePitchFrame: Sendable {
    public let masterRecordingTimestamp: CMTime
    public let detectedFrequency: Float
    public let detectedMIDINote: Float
    public let centDeviation: Float
    public let isHit: Bool // true if abs(centDeviation) <= 50 cents
}

public enum SegmentAttemptStatus: String, Sendable {
    case simpan = "SUDAH"
    case buang = "BELUM"
}

public struct TakeAttemptLog: Identifiable, Sendable {
    public let id = UUID()
    public let segmentIndex: Int
    public let attemptNumber: Int
    public let videoTimeRange: CMTimeRange // Exact start & end CMTime inside RawMasterVideo.mov
    public let accuracyScore: Float        // 0.0 to 1.0
    public let status: SegmentAttemptStatus
}

public struct CompingCompositionPlan: Sendable {
    public let rawVideoURL: URL
    public let validTakes: [TakeAttemptLog] // Ordered 1 passed take per segmentIndex
    public let crossfadeDuration: CMTime    // Default: 30ms (0.03s)
}
```

#### 2. Domain Repository Protocols
```swift
import Foundation
import AVFoundation
import CoreMedia

public protocol AudioAnalysisRepository: Sendable {
    func extractVocalGuideNotes(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> [TargetMIDINote]
}

public protocol CaptureAndPlaybackRepository: AnyObject {
    var captureSession: AVCaptureSession { get }
    var pitchFrameStream: AsyncStream<LivePitchFrame> { get }
    
    func prepareSession(referenceAudioURL: URL) throws
    func startContinuousRecording() async throws -> URL
    func playReferenceSegment(startTime: TimeInterval, duration: TimeInterval)
    func pauseReferencePlayback()
    func currentRecordingTime() -> CMTime
    func stopContinuousRecording() async throws -> URL
}

public protocol SessionTakeLogRepository: AnyObject {
    func logAttempt(_ attempt: TakeAttemptLog)
    func getAllAttempts() -> [TakeAttemptLog]
    func getValidAttemptsPerSegment() -> [TakeAttemptLog]
    func clearLogs()
}

public protocol VideoCompositionRepository: Sendable {
    func stitchAndExport(plan: CompingCompositionPlan) async throws -> URL
}
```

#### 3. Domain Use Cases
* **`ExtractGuideAndSliceUseCase`**
  * Calls `AudioAnalysisRepository.extractVocalGuideNotes(...)`.
  * Converts frequency $f$ to MIDI note number using:
    $$M = 69 + 12 \log_2\left(\frac{f}{440}\right)$$
  * Groups contiguous notes into `[SongSegment]` whenever a gap $> 0.8\text{s}$ is detected (enforcing a minimum segment length of $3.0\text{s}$ and maximum of $8.0\text{s}$).
* **`TrackLivePitchUseCase`**
  * Consumes microphone frequency frames every $50\text{ms}$, applies an RMS noise gate ($> -40\text{ dB}$), compares the user's float MIDI note against the active `TargetMIDINote` at the current segment timestamp, computes cent deviation:
    $$\Delta_{\text{cents}} = 100 \times \left(M_{\text{user}} - M_{\text{target}}\right)$$
  * Marks `isHit = abs(centDeviation) <= 50.0`.
* **`EvaluateSegmentUseCase`**
  * At the end of a segment's duration, calculates:
    $$\text{Accuracy} = \frac{\text{Count}(\text{isHit} == \text{true})}{\text{Total Active Frames}}$$
  * Logs a `TakeAttemptLog` with the exact `CMTimeRange(start: segmentVideoStartCMTime, end: segmentVideoEndCMTime)`.
  * Returns `.simpan` (`SUDAH`) if $\text{Accuracy} \ge 0.75$, else `.buang` (`BELUM`).
* **`AutoCompingVideoUseCase`**
  * Queries `SessionTakeLogRepository.getValidAttemptsPerSegment()`, builds a `CompingCompositionPlan` with `crossfadeDuration = CMTime(seconds: 0.03, preferredTimescale: 600)`, and invokes `VideoCompositionRepository.stitchAndExport(plan:)`.

---

### C. Data & Infrastructure Layer (`Repositories` & `Native/SPM Frameworks`)
1. **`AudioAnalysisRepositoryImpl`**
   * Uses `AVAssetReader` to read PCM float samples from the reference song.
   * **Phase 1 Native DSP:** Applies a biquad band-pass filter ($80\text{ Hz} - 1100\text{ Hz}$ via `vDSP`) to attenuate bass/drums and extract dominant vocal $F_0$ via windowed autocorrelation/YIN every $40\text{ms}$, quantizing stable pitch regions ($\ge 120\text{ms}$) into `TargetMIDINote` items.
   * **Phase 2 SPM Hook:** Add clear `// MARK: - SPM CoreML BasicPitch & Vocal Separation` extension point.
2. **`CaptureAndPlaybackRepositoryImpl`**
   * Configures `AVAudioSession.sharedInstance()` with category `.playAndRecord`, mode `.measurement` or `.videoRecording`, and options `[.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]`.
   * Configures `AVCaptureSession` with front camera (`builtInWideAngleCamera`) and audio input, writing to a temporary `RawMasterVideo.mov` via `AVCaptureMovieFileOutput`.
   * Runs `AVAudioEngine` (or `AVAudioPlayer` for reference track + `AVAudioEngine` input node tap for mic pitch detection) to stream live pitch frames while playing the reference song segment.
3. **`SessionTakeLogRepositoryImpl`**
   * Thread-safe in-memory storage of `[TakeAttemptLog]`.
4. **`VideoCompositionRepositoryImpl`**
   * Creates `AVMutableComposition` with video and audio tracks.
   * Loops over `plan.validTakes` and calls `insertTimeRange(take.videoTimeRange, of: rawAsset, at: insertionCursor)` to splice only passed segments sequentially.
   * Applies `AVMutableVideoComposition` / `preferredTransform` to preserve 9:16 portrait orientation.
   * Configures `AVMutableAudioMix` with `AVMutableAudioMixInputParameters` (`setVolumeRamp`) for $30\text{ms}$ crossfades at segment boundaries to prevent clicks/pops.
   * Exports to `FinalCoverVideo.mp4` via `AVAssetExportSession(asset:presetName: AVAssetExportPresetHighestQuality)`.

---

## 5. Critical Edge Cases & Technical Guardrails
1. **Master Clock Synchronization (`CMTime`):**
   * NEVER use `Date()` or `Timer` elapsed seconds to calculate video cut points.
   * Record `recordingStartCMTime = CMClockGetTime(CMClockGetHostTimeClock())` inside `fileOutput(_:didStartRecordingTo:from:)`.
   * Calculate every segment's `videoStartTime` and `videoEndTime` by subtracting `recordingStartCMTime` from the current `CMClockGetHostTimeClock()` time.
2. **Portrait Video Orientation (9:16):**
   * Copy `rawVideoTrack.preferredTransform` to the `AVMutableCompositionTrack` so the stitched `.mp4` video does not render rotated 90 degrees sideways.
3. **Zero-Friction Demo Mode:**
   * Provide a built-in "Load Demo Song & Guide" button that generates a playable reference audio file (e.g., synthesized melody or bundled audio) and pre-populated `[SongSegment]` notes so the entire recording, auto-rewind, and video-stitching pipeline can be tested immediately on a physical iPhone without external MP3 files.

---

## 6. Step-by-Step Implementation Prompt for AI Coding Agent
Please implement this PoC in complete, production-ready Swift files without placeholders or `// TODO` stubs:
1. **File 1 (`DomainLayer.swift`):** All Domain Entities, Repository Protocols, and the 4 Use Cases (`ExtractGuideAndSliceUseCase`, `TrackLivePitchUseCase`, `EvaluateSegmentUseCase`, `AutoCompingVideoUseCase`).
2. **File 2 (`DataLayer.swift`):** Complete implementations of `AudioAnalysisRepositoryImpl` (including a synthetic demo audio generator fallback), `CaptureAndPlaybackRepositoryImpl` (`AVCaptureSession` + `AVAudioEngine` real-time pitch detector + reference segment player), `SessionTakeLogRepositoryImpl`, and `VideoCompositionRepositoryImpl` (`AVMutableComposition` splicing + audio ramp).
3. **File 3 (`ViewModels.swift`):** `@Observable` ViewModels (`PrepViewModel`, `RecordingViewModel`, `LoopStateController`, `CompingViewModel`) coordinating the end-to-end state machine.
4. **File 4 (`PresentationViews.swift`):** Main Navigation flow, `AudioImportView`, `RecordingPianoRollView` (9:16 camera preview + center transparent `Canvas` Piano Roll + `CorrectionOverlayView` countdown), and `ExportPreviewView` (`VideoPlayer` + Share/Save).
5. **File 5 (`Configuration.md`):** Required `Info.plist` keys (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`) and instructions for adding `AudioKit` via SPM.
