//
//  CrepePitchDetector.swift
//  poc-c6
//
//  CREPE tiny (CoreML) pitch estimate for one audio window. Used for live pitch,
//  the vocal range test and the guide fallback (PRD §2, team decision 2026-11-01).
//

import AVFoundation
import CoreML
import Foundation

nonisolated final class CrepePitchDetector {
  /// CREPE's own voicing threshold on the salience peak (model-specific, PRD §2).
  static let confidenceThreshold = 0.5
  /// Windows quieter than this skip inference. The configurable noise gate is applied later
  /// in TrackLivePitchUseCase; this only saves work on near-silence (−60 dBFS).
  static let minimumRMS = 0.001
  private let model: MLModel
  init(modelURL: URL? = nil) throws {
    guard let url = modelURL ?? Bundle.main.url(forResource: "CrepeTiny", withExtension: "mlmodelc")
    else {
      throw NSError(
        domain: "CREPE", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "CREPE model not found in the app bundle."])
    }
    let config = MLModelConfiguration()
    config.computeUnits = .cpuOnly
    model = try MLModel(contentsOf: url, configuration: config)
  }
  func detect(_ samples: [Float], sampleRate: Double) throws -> Double? {
    try analyze(samples, sampleRate: sampleRate).frequency
  }
  func analyze(_ samples: [Float], sampleRate: Double) throws -> CrepeEstimate {
    guard sampleRate > 0, !samples.isEmpty else { return CrepeEstimate() }
    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
      let source = AVAudioPCMBuffer(
        pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
      let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
      let output = AVAudioPCMBuffer(
        pcmFormat: targetFormat,
        frameCapacity: AVAudioFrameCount(ceil(Double(samples.count) * 16000 / sampleRate) + 256))
    else {
      throw NSError(
        domain: "CREPE", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format for CREPE."])
    }
    source.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer {
      source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
    }
    var supplied = false
    var conversionError: NSError?
    converter.primeMethod = .none
    let status = converter.convert(to: output, error: &conversionError) { _, state in
      if supplied {
        state.pointee = .endOfStream
        return nil
      }
      supplied = true
      state.pointee = .haveData
      return source
    }
    if let conversionError { throw conversionError }
    guard status != .error, output.frameLength >= 1024 else { return CrepeEstimate() }
    let offset = (Int(output.frameLength) - 1024) / 2
    let channel = output.floatChannelData![0]
    let frame = (0..<1024).map { Double(channel[offset + $0]) }
    let mean = frame.reduce(0, +) / 1024
    let variance = frame.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 1024
    let deviation = sqrt(variance)
    var estimate = CrepeEstimate()
    estimate.rms = deviation
    estimate.centerOffset = Double(offset + 512) / 16000
    guard deviation > Self.minimumRMS else { return estimate }
    let input = try MLMultiArray(shape: [1, 1024], dataType: .float32)
    for i in 0..<1024 { input[i] = NSNumber(value: Float((frame[i] - mean) / deviation)) }
    let features = try MLDictionaryFeatureProvider(dictionary: [
      "audio": MLFeatureValue(multiArray: input)
    ])
    let result = try model.prediction(from: features)
    guard let salience = result.featureValue(for: "salience")?.multiArrayValue,
      salience.count == 360
    else {
      throw NSError(
        domain: "CREPE", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Unexpected CREPE model output."])
    }
    let values = (0..<360).map { salience[$0].doubleValue }
    guard let peak = values.indices.max(by: { values[$0] < values[$1] }) else { return estimate }
    estimate.confidence = values[peak]
    guard values[peak] >= Self.confidenceThreshold else { return estimate }
    var sum = 0.0
    var weighted = 0.0
    for i in max(0, peak - 4)...min(359, peak + 4) {
      sum += values[i]
      weighted += values[i] * (1997.3794084376191 + 20 * Double(i))
    }
    guard sum > 0 else { return estimate }
    let hz = 10 * pow(2, weighted / sum / 1200)
    estimate.frequency = hz.isFinite ? hz : nil
    return estimate
  }
}
