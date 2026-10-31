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
    private(set) var compingPlan: CompingCompositionPlan?

    init(container: AppContainer) {
        self.container = container
        step = container.vocalRange.load() == nil ? .vocalRange : .importSong
    }

    /// Vocal range screen (Ikzaz) saved a range.
    func vocalRangeSaved() {
        step = .importSong
    }

    /// Import/prep screen (Ikzaz) finished preparing a song.
    func songPrepared(_ song: PreparedSong) {
        Contract.assertValid(song.validate())
        preparedSong = song
        step = .ready
    }

    /// Loads the synthesized demo song (ZV-06) and continues as if it was imported.
    func loadDemoSong() async {
        do {
            songPrepared(try await container.demo.preparedSong())
        } catch {
            assertionFailure("Synthesized demo failed: \(error)")
        }
    }

    /// Ready screen: user tapped Record.
    func startRecording() {
        guard preparedSong != nil else { return }
        container.takeLog.clear()
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
        compingPlan = nil
        container.takeLog.clear()
        step = .importSong
    }

    func retestVocalRange() {
        step = .vocalRange
    }
}
