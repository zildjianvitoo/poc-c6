import Foundation
@main struct Checks {
 static func main() throws {
  let detector = try CrepePitchDetector(modelURL: URL(fileURLWithPath: CommandLine.arguments[1]))
  func signal(_ gain: Double) -> [Float] {
   (0..<4096).map { Float(gain * sin(2 * Double.pi * 261.63 * Double($0) / 48000)) }
  }
  let normal = try detector.analyze(signal(0.2), sampleRate: 48000)
  precondition(normal.frequency != nil && normal.confidence >= 0.5)
  let quiet = try detector.analyze(signal(0.004), sampleRate: 48000)
  precondition(quiet.frequency == nil && quiet.reason == "Suara terlalu pelan")
  precondition(abs(normal.centerOffset - Double(4096) / 48000 / 2) < 0.002)
  let sampleTime = 1.19, screenTime = 1.30
  let pitch = Twinkle.note(at: sampleTime)!.frequency
  precondition(abs(PitchDetector.cents(pitch, from: Twinkle.note(at: sampleTime)!.frequency)) < 1)
  precondition(abs(PitchDetector.cents(pitch, from: Twinkle.note(at: screenTime)!.frequency)) > 600)
  var eval = SegmentEvaluator()
  eval.ingest(frequency: nil, start: 0, duration: 0.3)
  eval.ingest(frequency: 250, start: 0.3, duration: 0.3)
  precondition(abs(eval.voiced[0] - 0.3) < 1e-8 && eval.matched[0] == 0)
  eval.ingest(frequency: 250, start: 0.3, duration: 0.3)
  precondition(abs(eval.voiced[0] - 0.3) < 1e-8)
  print("PASS: RMS rejection, confidence, window center timing, stale-feedback reproduction, voiced-vs-correct coverage, duplicate prevention")
  for delay in [0.0,0.10,0.20] {
   var e = SegmentEvaluator()
   for n in Twinkle.notes { e.ingest(frequency: n.frequency, start:n.start + delay, duration:n.duration) }
   print("Synthetic perfect pitch delayed \(Int(delay*1000)) ms: score \(Int((e.score*100).rounded()))%")
  }
 }
}
