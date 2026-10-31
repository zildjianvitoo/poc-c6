//
//  SynthesizedDemoRepository.swift
//  poc-c6
//
//  Developer fallback demo (PRD §3, §7.5). Owner: Zildjian Vito (ZV-06).
//  Produces real audio files whose guide is known exactly (DomainFixtures.segments),
//  so recording, evaluation and comping can be tested before the Track A demo exists.
//

import Foundation

nonisolated final class SynthesizedDemoRepository: StemSeparationRepository, Sendable {
    let segments: [SongSegment]
    let duration: TimeInterval
    let synthesizer: DemoAudioSynthesizer
    private let directory: URL

    init(segments: [SongSegment] = DomainFixtures.segments,
         duration: TimeInterval = DomainFixtures.preparedSong.duration,
         synthesizer: DemoAudioSynthesizer = DemoAudioSynthesizer(),
         directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SynthesizedDemo", isDirectory: true)) {
        self.segments = segments
        self.duration = duration
        self.synthesizer = synthesizer
        self.directory = directory
    }

    /// Stems in the original key. The input file and trim range are ignored: the demo is always the same song.
    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        let files = try await renderInBackground(semitoneShift: 0)
        return SeparatedStems(mixURL: files.mix, vocalGuideURL: files.vocal,
                              instrumentalURL: files.instrumental, method: .synthesized)
    }

    /// A ready-to-record song, skipping separation and analysis.
    /// The earphone mix and instrumental are rendered with `transposition.semitoneShift`, as the contract requires.
    func preparedSong(transposition: TranspositionPlan = .none) async throws -> PreparedSong {
        let files = try await renderInBackground(semitoneShift: transposition.semitoneShift)
        let song = PreparedSong(earphoneMixURL: files.mix, instrumentalURL: files.instrumental,
                                segments: segments, transposition: transposition,
                                duration: duration, separationMethod: .synthesized)
        Contract.assertValid(song.validate())
        return song
    }

    // MARK: - Private

    private struct Files: Sendable {
        let mix: URL
        let vocal: URL
        let instrumental: URL
    }

    /// Rendering takes a moment; keep it off the caller's actor (usually the main actor).
    private func renderInBackground(semitoneShift: Int) async throws -> Files {
        try await Task.detached(priority: .userInitiated) { [self] in
            try render(semitoneShift: semitoneShift)
        }.value
    }

    /// Renders once per semitone shift and reuses the files afterwards.
    private func render(semitoneShift: Int) throws -> Files {
        let folder = directory.appendingPathComponent("shift\(semitoneShift)", isDirectory: true)
        let files = Files(mix: folder.appendingPathComponent("mix.wav"),
                          vocal: folder.appendingPathComponent("vocal.wav"),
                          instrumental: folder.appendingPathComponent("instrumental.wav"))
        let fileManager = FileManager.default
        if [files.mix, files.vocal, files.instrumental].allSatisfy({ fileManager.fileExists(atPath: $0.path) }) {
            return files
        }

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let stems = synthesizer.render(notes: segments.flatMap(\.targetNotes),
                                       duration: duration, semitoneShift: semitoneShift)
        try synthesizer.write(stems.vocal, to: files.vocal)
        try synthesizer.write(stems.instrumental, to: files.instrumental)
        try synthesizer.write(stems.mix, to: files.mix)
        return files
    }
}
