//
//  HTDemucsStemSeparationRepository.swift
//  poc-c6
//
//  On-device vocal separation with htdemucs (Demucs v4, Meta, MIT) converted to CoreML: only the
//  network is in the model; the demucs STFT/iSTFT and the 7.8 s chunking (25 % overlap,
//  triangular weights, as demucs.apply.apply_model) run here. Vocal stem = "vocals" source;
//  instrumental = drums + bass + other. Spike, numbers and conversion:
//  docs/test-reports/htdemucs-coreml-spike-2026-11-03.md, prototypes/htdemucs-coreml/.
//

import Accelerate
import AVFoundation
import CoreML
import os

nonisolated final class HTDemucsStemSeparationRepository: StemSeparationRepository, @unchecked Sendable {
    /// The model was trained at 44.1 kHz.
    static let sampleRate = 44_100.0
    /// The model's fixed window: htdemucs' training segment, 39/5 s at 44.1 kHz.
    static let segmentSamples = 343_980
    /// Sources in model output order.
    static let sources = ["drums", "bass", "other", "vocals"]
    static let vocalsSource = 3

    /// Where the preparation time goes (model load, audio I/O, STFT, inference, iSTFT); a few
    /// lines per song, also in Release builds, for device tests.
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "poc-c6", category: "Separation")

    private let modelURL: URL?
    private let directory: URL
    private let lock = NSLock()
    private var model: MLModel?

    init(modelURL: URL? = nil,
         directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
             .appendingPathComponent("HTDemucsSeparation", isDirectory: true)) {
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

        let clock = ContinuousClock()
        let loadStarted = clock.now
        let model = try loadModel()
        let loadSeconds = (clock.now - loadStarted) / .seconds(1)
        try await Task.detached(priority: .userInitiated) {
            let readStarted = clock.now
            let mix = try Self.readStereo(asset: asset, track: track, trim: trimRange)
            let readSeconds = (clock.now - readStarted) / .seconds(1)
            let (vocals, instrumental) = try Self.separate(mix, model: model)
            let writeStarted = clock.now
            let mono = [zip(vocals[0], vocals[1]).map { ($0 + $1) / 2 }]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.write(mix, to: mixURL)
            try Self.write(mono, to: vocalURL)
            try Self.write(instrumental, to: instrumentalURL)
            Self.log.notice("""
                htdemucs timing: model load \(loadSeconds, format: .fixed(precision: 2)) s, read audio \(readSeconds, format: .fixed(precision: 2)) s, \
                write stems \((clock.now - writeStarted) / .seconds(1), format: .fixed(precision: 2)) s
                """)
        }.value
        return stems
    }

    // MARK: - Model

    private func loadModel() throws -> MLModel {
        try lock.withLock {
            if let model { return model }
            guard let url = modelURL ?? Bundle.main.url(forResource: "HTDemucs", withExtension: "mlmodelc") else {
                throw CoreMLSeparationError.modelUnavailable
            }
            let configuration = MLModelConfiguration()
            // GPU: on the Neural Engine the model's float32 normalisation ops split it into CPU/ANE
            // pieces (18× slower, ~8 GB), and `.all` gives wrong output (spike §4). Where Core ML
            // runs it on the CPU instead (Simulator, possibly the background) the stems get noisier
            // (~30 dB SNR vs ~60 dB on the GPU) but stay usable.
            configuration.computeUnits = .cpuAndGPU
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            model = loaded
            return loaded
        }
    }

    // MARK: - Separation

    /// Vocal and instrumental (drums + bass + other) estimate per channel, same length as the input.
    /// Per-sample work goes through vDSP so Debug builds (no Swift optimisation) stay fast.
    static func separate(_ channels: [[Float]], model: MLModel) throws -> (vocals: [[Float]], instrumental: [[Float]]) {
        let spectrogram = DemucsSpectrogram()
        let segment = segmentSamples
        let frames = spectrogram.frameCount(sampleCount: segment)
        let bins = DemucsSpectrogram.bins
        let length = channels[0].count
        let stride = segment * 3 / 4
        // Triangle peaking mid-window (apply_model, transition power 1): 1, 2, …, half, …, 2, 1 over half.
        let half = segment / 2
        let weight = vDSP.divide(vDSP.ramp(withInitialValue: 1, increment: 1, count: half)
                                     + vDSP.ramp(withInitialValue: Float(segment - half), increment: -1, count: segment - half),
                                 Float(half))
        let targets = [[vocalsSource], (0..<sources.count).filter { $0 != vocalsSource }]

        var output = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: length), count: 2), count: targets.count)
        var total = [Float](repeating: 0, count: length)
        let mixInput = try MLMultiArray(shape: [1, 2, NSNumber(value: segment)], dataType: .float32)
        let specInput = try MLMultiArray(shape: [1, 4, NSNumber(value: bins), NSNumber(value: frames)], dataType: .float32)
        let mixStrides = mixInput.strides.map(\.intValue)
        let specStrides = specInput.strides.map(\.intValue)
        let clock = ContinuousClock()
        var inputTime = Duration.zero, modelTime = Duration.zero, outputTime = Duration.zero
        var chunks = 0

        for offset in Swift.stride(from: 0, to: length, by: stride) {
            // Free each chunk's CoreML buffers right away; otherwise they pile up until the loop ends
            // (7 GB for a 4.6 min song).
            try autoreleasepool {
                // demucs TensorChunk.padded: a short last chunk is centred, with real audio as context.
                let count = min(segment, length - offset)
                let trim = (segment - count) / 2
                let start = offset - trim
                let inputStarted = clock.now
                let lo = max(0, start), hi = min(length, start + segment)
                let window = channels.map { channel in
                    var samples = [Float](repeating: 0, count: segment)
                    samples.replaceSubrange((lo - start)..<(hi - start), with: channel[lo..<hi])
                    return samples
                }
                let mixPointer = mixInput.dataPointer.bindMemory(to: Float.self, capacity: mixInput.count)
                let specPointer = specInput.dataPointer.bindMemory(to: Float.self, capacity: specInput.count)
                for c in 0..<2 {
                    copy(window[c], to: mixPointer + c * mixStrides[1], stride: mixStrides[2])
                    // Complex as channels: [L real, L imaginary, R real, R imaginary], each (bin, frame).
                    let spectra = spectrogram.forward(window[c])
                    writePlane(frameMajor(spectra.map(\.real), bins: bins), to: specPointer + (2 * c) * specStrides[1],
                               binStride: specStrides[2], frameStride: specStrides[3], bins: bins, frames: frames)
                    writePlane(frameMajor(spectra.map(\.imaginary), bins: bins), to: specPointer + (2 * c + 1) * specStrides[1],
                               binStride: specStrides[2], frameStride: specStrides[3], bins: bins, frames: frames)
                }

                let modelStarted = clock.now
                inputTime += modelStarted - inputStarted
                let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mix": mixInput, "spec": specInput]))
                let outputStarted = clock.now
                modelTime += outputStarted - modelStarted
                chunks += 1
                guard let specOut = prediction.featureValue(for: "spec_out")?.multiArrayValue,
                      let waveOut = prediction.featureValue(for: "wave_out")?.multiArrayValue,
                      specOut.dataType == .float32, waveOut.dataType == .float32 else {
                    throw CoreMLSeparationError.modelUnavailable
                }
                let so = specOut.strides.map(\.intValue)
                let wo = waveOut.strides.map(\.intValue)
                let specValues = UnsafePointer(specOut.dataPointer.bindMemory(to: Float.self, capacity: specOut.count))
                let waveValues = UnsafePointer(waveOut.dataPointer.bindMemory(to: Float.self, capacity: waveOut.count))

                total.withUnsafeMutableBufferPointer {
                    vDSP_vadd(weight, 1, $0.baseAddress! + offset, 1, $0.baseAddress! + offset, 1, vDSP_Length(count))
                }
                for (target, sourceIndices) in targets.enumerated() {
                    for c in 0..<2 {
                        // Sum the target's sources first: iSTFT is linear, so one inverse per target.
                        func summed(_ part: Int) -> [Float] {
                            sourceIndices.map { s in
                                readPlane(specValues + (s * 4 + 2 * c + part) * so[1], binStride: so[2], frameStride: so[3],
                                          bins: bins, frames: frames)
                            }.reduce([Float](repeating: 0, count: bins * frames)) { vDSP.add($0, $1) }
                        }
                        let real = summed(0), imaginary = summed(1)
                        let spectra = (0..<frames).map { t in
                            ShortTimeFourierTransform.Spectrum(real: Array(real[(t * bins)..<((t + 1) * bins)]) + [0],
                                                               imaginary: Array(imaginary[(t * bins)..<((t + 1) * bins)]) + [0])
                        }
                        // Frequency branch + the sources' time branch, then weighted into the output.
                        var chunk = Array(spectrogram.inverse(spectra, length: segment)[trim..<(trim + count)])
                        chunk.withUnsafeMutableBufferPointer { samples in
                            for s in sourceIndices {
                                vDSP_vadd(samples.baseAddress!, 1, waveValues + (s * 2 + c) * wo[1] + trim * wo[2], vDSP_Stride(wo[2]),
                                          samples.baseAddress!, 1, vDSP_Length(count))
                            }
                        }
                        output[target][c].withUnsafeMutableBufferPointer {
                            vDSP_vma(chunk, 1, weight, 1, $0.baseAddress! + offset, 1, $0.baseAddress! + offset, 1, vDSP_Length(count))
                        }
                    }
                }
                outputTime += clock.now - outputStarted
            }
        }
        log.notice("""
            htdemucs timing: \(chunks) chunks, STFT + inputs \(inputTime / .seconds(1), format: .fixed(precision: 2)) s, \
            model \(modelTime / .seconds(1), format: .fixed(precision: 2)) s, iSTFT + mixing \(outputTime / .seconds(1), format: .fixed(precision: 2)) s
            """)

        // Every sample is covered by at least one chunk, so total > 0.
        let normalized = output.map { target in target.map { vDSP.divide($0, total) } }
        return (normalized[0], normalized[1])
    }

    // MARK: - Strided copies (vDSP)

    /// Frames (each ≥ `bins` values) → one (frame, bin) row-major matrix of the first `bins` values.
    private static func frameMajor(_ frames: [[Float]], bins: Int) -> [Float] {
        var matrix = [Float]()
        matrix.reserveCapacity(frames.count * bins)
        for frame in frames { matrix.append(contentsOf: frame[0..<bins]) }
        return matrix
    }

    private static func copy(_ values: [Float], to destination: UnsafeMutablePointer<Float>, stride: Int) {
        var zero: Float = 0
        // Strided copy: destination[i * stride] = values[i] + 0.
        vDSP_vsadd(values, 1, &zero, destination, vDSP_Stride(stride), vDSP_Length(values.count))
    }

    /// (frame, bin) matrix → a model plane laid out with the given (bin, frame) strides.
    private static func writePlane(_ matrix: [Float], to destination: UnsafeMutablePointer<Float>,
                                   binStride: Int, frameStride: Int, bins: Int, frames: Int) {
        guard frameStride == 1 else {
            for t in 0..<frames {
                for b in 0..<bins { destination[b * binStride + t * frameStride] = matrix[t * bins + b] }
            }
            return
        }
        if binStride == frames {
            vDSP_mtrans(matrix, 1, destination, 1, vDSP_Length(bins), vDSP_Length(frames))
        } else {
            var transposed = [Float](repeating: 0, count: bins * frames)
            vDSP_mtrans(matrix, 1, &transposed, 1, vDSP_Length(bins), vDSP_Length(frames))
            vDSP_mmov(transposed, destination, vDSP_Length(frames), vDSP_Length(bins), vDSP_Length(frames), vDSP_Length(binStride))
        }
    }

    /// A model plane with the given (bin, frame) strides → a (frame, bin) row-major matrix.
    private static func readPlane(_ source: UnsafePointer<Float>, binStride: Int, frameStride: Int,
                                  bins: Int, frames: Int) -> [Float] {
        var matrix = [Float](repeating: 0, count: bins * frames)
        guard frameStride == 1 else {
            for t in 0..<frames {
                for b in 0..<bins { matrix[t * bins + b] = source[b * binStride + t * frameStride] }
            }
            return matrix
        }
        if binStride == frames {
            vDSP_mtrans(source, 1, &matrix, 1, vDSP_Length(frames), vDSP_Length(bins))
        } else {
            var packed = [Float](repeating: 0, count: bins * frames)
            vDSP_mmov(source, &packed, vDSP_Length(frames), vDSP_Length(bins), vDSP_Length(binStride), vDSP_Length(frames))
            vDSP_mtrans(packed, 1, &matrix, 1, vDSP_Length(frames), vDSP_Length(bins))
        }
        return matrix
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
