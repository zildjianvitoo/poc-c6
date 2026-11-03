//
//  ImportSongView.swift
//  poc-c6
//
//  Import screen (PRD §5.2): pick a song from Files, trim 15–60 s on a waveform, prepare.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportSongView: View {
    @State private var viewModel: ImportSongViewModel
    @State private var picking = false
    let onUseDemo: () -> Void

    init(viewModel: ImportSongViewModel, onUseDemo: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onUseDemo = onUseDemo
    }

    /// PRD §5.2: mp3, m4a, wav, and the audio track of a video.
    private static let types: [UTType] = [.mp3, .mpeg4Audio, .wav, .audio, .movie]

    var body: some View {
        VStack(spacing: 20) {
            switch viewModel.status {
            case .idle:
                picker
            case .loading:
                Spacer()
                ProgressView("Opening song…")
                Spacer()
            case .trimming(let audio):
                trimmer(audio)
            case .preparing(let step):
                preparing(step)
            case .failed(let error):
                Spacer()
                ErrorStateView(error: error, actionTitle: "Choose Another Song") {
                    viewModel.reset()
                    picking = true
                }
                Spacer()
            }
        }
        .padding()
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { viewModel.picked($0) }
        .onDisappear { viewModel.cancelPreparation() }
    }

    private var picker: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Pick a Song")
                .font(.largeTitle.bold())
            Text("Choose a song file you own (MP3, M4A, WAV or a video). You'll pick 15–60 seconds to cover.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Choose from Files") { picking = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Use Demo Song", action: onUseDemo)
        }
    }

    private func trimmer(_ audio: ImportedAudio) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(audio.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text("Pick the part you want to sing")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            WaveformSelection(waveform: audio.waveform, duration: audio.duration,
                              start: viewModel.selectionStart, length: viewModel.selectionLength)
                .frame(height: 96)

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Start", value: time(viewModel.selectionStart))
                Slider(value: $viewModel.selectionStart, in: 0...max(0.1, viewModel.maximumStart))
                    .disabled(viewModel.maximumStart <= 0)
                LabeledContent("Length", value: time(viewModel.selectionLength))
                Slider(value: $viewModel.selectionLength,
                       in: ImportSongViewModel.minimumLength...max(ImportSongViewModel.minimumLength + 0.1, viewModel.maximumLengthForStart))
                    .disabled(viewModel.maximumLengthForStart <= ImportSongViewModel.minimumLength)
            }
            .monospacedDigit()

            Spacer()
            disclaimer
            Button("Prepare Song") { viewModel.prepareSelection() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Choose Another Song") { picking = true }
        }
    }

    private func preparing(_ step: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(step)
                .font(.headline)
            Text("This can take a little while for a long selection.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            disclaimer
            Button("Cancel", role: .cancel) { viewModel.cancelPreparation() }
        }
    }

    /// PRD §5.2 disclaimers (Phase 1 guide + basic vocal removal).
    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("**Experimental (Phase 1):** The pitch guide is extracted from the original song and may be inaccurate, especially in busy sections.")
            } icon: {
                Image(systemName: "flask")
            }
            Label {
                Text("The singer is removed from the background music on your iPhone. Some original vocals may still be audible.")
            } icon: {
                Image(systemName: "waveform.badge.minus")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }
}

/// Waveform bars with the selected 15–60 s highlighted.
private struct WaveformSelection: View {
    let waveform: [Float]
    let duration: TimeInterval
    let start: TimeInterval
    let length: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard !waveform.isEmpty, duration > 0 else { return }
            let barWidth = size.width / CGFloat(waveform.count)
            let selection = (start / duration)...((start + length) / duration)
            for (index, level) in waveform.enumerated() {
                let position = (Double(index) + 0.5) / Double(waveform.count)
                let height = max(2, CGFloat(level) * size.height)
                let rect = CGRect(x: CGFloat(index) * barWidth, y: (size.height - height) / 2,
                                  width: max(1, barWidth - 1), height: height)
                context.fill(Path(rect), with: .color(selection.contains(position) ? .accentColor : .secondary.opacity(0.35)))
            }
            let x0 = size.width * start / duration, x1 = size.width * (start + length) / duration
            context.stroke(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)),
                           with: .color(.accentColor), lineWidth: 2)
        }
        .accessibilityLabel("Selected \(Int(length)) seconds starting at \(Int(start)) seconds")
    }
}
