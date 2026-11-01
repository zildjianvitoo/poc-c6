//
//  ClickTrack.swift
//  poc-c6
//
//  Short, sharp clicks at known times for the sync click test.
//

import AVFoundation

nonisolated enum ClickTrack {
    /// One click per second from 1 s to 8 s: 1 s apart keeps each click's search window clear
    /// of its neighbours even for errors up to ±0.45 s.
    static let clickTimes: [TimeInterval] = (1...8).map(Double.init)
    static let duration: TimeInterval = 9.5
    private static let sampleRate = 48_000.0

    /// Writes (once) and returns the click track WAV.
    static func url() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SyncClicks.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * sampleRate)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = buffer.frameCapacity
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(buffer.frameLength) { samples[i] = 0 }
        // 3 ms of 2 kHz at full level: easy to hear, sharp onset, far above room noise.
        let clickLength = Int(0.003 * sampleRate)
        for time in clickTimes {
            let start = Int(time * sampleRate)
            for i in 0..<clickLength {
                samples[start + i] = Float(sin(2 * Double.pi * 2_000 * Double(i) / sampleRate))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
