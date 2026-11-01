//
//  DemoAudioSynthesizer.swift
//  poc-c6
//
//  Renders the synthesized demo stems. Owner: Zildjian Vito (ZV-06).
//  The "vocal" is a tone that follows the guide notes exactly, so the guide is known
//  without any analysis. The instrumental has a kick on every beat to make
//  vocal/instrumental sync easy to hear.
//

import AVFAudio
import Foundation

nonisolated struct DemoAudioSynthesizer {
    struct Stems {
        let vocal: [Float]
        let instrumental: [Float]
        let mix: [Float]
    }

    var sampleRate: Double = 48_000
    var beatsPerMinute: Double = 120
    var vocalLevel: Float = 0.3
    var padLevel: Float = 0.06
    var kickLevel: Float = 0.5

    /// One chord per bar (4 beats), MIDI notes in the original key.
    var chordProgression: [[Int]] = [
        [48, 52, 55], // C
        [53, 57, 60], // F
        [55, 59, 62], // G
        [57, 60, 64], // Am
    ]

    /// `semitoneShift` is rendered into every stem, like the real earphone mix and instrumental.
    func render(notes: [TargetMIDINote], duration: TimeInterval, semitoneShift: Int) -> Stems {
        let frameCount = Int(duration * sampleRate)
        var vocal = [Float](repeating: 0, count: frameCount)
        var instrumental = [Float](repeating: 0, count: frameCount)

        for note in notes {
            addTone(to: &vocal, midiNote: note.midiNote + semitoneShift, start: note.startTime,
                    duration: note.duration, level: vocalLevel, harmonics: [1, 0.3, 0.15])
        }

        let beat = 60 / beatsPerMinute
        let bar = beat * 4
        var barStart: TimeInterval = 0
        var barIndex = 0
        while barStart < duration {
            let chord = chordProgression[barIndex % chordProgression.count]
            for midiNote in chord {
                addTone(to: &instrumental, midiNote: midiNote + semitoneShift, start: barStart,
                        duration: min(bar, duration - barStart), level: padLevel, harmonics: [1, 0.2])
            }
            barStart += bar
            barIndex += 1
        }

        var beatTime: TimeInterval = 0
        while beatTime < duration {
            addKick(to: &instrumental, at: beatTime)
            beatTime += beat
        }

        var mix = zip(vocal, instrumental).map { $0 + $1 }
        let peak = mix.map(abs).max() ?? 0
        if peak > 0.99 {
            let scale = 0.99 / peak
            mix = mix.map { $0 * scale }
        }
        return Stems(vocal: vocal, instrumental: instrumental, mix: mix)
    }

    /// Writes mono 32-bit float WAV.
    func write(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    // MARK: - Private

    private func addTone(to samples: inout [Float], midiNote: Int, start: TimeInterval,
                         duration: TimeInterval, level: Float, harmonics: [Float]) {
        let frequency = 440 * pow(2, (Double(midiNote) - 69) / 12)
        let first = max(0, Int(start * sampleRate))
        let last = min(samples.count, Int((start + duration) * sampleRate))
        guard first < last else { return }
        let fade = min(Int(0.02 * sampleRate), (last - first) / 2)
        let harmonicSum = harmonics.reduce(0, +)

        for index in first..<last {
            let time = Double(index - first) / sampleRate
            var value: Float = 0
            for (order, weight) in harmonics.enumerated() {
                value += weight * Float(sin(2 * .pi * frequency * Double(order + 1) * time))
            }
            let fromStart = index - first
            let toEnd = last - 1 - index
            let envelope = Float(min(1, Double(min(fromStart, toEnd)) / Double(max(fade, 1))))
            samples[index] += level * envelope * value / harmonicSum
        }
    }

    private func addKick(to samples: inout [Float], at start: TimeInterval) {
        let first = Int(start * sampleRate)
        let length = Int(0.12 * sampleRate)
        for offset in 0..<length where first + offset < samples.count {
            let time = Double(offset) / sampleRate
            // Pitch drops from 120 Hz to ~50 Hz with an exponential decay.
            let frequency = 50 + 70 * exp(-time * 40)
            let envelope = Float(exp(-time * 30))
            samples[first + offset] += kickLevel * envelope * Float(sin(2 * .pi * frequency * time))
        }
    }
}
