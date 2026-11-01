//
//  VocalRangeViewModel.swift
//  poc-c6
//
//  Vocal range test (PRD §5.1): lowest comfortable note, then highest, each held ~2 s.
//  The result is saved as VocalRange and used to transpose the song (PRD §5.4).
//

import Foundation
import Observation

@Observable
final class VocalRangeViewModel {
    enum Prompt: Equatable {
        case lowest
        case highest
    }

    enum Status: Equatable {
        case idle
        case listening
        /// The note for the current prompt was held long enough.
        case captured(Float)
        /// Both notes captured; ready to save.
        case finished(VocalRange)
        case failed(String)
    }

    /// The highest note must be at least this far above the lowest (in semitones), or the
    /// prompts were probably mixed up or the same note was sung twice.
    static let minimumSpan: Float = 3

    private(set) var prompt: Prompt = .lowest
    private(set) var status: Status = .idle
    private(set) var liveMIDI: Float?
    /// 0…1 while holding a stable note.
    private(set) var holdProgress: Double = 0
    private(set) var lowestMIDI: Float?

    @ObservationIgnored private let source: any LivePitchSource
    @ObservationIgnored private let repository: any VocalRangeRepository
    @ObservationIgnored private let configuration: PoCConfiguration
    @ObservationIgnored private let onSaved: () -> Void
    @ObservationIgnored private var listening: Task<Void, Never>?

    init(source: any LivePitchSource, repository: any VocalRangeRepository,
         configuration: PoCConfiguration, onSaved: @escaping () -> Void) {
        self.source = source
        self.repository = repository
        self.configuration = configuration
        self.onSaved = onSaved
    }

    var title: String {
        prompt == .lowest ? "Sing your lowest comfortable note" : "Sing your highest comfortable note"
    }

    var liveNoteName: String? {
        liveMIDI.map { PitchMath.noteName(midi: Int($0.rounded())) }
    }

    /// Starts listening for the current prompt (also used for Retry).
    func listen() {
        stopListening()
        status = .listening
        holdProgress = 0
        liveMIDI = nil
        let configuration = configuration
        listening = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await source.start()
                var detector = DetectVocalRangeUseCase(configuration: configuration)
                for await sample in samples {
                    guard !Task.isCancelled else { break }
                    let note = detector.ingest(sample)
                    liveMIDI = detector.latestMIDI
                    holdProgress = min(1, detector.stableDuration / DetectVocalRangeUseCase.requiredDuration)
                    if let note {
                        captured(note)
                        break
                    }
                }
            } catch {
                status = .failed("The microphone couldn't start: \(error.localizedDescription)")
            }
            source.stop()
        }
    }

    /// After the lowest note: go to the highest prompt.
    func next() {
        guard case .captured(let note) = status, prompt == .lowest else { return }
        lowestMIDI = note
        prompt = .highest
        listen()
    }

    func save() {
        guard case .finished(let range) = status else { return }
        repository.save(range)
        onSaved()
    }

    /// Start over from the lowest note.
    func restart() {
        stopListening()
        prompt = .lowest
        lowestMIDI = nil
        status = .idle
    }

    func stopListening() {
        listening?.cancel()
        listening = nil
        source.stop()
    }

    private func captured(_ note: Float) {
        holdProgress = 1
        guard prompt == .highest, let lowestMIDI else {
            status = .captured(note)
            return
        }
        guard note - lowestMIDI >= Self.minimumSpan else {
            status = .failed("That note is not higher than your lowest note (\(PitchMath.noteName(midi: Int(lowestMIDI.rounded())))). Try a higher one.")
            return
        }
        status = .finished(VocalRange(lowestMIDI: lowestMIDI, highestMIDI: note))
    }
}
