import Foundation
import AVFoundation
struct PitchRange: Codable {
    var low: Int
    var high: Int
    var label: String { "\(note(low)) – \(note(high))" }
}
func note(_ midi: Int) -> String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
}
enum PitchAnalyzer {
    static func read(_ url: URL) throws -> (PitchRange, Double) {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw CocoaError(.fileReadUnknown) }
        var pitches: [Double] = []
        // Streaming analysis bounds memory even for long imported audio.
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: 8192)
            guard let channels = buffer.floatChannelData else { continue }
            let stride = max(1, Int(rate / 8000))
            let count = Int(buffer.frameLength) / stride
            if count < 512 { continue }
            let samples = (0..<count).map { i -> Float in
                var sum: Float = 0
                for c in 0..<Int(buffer.format.channelCount) { sum += channels[c][i * stride] }
                return sum / Float(buffer.format.channelCount)
            }
            let sr = rate / Double(stride)
            for start in Swift.stride(from: 0, through: count - 512, by: 512) {
                let x = Array(samples[start..<start + 512])
                let energy = x.reduce(0) { $0 + $1 * $1 }
                if energy / 512 < 0.00008 { continue }
                let minLag = max(2, Int(sr / 1000)), maxLag = min(256, Int(sr / 70))
                var scores = [Double](repeating: 0, count: maxLag + 1)
                for lag in minLag...maxLag {
                    var dot: Double = 0, e1: Double = 0, e2: Double = 0
                    for i in 0..<(512 - lag) { let a = Double(x[i]), b = Double(x[i + lag]); dot += a*b; e1 += a*a; e2 += b*b }
                    scores[lag] = dot / max(1e-12, sqrt(e1 * e2))
                }
                // First strong local maximum reduces octave-down errors.
                let best = (minLag...maxLag).max(by: { scores[$0] < scores[$1] })!
                guard scores[best] > 0.80 else { continue }
                let threshold = max(0.80, scores[best] * 0.94)
                var lag = best
                if maxLag > minLag + 2 {
                    for l in (minLag + 1)..<maxLag where scores[l] >= threshold && scores[l] > scores[l-1] && scores[l] >= scores[l+1] { lag = l; break }
                }
                pitches.append(69 + 12 * log2((sr / Double(lag)) / 440))
            }
        }
        guard pitches.count >= 8 else { throw NSError(domain: "Pitch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nada belum cukup jelas. Rekam minimal 5 detik di tempat tenang, tanpa musik pengiring."]) }
        let sorted = pitches.sorted()
        let low = Int(sorted[Int(Double(sorted.count - 1) * 0.05)].rounded())
        let high = Int(sorted[Int(Double(sorted.count - 1) * 0.95)].rounded())
        let deviations = pitches.map { abs($0 - $0.rounded()) * 100 }
        return (PitchRange(low: low, high: high), deviations.reduce(0,+) / Double(deviations.count))
    }
}

let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
let url = URL(fileURLWithPath: "/tmp/key-test.wav")
var out: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
for frequency in [130.8128, 220.0, 391.9954] {
 let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
 b.frameLength = 44100
 for i in 0..<44100 { b.floatChannelData![0][i] = Float(0.25 * sin(2 * Double.pi * frequency * Double(i) / 44100)) }
 try out!.write(from: b)
}
out = nil
let result = try PitchAnalyzer.read(url)
assert(result.0.low == 48 && result.0.high == 67, "Unexpected range: \(result.0.label)")
print("PASS synthetic C3/A3/G4: \(result.0.label)")
let silent = URL(fileURLWithPath: "/tmp/key-silent.wav")
var sf: AVAudioFile? = try AVAudioFile(forWriting: silent, settings: format.settings)
let zero = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
zero.frameLength = 44100
try sf!.write(from: zero)
sf = nil
do { _ = try PitchAnalyzer.read(silent); fatalError("Silence should fail") } catch { print("PASS silence rejected") }
