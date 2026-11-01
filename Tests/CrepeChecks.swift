import Foundation
@main struct Checks {
 static func main() throws {
  let detector = try CrepePitchDetector(modelURL: URL(fileURLWithPath: CommandLine.arguments[1]))
  var count = 0
  let begin = Date()
  for rate in [16000.0,44100,48000] {
   for hz in [130.81,261.63,329.63,440,880] {
    let samples = (0..<4096).map { i -> Float in
     let phase = 2 * Double.pi * hz * Double(i) / rate
     return Float(0.2 * sin(phase) + 0.08 * sin(2 * phase))
    }
    let result = try detector.detect(samples, sampleRate: rate)
    precondition(result != nil && abs(1200 * log2(result! / hz)) < 35, "pitch or resample failed: \(rate), \(hz), \(String(describing: result))")
    count += 1
   }
  }
  let silence = try detector.detect([Float](repeating: 0, count:4096),sampleRate:48000)
  precondition(silence == nil)
  print("PASS: \(count) Swift CREPE pitch/resampling checks plus silence; elapsed \(Date().timeIntervalSince(begin)) seconds")
 }
}
