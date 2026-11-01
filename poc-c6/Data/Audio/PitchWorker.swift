//
//  PitchWorker.swift
//  poc-c6
//

import AVFoundation
import Foundation

nonisolated final class PitchWorker: @unchecked Sendable {
  private let queue = DispatchQueue(label: "pitch.analysis", qos: .userInitiated)
  private let gate = DispatchSemaphore(value: 1)
  private var frames = PitchFrameBuffer()
  private var detector: CrepePitchDetector?
  func prepare() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        do {
          frames = PitchFrameBuffer()
          if detector == nil { detector = try CrepePitchDetector() }
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  func accept(
    _ buffer: AVAudioPCMBuffer, time: AVAudioTime,
    completion: @escaping @Sendable (CrepeEstimate, Double, Double, String?) -> Void
  ) {
    let duration = Double(buffer.frameLength) / buffer.format.sampleRate
    let start = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : ProcessInfo.processInfo.systemUptime - duration
    accept(buffer, start: start, completion: completion)
  }
  func accept(_ buffer: AVAudioPCMBuffer, start: Double,
              completion: @escaping @Sendable (CrepeEstimate, Double, Double, String?) -> Void) {
    guard gate.wait(timeout: .now()) == .success else { return }
    let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
    let samples: [Float]
    if let channel = buffer.floatChannelData?[0] {
      samples = (0..<Int(buffer.frameLength)).map { channel[$0 * stride] }
    } else if let channel = buffer.int16ChannelData?[0] {
      samples = (0..<Int(buffer.frameLength)).map { Float(channel[$0 * stride]) / 32768 }
    } else { gate.signal(); return }
    let rate = buffer.format.sampleRate
    let duration = Double(samples.count) / rate
    queue.async { [self] in
      defer { gate.signal() }
      do {
        guard let detector else { return }
        for frame in frames.append(samples, sampleRate: rate, start: start) {
          completion(try detector.analyze(frame.samples, sampleRate: rate), frame.start, Double(frame.samples.count) / rate, nil)
        }
      } catch { completion(CrepeEstimate(), start, duration, error.localizedDescription) }
    }
  }
}
