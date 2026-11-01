//
//  AudioFileInspector.swift
//  poc-c6
//
//  Copies a file picked in Files into the app and reads its duration and a coarse waveform
//  for the trimmer (PRD §5.2). Audio and video files (audio track) are supported; DRM is rejected.
//

import AVFoundation

nonisolated struct AudioFileInspector: AudioFileInspecting {
    /// Bars in the trimmer waveform.
    static let waveformBins = 160
    /// The waveform only needs a coarse picture, so read at a low rate
    /// (AVAssetReader accepts 8–192 kHz; lower values throw an Objective-C exception).
    private static let analysisSampleRate = 8_000.0

    static var importDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
    }

    func importFile(at pickedURL: URL) async throws -> ImportedAudio {
        let copy = try copyIntoApp(pickedURL)
        let asset = AVURLAsset(url: copy)
        let (duration, isProtected) = try await asset.load(.duration, .hasProtectedContent)
        guard !isProtected else { throw AudioImportError.protectedContent }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw AudioImportError.noAudio }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw AudioImportError.unreadable }
        let waveform = try await Task.detached(priority: .userInitiated) {
            try Self.readWaveform(asset: asset, track: track, duration: seconds)
        }.value
        return ImportedAudio(url: copy, name: pickedURL.deletingPathExtension().lastPathComponent,
                             duration: seconds, waveform: waveform)
    }

    /// Files from the picker are security-scoped and may vanish; work on a private copy.
    private func copyIntoApp(_ pickedURL: URL) throws -> URL {
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }
        let directory = Self.importDirectory
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(pickedURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: pickedURL, to: destination)
        } catch {
            throw AudioImportError.unreadable
        }
        return destination
    }

    private static func readWaveform(asset: AVAsset, track: AVAssetTrack, duration: TimeInterval) throws -> [Float] {
        guard let reader = try? AVAssetReader(asset: asset) else { throw AudioImportError.unreadable }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: analysisSampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        guard reader.canAdd(output) else { throw AudioImportError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw AudioImportError.unreadable }

        let samplesPerBin = max(1, Int(duration * analysisSampleRate) / waveformBins)
        var bins: [Float] = []
        var peak: Float = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for value in data {
                peak = max(peak, abs(value))
                count += 1
                if count == samplesPerBin {
                    bins.append(peak)
                    peak = 0
                    count = 0
                }
            }
        }
        guard reader.status == .completed else { throw AudioImportError.unreadable }
        if count > 0 { bins.append(peak) }
        let loudest = bins.max() ?? 0
        return loudest > 0 ? bins.map { $0 / loudest } : bins
    }
}
