//
//  PianoRollView.swift
//  poc-c6
//
//  Centre lane of the recording screen (PRD §5.5): target notes scroll past a playhead at 25%,
//  ~4 s visible, vertical range fitted to the current segment ± 3 semitones, and the user's
//  pitch trail in green (within tolerance) or red. UI only — never part of the recording.
//

import SwiftUI

struct PianoRollView: View {
    struct Note: Identifiable {
        let id: UUID
        /// Transposed MIDI note, as the user should sing it.
        let midi: Int
        let start: TimeInterval
        let end: TimeInterval
        var isMissed = false
    }

    static let visibleDuration: TimeInterval = 4
    static let playheadPosition = 0.25
    static let rangePadding = 3

    let notes: [Note]
    let trail: [RecordingViewModel.TrailPoint]
    /// Notes of the current segment, used to fit the vertical range.
    let focusMIDI: [Int]
    let songTime: () -> TimeInterval?
    /// Stops redrawing (e.g. while a dialog is open) to leave CPU time for audio and video.
    var isPaused = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { _ in
            Canvas { context, size in
                draw(in: &context, size: size, now: songTime())
            }
        }
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 12))
        .accessibilityLabel("Piano roll")
    }

    private var midiRange: ClosedRange<Int> {
        let low = (focusMIDI.min() ?? 60) - Self.rangePadding
        let high = (focusMIDI.max() ?? 60) + Self.rangePadding
        return low...max(high, low + 2 * Self.rangePadding)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval?) {
        let range = midiRange
        let rows = CGFloat(range.count)
        let rowHeight = size.height / rows
        let labelWidth: CGFloat = 30
        let laneWidth = size.width - labelWidth
        let playheadX = labelWidth + laneWidth * Self.playheadPosition
        let current = now ?? 0
        func x(_ time: TimeInterval) -> CGFloat {
            playheadX + CGFloat((time - current) / Self.visibleDuration) * laneWidth
        }
        func y(_ midi: Double) -> CGFloat {
            size.height - (CGFloat(midi - Double(range.lowerBound)) + 0.5) * rowHeight
        }

        // Rows and note names on the left edge.
        for midi in range {
            let rowY = y(Double(midi))
            if midi % 12 == 0 || midi == range.lowerBound || midi == range.upperBound {
                context.draw(Text(PitchMath.noteName(midi: midi)).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7)),
                             at: CGPoint(x: labelWidth / 2, y: rowY))
            }
            var line = Path()
            line.move(to: CGPoint(x: labelWidth, y: rowY))
            line.addLine(to: CGPoint(x: size.width, y: rowY))
            context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }

        guard now != nil else { return }
        context.clip(to: Path(CGRect(x: labelWidth, y: 0, width: laneWidth, height: size.height)))

        // Target notes.
        let windowStart = current - Self.visibleDuration * Self.playheadPosition
        let windowEnd = windowStart + Self.visibleDuration
        for note in notes where note.end > windowStart && note.start < windowEnd && range.contains(note.midi) {
            let rect = CGRect(x: x(note.start), y: y(Double(note.midi)) - rowHeight * 0.4,
                              width: max(2, x(note.end) - x(note.start)), height: rowHeight * 0.8)
            let color: Color = note.isMissed ? .red : (note.start <= current && current < note.end ? .white : .white.opacity(0.6))
            context.fill(Path(roundedRect: rect, cornerRadius: min(4, rowHeight * 0.3)), with: .color(color.opacity(0.85)))
        }

        // Pitch trail: consecutive voiced points are joined; unvoiced breaks the line.
        let maxJoin = 0.12
        for (previous, point) in zip(trail, trail.dropFirst()) {
            guard let a = previous.midi, let b = point.midi, point.songTime - previous.songTime <= maxJoin else { continue }
            var segment = Path()
            segment.move(to: CGPoint(x: x(previous.songTime), y: y(Double(a))))
            segment.addLine(to: CGPoint(x: x(point.songTime), y: y(Double(b))))
            context.stroke(segment, with: .color(point.isHit ? .green : .red), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // Playhead.
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: 0))
        playhead.addLine(to: CGPoint(x: playheadX, y: size.height))
        context.stroke(playhead, with: .color(.yellow.opacity(0.9)), lineWidth: 2)
    }
}

#Preview {
    let notes = DomainFixtures.segments.flatMap(\.targetNotes).map {
        PianoRollView.Note(id: $0.id, midi: $0.midiNote, start: $0.startTime, end: $0.endTime)
    }
    PianoRollView(notes: notes, trail: [], focusMIDI: notes.prefix(4).map(\.midi), songTime: { 1.5 })
        .frame(height: 180)
        .padding()
        .background(.gray)
}
