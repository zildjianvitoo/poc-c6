//
//  RecordingView.swift
//  poc-c6
//
//  Recording screen (PRD §5.5): full-screen front camera, 9:16 frame guide, centre piano roll,
//  top bar with progress and End Session, correction overlay and countdown.
//

import SwiftUI
import UIKit

struct RecordingView: View {
    @State private var viewModel: RecordingViewModel
    @State private var confirmsEnd = false
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: RecordingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer
            content
        }
        .task { await viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            // PRD §5.8: leaving the app stops the session; ask for time to finalize the file.
            let task = UIApplication.shared.beginBackgroundTask(withName: "Finalize recording")
            Task {
                await viewModel.interrupt()
                UIApplication.shared.endBackgroundTask(task)
            }
        }
        .confirmationDialog("End session?", isPresented: $confirmsEnd, titleVisibility: .visible) {
            if viewModel.passedCount > 0 {
                Button("Export \(viewModel.passedCount) of \(viewModel.segmentCount)") {
                    Task { await viewModel.finish() }
                }
            }
            Button("Discard", role: .destructive) {
                Task { await viewModel.discard() }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text(viewModel.passedCount > 0
                 ? "Your cover will use the \(viewModel.passedCount) segments you passed."
                 : "No segment has passed yet.")
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private var cameraLayer: some View {
        // Shown once the camera is configured, so the preview connection exists and can be oriented.
        if let source = viewModel.previewSource, viewModel.status != .starting {
            CameraPreviewView(session: source.previewSession, device: source.previewDevice)
                .ignoresSafeArea()
            FrameGuide()
                .ignoresSafeArea()
        } else {
            // Simulator / fakes: there is no camera, the loop still runs.
            Label("No camera preview", systemImage: "video.slash")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .starting:
            ProgressView("Getting ready…")
                .tint(.white)
                .foregroundStyle(.white)
        case .recording:
            recordingOverlay
        case .finishing:
            ProgressView("Saving your recording…")
                .tint(.white)
                .foregroundStyle(.white)
        case .blocked(let error):
            stoppedState(error, primary: ("Try Again", { Task { await viewModel.start() } }))
        case .interrupted(let error), .failed(let error):
            stoppedState(error, primary: viewModel.passedCount > 0
                         ? ("Export \(viewModel.passedCount) of \(viewModel.segmentCount)", { viewModel.exportAfterInterruption() })
                         : nil)
        }
    }

    private var recordingOverlay: some View {
        VStack(spacing: 12) {
            topBar
            if viewModel.isSpeakerTest {
                Label("Speaker test mode: scores are not reliable", systemImage: "speaker.wave.3")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.purple.opacity(0.85), in: .capsule)
            }
            #if DEBUG
            pitchDebug
            #endif
            if viewModel.showsBluetoothWarning {
                Label("Wired earphones give the best sync", systemImage: "airpodspro")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.85), in: .capsule)
            }
            Spacer()
            PianoRollView(notes: pianoRollNotes,
                          trail: viewModel.trail,
                          focusMIDI: focusMIDI,
                          songTime: viewModel.displaySongTime,
                          dimmedBefore: viewModel.loop.phase == .preRoll ? viewModel.loop.currentSegment?.audioStartTime : nil,
                          isPaused: confirmsEnd)
                .frame(height: 180)
                .padding(.horizontal)
            phaseInfo
                .frame(height: 140)
            Spacer()
        }
        .foregroundStyle(.white)
    }

    /// Debug builds: is the microphone heard, and how often? 20 samples/s is the target (50 ms hop).
    private var pitchDebug: some View {
        let stats = viewModel.pitchStats
        let level = stats.lastLevelDB.isFinite ? "\(Int(stats.lastLevelDB)) dB" : "silent"
        return Text("Mic \(stats.lastNote ?? "—") · \(stats.samplesPerSecond)/s · voiced \(stats.voicedPercent)% · \(level)")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: .capsule)
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.progressTitle)
                    .font(.headline.monospacedDigit())
                Text("Phase 1")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.2), in: .capsule)
            }
            Spacer()
            Button("End Session") { confirmsEnd = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding()
        .background(.black.opacity(0.4))
    }

    @ViewBuilder
    private var phaseInfo: some View {
        switch viewModel.loop.phase {
        case .countdown(let remaining):
            Text("\(remaining)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        case .preRoll:
            Label("Listen…", systemImage: "ear")
                .font(.title3.bold())
        case .showingResult:
            if let result = viewModel.lastResult {
                CorrectionOverlayView(passed: result.passed, score: Double(result.score),
                                      missedNotes: missedNoteNames(result))
                    .padding(.horizontal)
            }
        case .singing:
            if let result = viewModel.lastResult, result.passed {
                Label("Segment \(result.segmentIndex + 1) passed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }
        case .idle, .ended:
            EmptyView()
        }
    }

    private func stoppedState(_ error: UserFacingError, primary: (String, () -> Void)?) -> some View {
        VStack(spacing: 16) {
            ErrorStateView(error: error, actionTitle: primary?.0, action: primary?.1)
            Button("Start Over", role: .destructive) {
                Task { await viewModel.discard() }
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.black.opacity(0.7), in: .rect(cornerRadius: 20))
        .padding()
    }

    // MARK: - Data for the piano roll

    private var pianoRollNotes: [PianoRollView.Note] {
        let missed = viewModel.loop.phase == .showingResult ? Set(viewModel.lastResult?.missedNoteIDs ?? []) : []
        let plan = viewModel.song.transposition
        return viewModel.song.segments.flatMap(\.targetNotes).map {
            PianoRollView.Note(id: $0.id, midi: plan.transposed($0), start: $0.startTime, end: $0.endTime,
                               isMissed: missed.contains($0.id))
        }
    }

    private var focusMIDI: [Int] {
        guard let segment = viewModel.loop.currentSegment else { return [] }
        let notes = segment.targetNotes.isEmpty
            ? viewModel.song.segments.flatMap(\.targetNotes)
            : segment.targetNotes
        return notes.map(viewModel.song.transposition.transposed)
    }

    private func missedNoteNames(_ result: RecordingViewModel.SegmentResult) -> [String] {
        let plan = viewModel.song.transposition
        return viewModel.song.segments[result.segmentIndex].targetNotes
            .filter { result.missedNoteIDs.contains($0.id) }
            .map { PitchMath.noteName(midi: plan.transposed($0)) }
    }
}

/// Darkens everything outside the centred 9:16 area that ends up in the video.
private struct FrameGuide: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let width = min(size.width, size.height * 9 / 16)
            let height = width * 16 / 9
            let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
            Rectangle()
                .path(in: rect)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
