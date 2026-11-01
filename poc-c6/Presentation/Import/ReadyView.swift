//
//  ReadyView.swift
//  poc-c6
//
//  Ready screen (PRD §5.2 step 3): segment count, chosen transposition, earphone reminder.
//

import SwiftUI

struct ReadyView: View {
    let song: PreparedSong
    let onRecord: () -> Void
    let onChooseAnother: () -> Void

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
            if song.separationMethod == .centerChannelCancellation {
                Text("Background music uses basic vocal removal. Some original vocals may still be audible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Label("Use earphones so the song doesn't leak into the microphone.", systemImage: "headphones")
                .font(.footnote)
            Spacer()
            Button("Record", action: onRecord)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Choose Another Song", action: onChooseAnother)
        }
        .padding()
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
