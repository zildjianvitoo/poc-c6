//
//  PitchWorker.swift
//  poc-c6
//

import AVFoundation
import Foundation
import os

nonisolated final class PitchWorker: @unchecked Sendable {
  private let queue = DispatchQueue(label: "pitch.analysis", qos: .userInitiated)
  private let pending = OSAllocatedUnfairLock(initialState: 0)
  /// ~4 capture buffers (~85 ms) of queued audio.
  private static let maxBacklog = 4
  private var frames = PitchFrameBuffer()
  private var detector: CrepePitchDetector?
  func prepare() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        do {
          frames = PitchFrameBuffer()
          if detector == nil {
            let detector = try CrepePitchDetector()
            // The first CoreML predictions are slow; while one runs, incoming buffers are dropped,
            // so the first second of singing went undetected. Warm up on a voiced tone first.
            let rate = 48_000.0
            let tone = (0..<4096).map { Float(0.3 * sin(2 * Double.pi * 220 * Double($0) / rate)) }
            for _ in 0..<3 { _ = try detector.analyze(tone, sampleRate: rate) }
            self.detector = detector
          }
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  /// Every buffer is appended so the analysis window stays continuous (dropping buffers used to
  /// reset the window and leave gaps). If analysis falls behind, older frames are skipped instead.
  func accept(_ buffer: AVAudioPCMBuffer, start: Double,
              completion: @escaping @Sendable (CrepeEstimate, Double, Double, String?) -> Void) {
    let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
    let samples: [Float]
    if let channel = buffer.floatChannelData?[0] {
      samples = (0..<Int(buffer.frameLength)).map { channel[$0 * stride] }
    } else if let channel = buffer.int16ChannelData?[0] {
      samples = (0..<Int(buffer.frameLength)).map { Float(channel[$0 * stride]) / 32768 }
    } else { return }
    let rate = buffer.format.sampleRate
    let duration = Double(samples.count) / rate
    let backlog = pending.withLock { value -> Int in value += 1; return value }
    queue.async { [self] in
      defer { pending.withLock { $0 -= 1 } }
      do {
        guard let detector else { return }
        let ready = frames.append(samples, sampleRate: rate, start: start)
        // Behind by more than a few buffers: analyse only the newest frame to catch up.
        for frame in backlog > Self.maxBacklog ? Array(ready.suffix(1)) : ready {
          completion(try detector.analyze(frame.samples, sampleRate: rate), frame.start, Double(frame.samples.count) / rate, nil)
        }
      } catch { completion(CrepeEstimate(), start, duration, error.localizedDescription) }
    }
  }
}
