//
//  PitchGraph.swift
//  poc-c6
//

import SwiftUI

struct PitchGraph: View {
  let phrase: Phrase
  let points: [PitchPoint]
  let elapsed: Double
  let showPlayhead: Bool
  var missedNotes: [String] = []
  private let purple = Color(red: 0.45, green: 0.33, blue: 0.93)
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
    Canvas { context, size in
      let left = 35.0
      let top = 10.0
      let width = max(1, size.width - left - 6)
      let height = max(1, size.height - 28)
      let low = Double((phrase.notes.map(\.midi).min() ?? 60) - 3)
      let high = Double((phrase.notes.map(\.midi).max() ?? 72) + 3)
      func x(_ t: Double) -> Double { left + (showPlayhead ? 0.25 + (t - elapsed) / phrase.duration : t / phrase.duration) * width }
      func y(_ midi: Double) -> Double { top + (high - midi) / (high - low) * height }
      for midi in Int(low)...Int(high) {
        if [0, 2, 4, 5, 7, 9, 11].contains((midi % 12 + 12) % 12) {
          var line = Path()
          line.move(to: CGPoint(x: left, y: y(Double(midi))))
          line.addLine(to: CGPoint(x: left + width, y: y(Double(midi))))
          context.stroke(line, with: .color(.gray.opacity(0.12)), lineWidth: 1)
          let hz = 440 * pow(2, Double(midi - 69) / 12)
          context.draw(
            Text(PitchDetector.noteName(hz)).font(.system(size: 10)).foregroundColor(.secondary),
            at: CGPoint(x: 14, y: y(Double(midi))))
        }
      }
      context.clip(to: Path(CGRect(x: left, y: 0, width: width, height: size.height)))
      for beat in 0...8 {
        var grid = Path()
        grid.move(to: CGPoint(x: x(Double(beat) * 0.6), y: top))
        grid.addLine(to: CGPoint(x: x(Double(beat) * 0.6), y: top + height))
        context.stroke(grid, with: .color(.gray.opacity(0.12)), lineWidth: 1)
      }
      for note in phrase.notes {
        var target = Path()
        let point = CGPoint(x: x(note.start - phrase.start), y: y(Double(note.midi)))
        target.move(to: point)
        target.addLine(to: CGPoint(x: x(note.start - phrase.start + note.duration), y: point.y))
        context.stroke(target, with: .color(missedNotes.contains(note.name) ? Color.red.opacity(0.4 + 0.6 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * .pi * 2))) : purple), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
      }
      var previous: Double?
      var previousPoint: CGPoint?
      for sample in PitchTrace.smoothed(points) {
        guard let hz = sample.frequency, hz > 0 else {
          previous = nil
          continue
        }
        let midi = 69 + 12 * log2(hz / 440)
        guard (low...high).contains(midi) else {
          context.draw(
            Text(midi > high ? "↑" : "↓").font(.system(size: 11, weight: .bold)).foregroundColor(
              .blue),
            at: CGPoint(x: x(sample.time), y: midi > high ? top : top + height))
          previous = nil
          continue
        }
        let point = CGPoint(x: x(sample.time), y: y(midi))
        let targetNote = phrase.notes.first { phrase.start + sample.time >= $0.start && phrase.start + sample.time < $0.start + $0.duration }
        let correct = targetNote.map { abs(PitchDetector.cents(hz, from: $0.frequency)) <= Double(PoCConfiguration.default.hitToleranceCents) } ?? false
        let color: Color = correct ? .green : .red
        if let previous, let previousPoint, sample.time - previous < PracticeConfiguration.traceGap {
          var line = Path()
          line.move(to: previousPoint)
          line.addLine(to: point)
          context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        previousPoint = point
        context.fill(
          Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
          with: .color(color))
        previous = sample.time
      }

      if showPlayhead {
        var cursor = Path()
        cursor.move(to: CGPoint(x: x(min(phrase.duration, elapsed)), y: top))
        cursor.addLine(to: CGPoint(x: x(min(phrase.duration, elapsed)), y: top + height))
        context.stroke(
          cursor, with: .color(purple.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
      }
    }
    }.accessibilityLabel("Target pitch and green/red singing pitch for segment \(phrase.id + 1)")
  }
}
