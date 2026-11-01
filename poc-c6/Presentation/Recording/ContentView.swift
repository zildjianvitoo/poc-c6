//
//  ContentView.swift
//  poc-c6
//

import SwiftUI

struct ContentView: View {
  @State private var showHistory = false
  @State private var showEndSession = false
  @State private var model = PracticeModel()
  @Environment(\.scenePhase) private var scenePhase
  private let purple = Color(red: 0.45, green: 0.33, blue: 0.93)
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text("VOCAL PRACTICE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(purple)
            Text("Twinkle, Twinkle\nLittle Star").font(.title.bold())
            Text("C major · 100 BPM · 6 segments").foregroundStyle(.secondary)
          }
          if !model.canStart {
            Label("Plug in earphones to start practice.", systemImage: "headphones").foregroundStyle(.orange)
          } else if model.audioRoute == .bluetooth {
            Label("Wired earphones give the best sync.", systemImage: "wave.3.right").foregroundStyle(.orange)
          }
          if model.running {
            CameraPreviewView(session: model.capture.session)
              .aspectRatio(9.0 / 16.0, contentMode: .fit)
              .overlay {
                PitchGraph(phrase: model.phrase, points: model.visiblePoints, elapsed: max(0, model.elapsed), showPlayhead: model.running, missedNotes: model.phase == .result ? model.missedNotes : [])
                  .frame(height: 180).background(.ultraThinMaterial)
              }
              .overlay(alignment: .top) {
                Text("Segment \(model.displayIndex + 1)/\(Phrase.all.count) · Attempt \(max(1, model.progress.attempts[model.displayIndex]))")
                  .font(.caption.bold()).padding(8).background(.regularMaterial, in: Capsule()).padding()
              }
              .clipShape(RoundedRectangle(cornerRadius: 16))
          }
          if model.finalizing { ProgressView("Finalizing recording…") }
          if let url = model.rawVideoURL {
            ShareLink(items: [url] + (model.handoffURL.map { [$0] } ?? [])) { Label("Share raw recording", systemImage: "square.and.arrow.up") }
          }
          if !model.running && !model.finalizing {
            HStack {
              Text("Latency calibration (ms)")
              TextField("0", value: $model.manualLatencyMilliseconds, format: .number).keyboardType(.numbersAndPunctuation).frame(width: 70)
            }.font(.caption)
          }
          Button {
            showHistory = true
          } label: {
            Label("Results & attempt history", systemImage: "list.clipboard")
          }.buttonStyle(.bordered)
          if let error = model.historyError {
            Text(error).font(.caption).foregroundStyle(.red)
          }
          if let score = model.lastScore {
            CorrectionOverlayView(passed: model.lastPassed, score: score, missedNotes: model.missedNotes)
          }
          if let summary = model.endSummary { Text(summary).font(.headline) }
          HStack(spacing: 8) {
            ForEach(0..<6) { index in
              VStack(spacing: 6) {
                Capsule().fill(segmentColor(index)).frame(height: 6)
                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(segmentColor(index))
              }
            }
          }.accessibilityLabel("Segment \(model.displayIndex + 1) dari 6")
          VStack(alignment: .leading, spacing: 18) {
            HStack {
              Text("SEGMENT \(model.displayIndex + 1)").font(.caption.bold()).foregroundStyle(purple)
              Spacer()
              Text("Attempt \(max(1, model.progress.attempts[model.displayIndex]))").font(
                .caption
              ).foregroundStyle(.secondary)
            }
            lyric.font(.title2.bold()).lineSpacing(8)
              .frame(maxWidth: .infinity, alignment: .center)
              .accessibilityLabel(model.phrase.lyric)
            Text(model.feedback).font(.subheadline.weight(.semibold))
              .foregroundStyle(purple).frame(maxWidth: .infinity)
          }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
          VStack(alignment: .leading, spacing: 14) {
            HStack {
              Text(
                "\(time(model.phrase.start)) – \(time(model.phrase.start + model.phrase.duration))"
              ).font(.headline.monospacedDigit())
              Spacer()
              if let score = model.lastScore {
                Text(
                  "Segment \((model.lastEvaluatedPhrase ?? 0) + 1) \(model.lastPassed ? "PASS" : "TRY AGAIN") · \(Int((score * 100).rounded()))%"
                )
                .font(.caption.bold()).foregroundStyle(model.lastPassed ? .green : .orange)
              }
            }
            PitchGraph(
              phrase: model.phrase, points: model.visiblePoints,
              elapsed: max(0, model.elapsed), showPlayhead: model.running, missedNotes: model.phase == .result ? model.missedNotes : []
            )
            .frame(height: 220)
            Text("Pitch range follows the target notes · Playhead at 25%")
              .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 24) {
              Label("Target pitch", systemImage: "circle.fill").foregroundStyle(purple)
              Label("In tune / off pitch", systemImage: "circle.fill").foregroundStyle(.green)
            }.font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
            HStack {
              Text(
                model.frequency.map { "\(PitchDetector.noteName($0)) · \(Int($0)) Hz" }
                  ?? "Your voice: —")
              Spacer()
              Text(model.deviation.map { String(format: "%+.0f cents", $0) } ?? "±50 cents")
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
          }.padding(18).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("Segment accuracy").font(.subheadline.bold())
              Spacer()
              Text(model.score, format: .percent.precision(.fractionLength(0))).bold()
                .monospacedDigit()
            }
            ProgressView(value: model.score).tint(purple)
            Text(
              "The graph is smoothed for display. Scoring uses the original CREPE estimates every 50 ms."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text("Lulus ≥75% langsung lanjut · Segment gagal diulang otomatis")
              .font(.caption).foregroundStyle(.secondary)
            Text(model.message).font(.callout)
          }
          VStack(alignment: .leading, spacing: 8) {
            Text("Pitch diagnostics").font(.subheadline.bold())
            Text(model.detection.reason)
            Text(
              String(
                format: "Confidence %.2f / minimum 0.50 · RMS %.4f / minimum 0.010",
                model.detection.confidence, model.detection.rms))
            Text(
              "Suara terbaca: \(Int((model.detectionCoverage * 100).rounded()))% dari durasi bait yang sudah berjalan"
            )
            Text("Target sampel audio: \(model.comparisonTarget?.name ?? "—")")
            Text(
              String(
                format: "Usia sampel %.0f ms · latensi output dilaporkan %.0f ms",
                model.processingDelay * 1000, model.outputDelay * 1000))
            Text(
              "Missing voice frames count as misses. Use these diagnostics to check microphone input."
            )
          }.font(.caption).foregroundStyle(.secondary)
            .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
          HStack {
            Image(systemName: "speaker.wave.2")
            Slider(value: $model.volume, in: 0...1).accessibilityLabel("Music volume")
            Text("Music").font(.caption)
          }
          Label(
            "Gunakan headphone. Music dari speaker dapat ikut dinilai oleh mikrofon.",
            systemImage: "headphones"
          )
          .font(.caption).foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 14) {
            Text("Lyrics & progress").font(.headline)
            ForEach(Phrase.all) { phrase in
              HStack(alignment: .top) {
                Text("\(phrase.id + 1)").font(.caption.bold()).frame(width: 20)
                Text(phrase.lyric).font(.subheadline)
                Spacer()
                if let score = model.progress.scores[phrase.id] {
                  Text(
                    "\(score + 1e-9 >= SegmentEvaluator.passThreshold ? "PASSED" : "PENDING") · \(Int((score * 100).rounded()))%"
                  )
                  .font(.caption.bold()).foregroundStyle(
                    score + 1e-9 >= SegmentEvaluator.passThreshold ? .green : .orange)
                }
              }.foregroundStyle(phrase.id == model.displayIndex ? purple : .secondary)
            }
          }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
        }.padding(20)
      }.background(Color(red: 0.96, green: 0.96, blue: 0.99))
        .sheet(isPresented: $showHistory) {
          AttemptHistoryView(history: model.history, error: model.historyError)
        }
        .navigationTitle("Pitch Practice").navigationBarTitleDisplayMode(.inline)
        .tint(purple)
        .safeAreaInset(edge: .bottom) {
          HStack {
            Button {
              model.preview()
            } label: {
              Label("Preview segment", systemImage: "play.circle")
            }
            .disabled(model.running || model.requesting)
            Spacer()
            Button {
              if model.running { showEndSession = true } else { Task { await model.start() } }
            } label: {
              Label(
                model.running ? "End Session" : "Start practice",
                systemImage: model.running ? "stop.fill" : "mic.fill")
            }.buttonStyle(.borderedProminent).disabled(model.requesting || (!model.running && !model.canStart) || model.finalizing)
          }
          .padding(.horizontal, 20).padding(.vertical, 12)
          .background(.regularMaterial)
        }
    }
    .confirmationDialog("End this session?", isPresented: $showEndSession, titleVisibility: .visible) {
      Button("Save recording for \(model.passedSegmentCount) of \(Phrase.all.count) segments") { model.endSession() }
      Button("Keep practicing", role: .cancel) {}
      Button("Discard session", role: .destructive) { model.endSession(discard: true) }
    } message: {
      Text("The continuous raw recording and passed takes will be saved. Final comping is not available yet.")
    }
    .onAppear {
      model.refreshAudioRoute()
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-history") { showHistory = true }
      #endif
    }
    .onChange(of: scenePhase) { _, phase in if phase == .background { model.stop() } }
  }
  private var lyric: Text {
    model.phrase.words.enumerated().reduce(Text("")) { result, item in
      let active = model.target?.id == model.phrase.notes[item.offset].id
      let joinedOffsets: [Int] =
        [0, 4].contains(model.phrase.id)
        ? [0, 2, 4] : ([1, 5].contains(model.phrase.id) ? [2] : (model.phrase.id == 2 ? [1] : [2]))
      let separator = joinedOffsets.contains(item.offset) ? "" : " "
      return result
        + Text(item.element + separator).foregroundColor(active ? purple : .primary)
        .underline(active, color: purple)
    }
  }
  private func segmentColor(_ index: Int) -> Color {
    if let score = model.progress.scores[index], score + 1e-9 >= SegmentEvaluator.passThreshold {
      return .green
    }
    return index == model.displayIndex ? purple : .gray.opacity(0.25)
  }
  private func time(_ t: Double) -> String {
    String(format: "%02d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
  }
}

#Preview { ContentView() }
