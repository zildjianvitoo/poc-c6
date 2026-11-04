//
//  AppFlow.swift
//  poc-c6
//
//  The app's linear flow and the data handed between steps. Owner: Zildjian Vito (ZV-04).
//  Screens call these methods instead of navigating themselves, so every handoff
//  goes through one place and is checked against the contracts.
//

import Foundation
import Observation

@Observable
final class AppFlow {
    enum Step: Equatable {
        case vocalRange
        case importSong
        case ready
        case recording
        case export
    }

    let container: AppContainer
    private(set) var step: Step
    private(set) var preparedSong: PreparedSong?
    /// Stems of `preparedSong` before transposition; nil for the synthesized demo.
    private(set) var separatedStems: SeparatedStems?
    private(set) var compingPlan: CompingCompositionPlan?

    init(container: AppContainer) {
        self.container = container
        step = container.vocalRange.load() == nil ? .vocalRange : .importSong
        // Leftovers from a session that ended in a crash.
        SessionFiles.cleanUp()
        container.modelPrewarmer?.start()
    }

    /// Vocal range screen (Ikzaz) saved a range.
    func vocalRangeSaved() {
        step = .importSong
    }

    /// Import/prep screen (Ikzaz) finished preparing a song.
    func songPrepared(_ song: PreparedSong, stems: SeparatedStems? = nil) {
        Contract.assertValid(song.validate())
        preparedSong = song
        separatedStems = stems
        step = .ready
    }

    /// Loads the synthesized demo song (ZV-06), transposed to the user's vocal range (PRD §5.4),
    /// and continues as if it was imported.
    func loadDemoSong() async {
        do {
            let notes = container.demo.segments.flatMap(\.targetNotes)
            let plan = try container.vocalRange.load().map {
                try ComputeTranspositionUseCase().execute(notes: notes, vocalRange: $0)
            } ?? .none
            songPrepared(try await container.demo.preparedSong(transposition: plan))
        } catch {
            assertionFailure("Synthesized demo failed: \(error)")
        }
    }

    /// Ready screen: user tapped Record. A new session starts, so files from the last one go (ZV-16).
    func startRecording() {
        guard let preparedSong else { return }
        container.simulatedSinger?.prepare(song: preparedSong)
        container.takeLog.clear()
        SessionFiles.cleanUp()
        try? SessionFiles.prepareDirectory()
        step = .recording
    }

    /// Recording screen (Takin) ended the session with at least one passed segment.
    func sessionEnded(with plan: CompingCompositionPlan) {
        Contract.assertValid(plan.validate())
        compingPlan = plan
        step = .export
    }

    /// Recording screen (Takin) ended with nothing passed, or the user discarded the session.
    func sessionDiscarded() {
        container.takeLog.clear()
        step = .ready
    }

    func startOver() {
        preparedSong = nil
        separatedStems = nil
        compingPlan = nil
        container.takeLog.clear()
        step = .importSong
    }

    func retestVocalRange() {
        step = .vocalRange
    }

    /// Debug Settings saved new values (ZV-15). Takes effect the next time a value is read.
    func updateConfiguration(_ configuration: PoCConfiguration, store: ConfigurationStore = ConfigurationStore()) {
        container.configuration = configuration
        store.save(configuration)
    }
}
