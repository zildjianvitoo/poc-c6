//
//  PreparationPipelineChecks.swift
//  poc-c6
//
//  End-to-end song preparation on the Mac: a stereo "song" (centered vocal melody, hard-panned
//  backing) → CenterChannelStemRepository → CrepeAnalysisRepository → SliceSegments →
//  ComputeTransposition → AudioTranspositionRepositoryImpl, via PrepareSongUseCase.
//

import AVFoundation

nonisolated enum PreparationPipelineChecks {
    static func run(modelURL: URL) async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "PreparationPipeline", message: message) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prep-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 30 s song: melody (MIDI, start, length) in the centre, backing hard left/right.
        let melody: [(Int, Double, Double)] = [
            (60, 6.0, 0.9), (64, 7.1, 0.9), (67, 8.2, 1.4), (64, 9.9, 0.9), (62, 11.0, 1.6),
            // 4 s instrumental interlude
            (65, 16.8, 0.9), (69, 17.9, 0.9), (67, 19.0, 1.4), (65, 20.7, 0.9), (64, 21.8, 1.8),
        ]
        let rate = 48_000.0, length = Int(30 * rate)
        var left = [Float](repeating: 0, count: length), right = left
        for i in 0..<length {
            let t = Double(i) / rate
            left[i] = 0.12 * Float(sin(2 * .pi * 110 * t))                 // bass, hard left
            right[i] = 0.08 * Float(sin(2 * .pi * 880 * t + sin(t * 3)))   // lead synth, hard right
        }
        for (midi, start, duration) in melody {
            let frequency = 440 * pow(2, (Double(midi) - 69) / 12)
            for i in Int(start * rate)..<Int((start + duration) * rate) {
                let t = Double(i) / rate - start
                let envelope = Float(min(1, t / 0.02, (duration - t) / 0.02))
                let voice = 0.3 * envelope * Float(sin(2 * .pi * frequency * t))
                left[i] += voice
                right[i] += voice
            }
        }
        let songURL = directory.appendingPathComponent("song.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length))!
        buffer.frameLength = AVAudioFrameCount(length)
        left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: length) }
        right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: length) }
        try AVAudioFile(forWriting: songURL, settings: format.settings).write(from: buffer)

        // A low voice: the melody (C4–A4) should be shifted down.
        let range = VocalRange(lowestMIDI: 45, highestMIDI: 57)
        let useCase = PrepareSongUseCase(
            separation: CenterChannelStemRepository(directory: directory),
            analysis: CrepeAnalysisRepository(modelURL: modelURL),
            fallbackAnalysis: nil,
            transposition: AudioTranspositionRepositoryImpl(cacheDirectory: directory.appendingPathComponent("transposed")))
        let started = Date()
        let song = try await useCase.execute(audioURL: songURL, trimRange: 5...25, vocalRange: range)
        let seconds = Date().timeIntervalSince(started)

        try check(song.validate().isEmpty, "PreparedSong is valid: \(song.validate())")
        try check(song.separationMethod == .centerChannelCancellation, "center-channel method")
        let notes = song.segments.flatMap(\.targetNotes)
        // The guide is simplified into singable blocks: compare against the simplified melody.
        let simplified = SimplifyGuideUseCase().execute(melody.map {
            TargetMIDINote(midiNote: $0.0, startTime: $0.1 - 5, duration: $0.2)
        })
        let expected = simplified.map(\.midiNote)
        try check(notes.map(\.midiNote) == expected, "guide notes \(notes.map(\.midiNote)) == \(expected)")
        let worstStart = zip(notes, simplified).map { abs($0.startTime - $1.startTime) }.max() ?? 1
        try check(worstStart < 0.08, String(format: "note starts within 80 ms (worst %.0f ms)", worstStart * 1000))
        try check(song.segments.contains(where: \.isInstrumentalOnly), "interlude became an instrumental-only segment")
        try check(song.transposition.totalSemitones < 0, "transposed down for a low voice: \(song.transposition)")
        let transposedOutside = notes.filter {
            let pitch = Float(song.transposition.transposed($0))
            return pitch < range.lowestMIDI || pitch > range.highestMIDI
        }.count
        try check(transposedOutside == 0, "all notes inside the range after transposition (\(transposedOutside) outside)")
        for url in [song.earphoneMixURL, song.instrumentalURL] {
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            try check(abs(duration - 20) < 0.001, "\(url.lastPathComponent) is 20 s (\(duration))")
        }
        print(String(format: "  pipeline: %d notes, %d segments, plan %@, %.2f s", notes.count, song.segments.count,
                     "\(song.transposition.octaveShift) oct \(song.transposition.semitoneShift) st", seconds))
        try? FileManager.default.removeItem(at: directory)
        return count
    }
}
