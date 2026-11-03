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

import AVFoundation
import CoreML

nonisolated final class HTDemucsStemSeparationRepository: StemSeparationRepository, @unchecked Sendable {
    /// The model's fixed window: htdemucs' training segment, 39/5 s at 44.1 kHz.
    static let segmentSamples = 343_980
    /// Sources in model output order.
    static let sources = ["drums", "bass", "other", "vocals"]
    static let vocalsSource = 3

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
        let folder = directory.appendingPathComponent(CoreMLStemSeparationRepository.cacheKey(audioURL, trimRange), isDirectory: true)
        let mixURL = folder.appendingPathComponent("mix.wav")
        let vocalURL = folder.appendingPathComponent("vocals.wav")
        let instrumentalURL = folder.appendingPathComponent("instrumental.wav")
        let stems = SeparatedStems(mixURL: mixURL, vocalGuideURL: vocalURL, instrumentalURL: instrumentalURL, method: .coreML)
        if [mixURL, vocalURL, instrumentalURL].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return stems }

        let model = try loadModel()
        try await Task.detached(priority: .userInitiated) {
            let mix = try CoreMLStemSeparationRepository.readStereo(asset: asset, track: track, trim: trimRange)
            let (vocals, instrumental) = try Self.separate(mix, model: model)
            let mono = [zip(vocals[0], vocals[1]).map { ($0 + $1) / 2 }]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try CoreMLStemSeparationRepository.write(mix, to: mixURL)
            try CoreMLStemSeparationRepository.write(mono, to: vocalURL)
            try CoreMLStemSeparationRepository.write(instrumental, to: instrumentalURL)
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
    static func separate(_ channels: [[Float]], model: MLModel) throws -> (vocals: [[Float]], instrumental: [[Float]]) {
        let spectrogram = DemucsSpectrogram()
        let segment = segmentSamples
        let frames = spectrogram.frameCount(sampleCount: segment)
        let bins = DemucsSpectrogram.bins
        let length = channels[0].count
        let stride = segment * 3 / 4
        // Triangle peaking mid-window (apply_model, transition power 1).
        let half = segment / 2
        let weight = (0..<segment).map { Float($0 < half ? $0 + 1 : segment - $0) / Float(half) }
        let targets = [[vocalsSource], (0..<sources.count).filter { $0 != vocalsSource }]

        var output = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: length), count: 2), count: targets.count)
        var total = [Float](repeating: 0, count: length)
        let mixInput = try MLMultiArray(shape: [1, 2, NSNumber(value: segment)], dataType: .float32)
        let specInput = try MLMultiArray(shape: [1, 4, NSNumber(value: bins), NSNumber(value: frames)], dataType: .float32)
        let mixStrides = mixInput.strides.map(\.intValue)
        let specStrides = specInput.strides.map(\.intValue)

        for offset in Swift.stride(from: 0, to: length, by: stride) {
            // demucs TensorChunk.padded: a short last chunk is centred, with real audio as context.
            let count = min(segment, length - offset)
            let trim = (segment - count) / 2
            let start = offset - trim
            let window = channels.map { channel in
                (0..<segment).map { j -> Float in
                    let k = start + j
                    return k >= 0 && k < length ? channel[k] : 0
                }
            }
            let mixPointer = mixInput.dataPointer.bindMemory(to: Float.self, capacity: mixInput.count)
            let specPointer = specInput.dataPointer.bindMemory(to: Float.self, capacity: specInput.count)
            for c in 0..<2 {
                for j in 0..<segment { mixPointer[c * mixStrides[1] + j * mixStrides[2]] = window[c][j] }
                // Complex as channels: [L real, L imaginary, R real, R imaginary].
                for (t, spectrum) in spectrogram.forward(window[c]).enumerated() {
                    for b in 0..<bins {
                        specPointer[(2 * c) * specStrides[1] + b * specStrides[2] + t * specStrides[3]] = spectrum.real[b]
                        specPointer[(2 * c + 1) * specStrides[1] + b * specStrides[2] + t * specStrides[3]] = spectrum.imaginary[b]
                    }
                }
            }

            let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mix": mixInput, "spec": specInput]))
            guard let specOut = prediction.featureValue(for: "spec_out")?.multiArrayValue,
                  let waveOut = prediction.featureValue(for: "wave_out")?.multiArrayValue,
                  specOut.dataType == .float32, waveOut.dataType == .float32 else {
                throw CoreMLSeparationError.modelUnavailable
            }
            let so = specOut.strides.map(\.intValue)
            let wo = waveOut.strides.map(\.intValue)
            let specValues = specOut.dataPointer.bindMemory(to: Float.self, capacity: specOut.count)
            let waveValues = waveOut.dataPointer.bindMemory(to: Float.self, capacity: waveOut.count)

            for j in 0..<count { total[offset + j] += weight[j] }
            for (target, sourceIndices) in targets.enumerated() {
                for c in 0..<2 {
                    // Sum the target's sources first: iSTFT is linear, so one inverse per target.
                    let spectra = (0..<frames).map { t -> ShortTimeFourierTransform.Spectrum in
                        var real = [Float](repeating: 0, count: bins + 1)
                        var imaginary = [Float](repeating: 0, count: bins + 1)
                        for s in sourceIndices {
                            let re = (s * 4 + 2 * c) * so[1] + t * so[3]
                            let im = (s * 4 + 2 * c + 1) * so[1] + t * so[3]
                            for b in 0..<bins {
                                real[b] += specValues[re + b * so[2]]
                                imaginary[b] += specValues[im + b * so[2]]
                            }
                        }
                        return ShortTimeFourierTransform.Spectrum(real: real, imaginary: imaginary)
                    }
                    let frequencyBranch = spectrogram.inverse(spectra, length: segment)
                    for j in 0..<count {
                        let i = trim + j
                        var sample = frequencyBranch[i]
                        for s in sourceIndices { sample += waveValues[(s * 2 + c) * wo[1] + i * wo[2]] }
                        output[target][c][offset + j] += weight[j] * sample
                    }
                }
            }
        }

        for target in output.indices {
            for c in 0..<2 {
                for i in 0..<length where total[i] > 0 { output[target][c][i] /= total[i] }
            }
        }
        return (output[0], output[1])
    }
}
