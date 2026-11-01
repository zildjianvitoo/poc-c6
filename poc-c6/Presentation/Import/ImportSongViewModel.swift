//
//  ImportSongViewModel.swift
//  poc-c6
//
//  Import → trim → prepare (PRD §5.2–5.4): the user picks a song they own, chooses 15–60 s,
//  and PrepareSongUseCase separates it, extracts the guide, slices segments and transposes it
//  to the saved vocal range.
//

import Foundation
import Observation

/// Data-layer errors that know how to explain themselves on screen.
nonisolated protocol UserFacingConvertible: Error {
    var userFacingError: UserFacingError { get }
}

@Observable
final class ImportSongViewModel {
    enum Status: Equatable {
        case idle
        case loading
        case trimming(ImportedAudio)
        case preparing(step: String)
        case failed(UserFacingError)
    }

    /// PRD §5.2: the trimmed selection is 15–60 s.
    static let minimumLength: TimeInterval = 15
    static let maximumLength: TimeInterval = 60
    private static let defaultLength: TimeInterval = 30

    private(set) var status: Status = .idle
    var selectionStart: TimeInterval = 0 { didSet { clampSelection() } }
    var selectionLength: TimeInterval = defaultLength { didSet { clampSelection() } }

    @ObservationIgnored private let inspector: any AudioFileInspecting
    @ObservationIgnored private let prepare: PrepareSongUseCase
    @ObservationIgnored private let vocalRange: () -> VocalRange?
    @ObservationIgnored private let onPrepared: (PreparedSong) -> Void
    @ObservationIgnored private var preparation: Task<Void, Never>?

    init(inspector: any AudioFileInspecting, prepare: PrepareSongUseCase,
         vocalRange: @escaping () -> VocalRange?, onPrepared: @escaping (PreparedSong) -> Void) {
        self.inspector = inspector
        self.prepare = prepare
        self.vocalRange = vocalRange
        self.onPrepared = onPrepared
    }

    var audio: ImportedAudio? {
        if case .trimming(let audio) = status { audio } else { nil }
    }

    var maximumStart: TimeInterval {
        max(0, (audio?.duration ?? 0) - Self.minimumLength)
    }

    var maximumLengthForStart: TimeInterval {
        min(Self.maximumLength, (audio?.duration ?? 0) - selectionStart)
    }

    func picked(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        status = .loading
        Task {
            do {
                let audio = try await inspector.importFile(at: url)
                guard audio.duration >= Self.minimumLength else {
                    status = .failed(.songTooShort(minimumSeconds: Int(Self.minimumLength)))
                    return
                }
                selectionStart = 0
                selectionLength = min(Self.defaultLength, audio.duration)
                status = .trimming(audio)
                clampSelection()
            } catch {
                status = .failed(Self.userFacing(error))
            }
        }
    }

    func prepareSelection() {
        guard let audio, let range = vocalRange() else { return }
        let trim = selectionStart...(selectionStart + selectionLength)
        status = .preparing(step: "Starting…")
        preparation = Task { [prepare] in
            do {
                let song = try await prepare.execute(audioURL: audio.url, trimRange: trim, vocalRange: range) { step in
                    Task { @MainActor in
                        if case .preparing = self.status { self.status = .preparing(step: step) }
                    }
                }
                try Task.checkCancellation()
                onPrepared(song)
            } catch is CancellationError {
                status = .trimming(audio)
            } catch {
                status = .failed(Self.userFacing(error))
            }
        }
    }

    func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
    }

    func reset() {
        cancelPreparation()
        status = .idle
    }

    private func clampSelection() {
        guard let audio else { return }
        let start = min(max(0, selectionStart), max(0, audio.duration - Self.minimumLength))
        let length = min(max(Self.minimumLength, selectionLength), min(Self.maximumLength, audio.duration - start))
        if start != selectionStart { selectionStart = start }
        if length != selectionLength { selectionLength = length }
    }

    private static func userFacing(_ error: any Error) -> UserFacingError {
        if let convertible = error as? any UserFacingConvertible { return convertible.userFacingError }
        switch error {
        case AudioImportError.protectedContent: return .protectedFile
        case AudioImportError.noAudio, AudioImportError.unreadable: return .unreadableFile
        case let violation as ContractViolation where violation.contract == "Preparation" && violation.message.contains("vocal"):
            return .noVocalDetected
        case let violation as ContractViolation where violation.message.contains("guide notes"):
            return .noVocalDetected
        default: return .unreadableFile
        }
    }
}
