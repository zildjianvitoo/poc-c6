//
//  ReadyView.swift
//  poc-c6
//
//  Ready screen (PRD §5.2 step 3): segment count, chosen transposition, earphone reminder.
//

import SwiftUI

struct ReadyView: View {
    let song: PreparedSong
    let previewer: any AudioPreviewing
    let onRecord: () -> Void
    let onChooseAnother: () -> Void
    @State private var playing: Track?

    enum Track { case instrumental, original }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Ready to Record")
                .font(.largeTitle.bold())
            VStack(spacing: 8) {
                LabeledContent("Segments", value: "\(song.segments.count)")
                LabeledContent("Length", value: Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)))
                LabeledContent("Key", value: keyText)
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            previewButtons
            if song.separationMethod == .centerChannelCancellation || song.separationMethod == .coreML {
                Text(song.separationMethod == .coreML
                     ? "Background music was separated on your iPhone. Faint original vocals may remain."
                     : "Background music uses basic vocal removal. Some original vocals may still be audible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Label("Use earphones so the song doesn't leak into the microphone.", systemImage: "headphones")
                .font(.footnote)
            Spacer()
            Button("Record") {
                previewer.stop()
                onRecord()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Choose Another Song") {
                previewer.stop()
                onChooseAnother()
            }
        }
        .padding()
        .onDisappear { previewer.stop() }
    }

    /// Listen to the background music alone (what ends up in the cover) or the original.
    private var previewButtons: some View {
        HStack(spacing: 12) {
            previewButton("Background", systemImage: "music.note", track: .instrumental, url: song.instrumentalURL)
            previewButton("Original", systemImage: "music.mic", track: .original, url: song.earphoneMixURL)
        }
    }

    private func previewButton(_ title: String, systemImage: String, track: Track, url: URL) -> some View {
        Button {
            if playing == track {
                previewer.stop()
                playing = nil
            } else if (try? previewer.play(url)) != nil {
                playing = track
            }
        } label: {
            Label(playing == track ? "Stop" : title, systemImage: playing == track ? "stop.fill" : systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// "−3 semitones · 1 octave down" style summary of the transposition.
    private var keyText: String {
        let plan = song.transposition
        guard plan.totalSemitones != 0 else { return "Original key" }
        var parts: [String] = []
        if plan.semitoneShift != 0 {
            parts.append("\(plan.semitoneShift > 0 ? "+" : "−")\(abs(plan.semitoneShift)) semitones")
        }
        if plan.octaveShift != 0 {
            parts.append("\(abs(plan.octaveShift)) octave \(plan.octaveShift > 0 ? "up" : "down")")
        }
        return parts.joined(separator: " · ")
    }
}
