//
//  KeySelectionViewModel.swift
//  poc-c6
//

import Foundation
import Observation

@Observable
final class KeySelectionViewModel {
    let choices: PrepareSongUseCase.Choices
    private(set) var selectedIndex: Int?
    private(set) var playingIndex: Int?
    private(set) var loadingIndex: Int?
    private(set) var error: UserFacingError?

    @ObservationIgnored private let previewer: any AudioPreviewing
    @ObservationIgnored private let onChoose: (PreparedSong) -> Void
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init(choices: PrepareSongUseCase.Choices, previewer: any AudioPreviewing,
         onChoose: @escaping (PreparedSong) -> Void) {
        self.choices = choices
        self.previewer = previewer
        self.onChoose = onChoose
    }

    func listen(_ index: Int) {
        let wasActive = playingIndex == index || loadingIndex == index
        stop()
        guard !wasActive, choices.options.indices.contains(index), let excerpt = choices.excerpt else { return }
        let token = generation
        loadingIndex = index
        error = nil
        playback = Task { [self] in
            do {
                try await previewer.play(choices.options[index].song.instrumentalURL, excerpt: excerpt) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.playingIndex = nil
                        self.loadingIndex = nil
                    }
                }
                guard !Task.isCancelled, generation == token else { return }
                loadingIndex = nil
                playingIndex = index
            } catch is CancellationError {
                // A new choice or leaving the screen cancelled this preview.
            } catch {
                guard generation == token else { return }
                loadingIndex = nil
                playingIndex = nil
                self.error = .keyPreviewFailed
            }
        }
    }

    func select(_ index: Int) {
        guard choices.options.indices.contains(index) else { return }
        selectedIndex = index
    }

    func confirm() {
        guard let index = selectedIndex, choices.options.indices.contains(index) else { return }
        stop()
        let song = choices.options[index].song
        Contract.assertValid(song.validate())
        onChoose(song)
    }

    func stop() {
        generation = UUID()
        playback?.cancel()
        playback = nil
        previewer.stop()
        playingIndex = nil
        loadingIndex = nil
    }
}
