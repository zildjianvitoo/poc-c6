//
//  CoreMLStemSeparationRepository.swift
//  poc-c6
//
//  Track B (PRD §3, IK-14/IK-15): on-device vocal separation with Open-Unmix (umxhq vocals,
//  MIT, sigsep) converted to CoreML. STFT 4096/1024 per channel → the model estimates the vocal
//  magnitude in ~6 s chunks (overlapping, crossfaded) → soft mask → vocals; instrumental =
//  mix − vocals. Behind the `useCoreMLSeparation` flag.
//

import AVFoundation
import CoreML

nonisolated enum CoreMLSeparationError: Error, Equatable {
    case modelUnavailable
    case unreadable
    case drmProtected
    case invalidTrim
}

nonisolated final class CoreMLStemSeparationRepository: StemSeparationRepository, @unchecked Sendable {
    /// The model was trained at 44.1 kHz with this STFT.
    static let sampleRate = 44_100.0
    /// Frames per CoreML call (fixed input shape) and overlap between calls.
    static let chunkFrames = 256
    static let overlapFrames = 32

    private let modelURL: URL?
    private let directory: URL
    private let lock = NSLock()
    private var model: MLModel?

    init(modelURL: URL? = nil,
         directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
             .appendingPathComponent("CoreMLSeparation", isDirectory: true)) {
        self.modelURL = modelURL
        self.directory = directory
    }

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        let asset = AVURLAsset(url: audioURL)
        if (try? await asset.load(.hasProtectedContent)) == true { throw CoreMLSeparationError.drmProtected }
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let duration = try? await asset.load(.duration).seconds else { throw CoreMLSeparationError.unreadable }
        guard trimRange.lowerBound >= 0, trimRange.upperBound <= duration + 0.01, trimRange.upperBound > trimRange.lowerBound else {
            throw CoreMLSeparationError.invalidTrim
        }
        let folder = directory.appendingPathComponent(Self.cacheKey(audioURL, trimRange), isDirectory: true)
        let mixURL = folder.appendingPathComponent("mix.wav")
        let vocalURL = folder.appendingPathComponent("vocals.wav")
        let instrumentalURL = folder.appendingPathComponent("instrumental.wav")
        let stems = SeparatedStems(mixURL: mixURL, vocalGuideURL: vocalURL, instrumentalURL: instrumentalURL, method: .coreML)
        if [mixURL, vocalURL, instrumentalURL].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return stems }

        let model = try loadModel()
        try await Task.detached(priority: .userInitiated) {
            let mix = try Self.readStereo(asset: asset, track: track, trim: trimRange)
            let vocals = try Self.separate(mix, model: model)
            let instrumental = (0..<2).map { c in zip(mix[c], vocals[c]).map { $0 - $1 } }
            let mono = [zip(vocals[0], vocals[1]).map { ($0 + $1) / 2 }]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.write(mix, to: mixURL)
            try Self.write(mono, to: vocalURL)
            try Self.write(instrumental, to: instrumentalURL)
        }.value
        return stems
    }

    // MARK: - Model

    private func loadModel() throws -> MLModel {
        try lock.withLock {
            if let model { return model }
            guard let url = modelURL ?? Bundle.main.url(forResource: "OpenUnmixVocals", withExtension: "mlmodelc") else {
                throw CoreMLSeparationError.modelUnavailable
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            model = loaded
            return loaded
        }
    }

    /// Vocal estimate per channel, same length as the input.
    static func separate(_ channels: [[Float]], model: MLModel) throws -> [[Float]] {
        let stft = ShortTimeFourierTransform()
        let bins = stft.bins
        let spectra = channels.map { stft.forward($0) }
        let frames = spectra[0].count
        let magnitudes: [[[Float]]] = spectra.map { frame in
            frame.map { zip($0.real, $0.imaginary).map { sqrt($0 * $0 + $1 * $1) } }
        }
        // Mask accumulated with crossfade weights across overlapping chunks: [channel][frame][bin].
        var mask = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: bins), count: frames), count: 2)
        var weight = [Float](repeating: 0, count: frames)
        let input = try MLMultiArray(shape: [1, 2, NSNumber(value: bins), NSNumber(value: chunkFrames)], dataType: .float32)
        let strides = input.strides.map(\.intValue)
        let step = chunkFrames - overlapFrames
        var start = 0
        while start < frames {
            let pointer = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
            for c in 0..<2 {
                for t in 0..<chunkFrames {
                    let frame = start + t
                    for b in 0..<bins {
                        pointer[c * strides[1] + b * strides[2] + t * strides[3]] = frame < frames ? magnitudes[c][frame][b] : 0
                    }
                }
            }
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["spectrogram": input]))
            guard let estimate = output.featureValue(for: "vocals")?.multiArrayValue else { throw CoreMLSeparationError.modelUnavailable }
            let outStrides = estimate.strides.map(\.intValue)
            let estimatePointer = estimate.dataPointer.bindMemory(to: Float.self, capacity: estimate.count)
            for t in 0..<chunkFrames where start + t < frames {
                let frame = start + t
                // Linear fade over the overlap so chunk seams don't click.
                let fadeIn = start == 0 ? 1 : min(1, Float(t + 1) / Float(overlapFrames + 1))
                let fadeOut = start + chunkFrames >= frames ? 1 : min(1, Float(chunkFrames - t) / Float(overlapFrames + 1))
                let w = min(fadeIn, fadeOut)
                weight[frame] += w
                for c in 0..<2 {
                    for b in 0..<bins {
                        let value = estimatePointer[c * outStrides[1] + b * outStrides[2] + t * outStrides[3]]
                        let m = magnitudes[c][frame][b]
                        mask[c][frame][b] += w * (m > 1e-8 ? min(1, max(0, value / m)) : 0)
                    }
                }
            }
            if start + chunkFrames >= frames { break }
            start += step
        }
        return (0..<2).map { c in
            let masked = (0..<frames).map { f -> ShortTimeFourierTransform.Spectrum in
                let w = weight[f] > 0 ? 1 / weight[f] : 0
                var s = spectra[c][f]
                for b in 0..<bins {
                    let m = mask[c][f][b] * w
                    s.real[b] *= m
                    s.imaginary[b] *= m
                }
                return s
            }
            return stft.inverse(masked, length: channels[c].count)
        }
    }

    // MARK: - Audio files

    private static func readStereo(asset: AVAsset, track: AVAssetTrack, trim: ClosedRange<TimeInterval>) throws -> [[Float]] {
        guard let reader = try? AVAssetReader(asset: asset) else { throw CoreMLSeparationError.unreadable }
        reader.timeRange = CMTimeRange(start: CMTime(seconds: trim.lowerBound, preferredTimescale: 44_100),
                                       end: CMTime(seconds: trim.upperBound, preferredTimescale: 44_100))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
        ])
        guard reader.canAdd(output) else { throw CoreMLSeparationError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw CoreMLSeparationError.unreadable }
        var left: [Float] = [], right: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for i in stride(from: 0, to: data.count - 1, by: 2) {
                left.append(data[i])
                right.append(data[i + 1])
            }
        }
        guard reader.status == .completed, !left.isEmpty else { throw CoreMLSeparationError.unreadable }
        let expected = Int(((trim.upperBound - trim.lowerBound) * sampleRate).rounded())
        return [left, right].map { channel in
            channel.count >= expected ? Array(channel.prefix(expected)) : channel + [Float](repeating: 0, count: expected - channel.count)
        }
    }

    private static func write(_ channels: [[Float]], to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels.count)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(channels[0].count)) else {
            throw CoreMLSeparationError.unreadable
        }
        buffer.frameLength = AVAudioFrameCount(channels[0].count)
        for (c, channel) in channels.enumerated() {
            channel.withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress!, count: channel.count) }
        }
        try? FileManager.default.removeItem(at: url)
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }

    private static func cacheKey(_ url: URL, _ trim: ClosedRange<TimeInterval>) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(url.path)|\(modified)|\(trim.lowerBound)|\(trim.upperBound)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
