//
//  CenterChannelStemRepository.swift
//  poc-c6
//
//  Track B fallback stem separation by center-channel cancellation (PRD §3, §5.2). Owner: Ikzaz (IK-13).
//  Vocals are usually panned to the center, so the side channel (L - R) / 2 is a rough
//  "music without vocals". The mid channel (L + R) / 2, band-passed, is only used for pitch extraction.
//  All outputs are uncompressed WAV (AAC priming would shift timing), start at t = 0 and have the same length.
//

import Accelerate
import AVFoundation
import Foundation

nonisolated enum CenterChannelError: Error, Equatable, Sendable {
    /// The asset has DRM (`hasProtectedContent`).
    case drmProtected
    /// The file cannot be opened or decoded.
    case unreadable
    case noAudioTrack
    /// L ≈ R: the vocals cannot be removed with this method.
    case monoSource
    /// The trim range is outside the file or empty.
    case invalidTrim
}

nonisolated final class CenterChannelStemRepository: StemSeparationRepository, Sendable {
    /// Fixed DSP parameters of this method (not user-tunable, so they live here and not in `PoCConfiguration`).
    nonisolated struct Parameters: Sendable {
        /// Side energy below this level relative to mid (dB) means the source is mono.
        var monoThresholdDB: Float = -40
        var bandLow: Double = 80
        var bandHigh: Double = 1_100
        var filterQ: Double = 0.7071
        /// The instrumental is scaled to the mix peak, never above this.
        var peakCeiling: Float = 0.99
        /// Extra seconds decoded around the trim so the first and last samples are always covered.
        var readMargin: TimeInterval = 0.5
        var writeChunkFrames: Int = 65_536
    }

    private let directory: URL
    private let parameters: Parameters

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CenterChannel", isDirectory: true),
         parameters: Parameters = Parameters()) {
        self.directory = directory
        self.parameters = parameters
    }

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        guard trimRange.lowerBound.isFinite, trimRange.upperBound.isFinite,
              trimRange.lowerBound >= 0, trimRange.upperBound > trimRange.lowerBound else {
            throw CenterChannelError.invalidTrim
        }
        let cacheFolder = directory.appendingPathComponent(Self.cacheKey(url: audioURL, trim: trimRange), isDirectory: true)
        let mix = cacheFolder.appendingPathComponent("mix.wav")
        let guide = cacheFolder.appendingPathComponent("vocalGuide.wav")
        let instrumental = cacheFolder.appendingPathComponent("instrumental.wav")
        let stems = SeparatedStems(mixURL: mix, vocalGuideURL: guide, instrumentalURL: instrumental,
                                   method: .centerChannelCancellation)
        let allFiles = [mix, guide, instrumental]
        if allFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return stems }

        let source = try await Self.readTrimmedStereo(from: audioURL, trim: trimRange, parameters: parameters)
        let parameters = self.parameters
        let directory = self.directory
        try await Task.detached(priority: .userInitiated) {
            let processed = try Self.process(source, parameters: parameters)
            let fileManager = FileManager.default
            let temp = directory.appendingPathComponent("tmp-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: temp) }
            try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
            let chunk = parameters.writeChunkFrames
            try Self.write(channels: [source.left, source.right], sampleRate: source.sampleRate,
                           to: temp.appendingPathComponent("mix.wav"), chunk: chunk)
            try Self.write(channels: [processed.guide], sampleRate: source.sampleRate,
                           to: temp.appendingPathComponent("vocalGuide.wav"), chunk: chunk)
            try Self.write(channels: [processed.side, processed.side], sampleRate: source.sampleRate,
                           to: temp.appendingPathComponent("instrumental.wav"), chunk: chunk)
            try? fileManager.removeItem(at: cacheFolder)
            do {
                try fileManager.moveItem(at: temp, to: cacheFolder)
            } catch {
                // A concurrent call may have produced the same folder; use it if complete.
                guard allFiles.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else { throw error }
            }
        }.value
        return stems
    }

    // MARK: - Reading

    private struct StereoAudio: Sendable {
        let left: [Float]
        let right: [Float]
        let sampleRate: Double
    }

    /// Decodes the trimmed range to float32 stereo at the source sample rate, placing samples by presentation time.
    private static func readTrimmedStereo(from url: URL, trim: ClosedRange<TimeInterval>,
                                          parameters: Parameters) async throws -> StereoAudio {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            if try await asset.load(.hasProtectedContent) { throw CenterChannelError.drmProtected }
            tracks = try await asset.loadTracks(withMediaType: .audio)
            duration = try await asset.load(.duration)
        } catch let error as CenterChannelError {
            throw error
        } catch {
            throw CenterChannelError.unreadable
        }
        guard let track = tracks.first else { throw CenterChannelError.noAudioTrack }
        guard duration.seconds.isFinite, trim.upperBound <= duration.seconds + 0.001 else {
            throw CenterChannelError.invalidTrim
        }

        var sampleRate: Double = 0
        if let descriptions = try? await track.load(.formatDescriptions),
           let description = descriptions.first,
           let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
            sampleRate = basic.pointee.mSampleRate
        }
        guard sampleRate > 0 else { throw CenterChannelError.unreadable }

        return try await Task.detached(priority: .userInitiated) {
            try decode(asset: asset, track: track, sampleRate: sampleRate, trim: trim, parameters: parameters)
        }.value
    }

    private static func decode(asset: AVURLAsset, track: AVAssetTrack, sampleRate: Double,
                               trim: ClosedRange<TimeInterval>, parameters: Parameters) throws -> StereoAudio {
        let startFrame = Int((trim.lowerBound * sampleRate).rounded())
        let frameCount = Int((trim.upperBound * sampleRate).rounded()) - startFrame
        guard frameCount > 0 else { throw CenterChannelError.invalidTrim }

        guard let reader = try? AVAssetReader(asset: asset) else { throw CenterChannelError.unreadable }
        let readStart = max(0, trim.lowerBound - parameters.readMargin)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: readStart, preferredTimescale: 600_000),
            end: CMTime(seconds: trim.upperBound + parameters.readMargin, preferredTimescale: 600_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: sampleRate,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw CenterChannelError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw CenterChannelError.unreadable }

        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        var scratch = [Float]()
        var nextFrame: Int? // absolute frame index of the next expected sample
        var one: Float = 1

        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let frames = CMSampleBufferGetNumSamples(buffer)
            let byteCount = frames * 2 * MemoryLayout<Float>.size
            guard frames > 0, CMBlockBufferGetDataLength(block) >= byteCount else { continue }
            if scratch.count < frames * 2 { scratch = [Float](repeating: 0, count: frames * 2) }
            let status = scratch.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw CenterChannelError.unreadable }

            // Position by PTS for the first buffer (and after any gap); otherwise stay contiguous.
            let ptsFrame = Int((CMSampleBufferGetPresentationTimeStamp(buffer).seconds * sampleRate).rounded())
            let bufferStart: Int
            if let expected = nextFrame, abs(ptsFrame - expected) <= 1 { bufferStart = expected } else { bufferStart = ptsFrame }
            nextFrame = bufferStart + frames

            let lower = max(bufferStart, startFrame)
            let upper = min(bufferStart + frames, startFrame + frameCount)
            guard upper > lower else { continue }
            let count = vDSP_Length(upper - lower)
            let sourceOffset = (lower - bufferStart) * 2
            let destOffset = lower - startFrame
            scratch.withUnsafeBufferPointer { source in
                // Strided copy (de-interleave) as a multiply by 1.
                left.withUnsafeMutableBufferPointer {
                    vDSP_vsmul(source.baseAddress! + sourceOffset, 2, &one, $0.baseAddress! + destOffset, 1, count)
                }
                right.withUnsafeMutableBufferPointer {
                    vDSP_vsmul(source.baseAddress! + sourceOffset + 1, 2, &one, $0.baseAddress! + destOffset, 1, count)
                }
            }
        }
        if reader.status == .failed { throw CenterChannelError.unreadable }
        return StereoAudio(left: left, right: right, sampleRate: sampleRate)
    }

    // MARK: - DSP

    private struct Processed {
        let guide: [Float]
        let side: [Float]
    }

    private static func process(_ source: StereoAudio, parameters: Parameters) throws -> Processed {
        let count = source.left.count
        let n = vDSP_Length(count)
        var mid = [Float](repeating: 0, count: count)
        var side = [Float](repeating: 0, count: count)
        vDSP_vadd(source.left, 1, source.right, 1, &mid, 1, n)
        vDSP_vsub(source.right, 1, source.left, 1, &side, 1, n) // left - right
        var half: Float = 0.5
        vDSP_vsmul(mid, 1, &half, &mid, 1, n)
        vDSP_vsmul(side, 1, &half, &side, 1, n)

        var midEnergy: Float = 0
        var sideEnergy: Float = 0
        vDSP_svesq(mid, 1, &midEnergy, n)
        vDSP_svesq(side, 1, &sideEnergy, n)
        guard midEnergy > 0 else { throw CenterChannelError.monoSource }
        let sideDB = 10 * log10(max(sideEnergy, Float.leastNormalMagnitude) / midEnergy)
        if sideDB < parameters.monoThresholdDB { throw CenterChannelError.monoSource }

        // Instrumental: side normalized to the mix peak, never clipping.
        var peakL: Float = 0
        var peakR: Float = 0
        var sidePeak: Float = 0
        vDSP_maxmgv(source.left, 1, &peakL, n)
        vDSP_maxmgv(source.right, 1, &peakR, n)
        vDSP_maxmgv(side, 1, &sidePeak, n)
        let mixPeak = min(max(peakL, peakR), parameters.peakCeiling)
        if sidePeak > 0 {
            var gain = mixPeak / sidePeak
            vDSP_vsmul(side, 1, &gain, &side, 1, n)
        }

        let guide = bandPass(mid, sampleRate: source.sampleRate, parameters: parameters)
        return Processed(guide: guide, side: side)
    }

    /// Zero-phase band-pass (high-pass + low-pass, run forward and backward) so the guide keeps its timing.
    private static func bandPass(_ input: [Float], sampleRate: Double, parameters: Parameters) -> [Float] {
        let sections = [
            biquad(highPass: true, frequency: parameters.bandLow, sampleRate: sampleRate, q: parameters.filterQ),
            biquad(highPass: false, frequency: parameters.bandHigh, sampleRate: sampleRate, q: parameters.filterQ),
        ]
        var signal = input
        for _ in 0..<2 { // forward, then backward on the reversed signal
            for section in sections { signal = filter(signal, coefficients: section) }
            signal.reverse()
        }
        return signal
    }

    /// RBJ cookbook biquad, normalized as [b0, b1, b2, a1, a2].
    private static func biquad(highPass: Bool, frequency: Double, sampleRate: Double, q: Double) -> [Float] {
        let omega = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosine = cos(omega)
        let b0: Double, b1: Double, b2: Double
        if highPass {
            b0 = (1 + cosine) / 2; b1 = -(1 + cosine); b2 = (1 + cosine) / 2
        } else {
            b0 = (1 - cosine) / 2; b1 = 1 - cosine; b2 = (1 - cosine) / 2
        }
        let a0 = 1 + alpha
        return [b0 / a0, b1 / a0, b2 / a0, -2 * cosine / a0, (1 - alpha) / a0].map { Float($0) }
    }

    private static func filter(_ input: [Float], coefficients: [Float]) -> [Float] {
        let count = input.count
        var padded = [Float](repeating: 0, count: count + 2)
        padded.replaceSubrange(2..<count + 2, with: input)
        var result = [Float](repeating: 0, count: count + 2)
        vDSP_deq22(padded, 1, coefficients, &result, 1, vDSP_Length(count))
        return Array(result[2...])
    }

    // MARK: - Writing

    /// Writes float32 PCM WAV in chunks. All `channels` have the same length.
    private static func write(channels: [[Float]], sampleRate: Double, to url: URL, chunk: Int) throws {
        guard let first = channels.first,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: AVAudioChannelCount(channels.count), interleaved: false) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)),
              let data = buffer.floatChannelData else { throw CocoaError(.fileWriteUnknown) }
        var position = 0
        while position < first.count {
            let frames = min(chunk, first.count - position)
            for (index, channel) in channels.enumerated() {
                channel.withUnsafeBufferPointer { data[index].update(from: $0.baseAddress! + position, count: frames) }
            }
            buffer.frameLength = AVAudioFrameCount(frames)
            try file.write(from: buffer)
            position += frames
        }
    }

    // MARK: - Cache key

    /// Stable (non-randomized) FNV-1a hash of path, modification date and trim range.
    private static func cacheKey(url: URL, trim: ClosedRange<TimeInterval>) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let text = "\(url.standardizedFileURL.path)|\(modified)|\(trim.lowerBound)|\(trim.upperBound)"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
