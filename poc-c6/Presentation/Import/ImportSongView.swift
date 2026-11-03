//
//  ImportSongView.swift
//  poc-c6
//
//  Import screen (PRD §5.2): pick a song from Files, trim 15–60 s on a waveform while the synced
//  lyrics of that part light up (and follow a preview), prepare.
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
                              start: viewModel.selectionStart, length: viewModel.selectionLength,
                              playhead: viewModel.playbackTime)
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

            Button {
                viewModel.toggleSelectionPreview()
            } label: {
                Label(viewModel.isPlayingSelection ? "Stop" : "Play Selection",
                      systemImage: viewModel.isPlayingSelection ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            LyricsPanel(viewModel: viewModel)
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
    /// Position of the selection preview, if playing.
    var playhead: TimeInterval?

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
            if let playhead {
                let x = size.width * playhead / duration
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.primary))
            }
        }
        .accessibilityLabel("Selected \(Int(length)) seconds starting at \(Int(start)) seconds")
    }
}

/// Synced lyrics: lines in the chosen part are lit, the rest dimmed; during the preview the
/// current line is bold and its words fill in as they are sung. Manual search when none match.
private struct LyricsPanel: View {
    @Bindable var viewModel: ImportSongViewModel

    var body: some View {
        Group {
            switch viewModel.lyrics {
            case .idle:
                Color.clear
            case .loading:
                ProgressView("Finding lyrics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .found(let song):
                lines(song)
            case .notFound:
                search(.lyricsNotFound)
            case .failed(let error):
                search(error)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func lines(_ song: SongLyrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(song.lines) { line in
                            lineText(line).id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { scroll(proxy, to: viewModel.firstSelectedLineID, anchor: .top) }
                .onChange(of: viewModel.firstSelectedLineID) { _, id in scroll(proxy, to: id, anchor: .top) }
                .onChange(of: viewModel.activeLineID) { _, id in scroll(proxy, to: id, anchor: .center) }
            }
            Text("Lyrics: \(song.matchedTitle) – \(song.matchedArtist), from LRCLIB. Timing may be slightly off.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func lineText(_ line: LyricLine) -> some View {
        let selected = viewModel.isInSelection(line)
        let active = viewModel.activeLineID == line.id
        let text: Text
        if active, let time = viewModel.playbackTime {
            // Karaoke fill: words already reached are tinted.
            text = line.words.reduce(Text("")) { result, word in
                result + Text(word.text + " ").foregroundStyle(time >= word.start ? Color.accentColor : Color.primary)
            }
        } else {
            text = Text(line.text)
        }
        return text
            .font(active ? .body.bold() : .body)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .opacity(selected ? 1 : 0.45)
            .animation(.easeOut(duration: 0.15), value: active)
    }

    private func search(_ error: UserFacingError) -> some View {
        ScrollView {
            searchForm(error)
        }
    }

    private func searchForm(_ error: UserFacingError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: error.systemImage)
                .font(.subheadline.bold())
            Text(error.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Song title", text: $viewModel.lyricsTitle)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { viewModel.searchLyrics() }
            TextField("Artist (optional)", text: $viewModel.lyricsArtist)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { viewModel.searchLyrics() }
            Button("Search Lyrics") { viewModel.searchLyrics() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: Int?, anchor: UnitPoint) {
        guard let id else { return }
        withAnimation { proxy.scrollTo(id, anchor: anchor) }
    }
}
