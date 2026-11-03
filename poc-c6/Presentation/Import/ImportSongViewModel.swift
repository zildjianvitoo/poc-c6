//
//  ImportSongViewModel.swift
//  poc-c6
//
//  Import → trim → prepare (PRD §5.2–5.4): the user picks a song they own, chooses 15–60 s
//  while seeing (and hearing) the synced lyrics of that part, and PrepareSongUseCase separates
//  it, extracts the guide, slices segments and transposes it to the saved vocal range.
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

    enum LyricsState: Equatable {
        case idle
        case loading
        case found(SongLyrics)
        case notFound
        case failed(UserFacingError)
    }

    /// PRD §5.2: the trimmed selection is 15–60 s.
    static let minimumLength: TimeInterval = 15
    static let maximumLength: TimeInterval = 60
    private static let defaultLength: TimeInterval = 30

    /// How often the karaoke highlight follows the selection preview (30 fps).
    private static let playbackRefresh: Duration = .milliseconds(33)

    private(set) var status: Status = .idle
    var selectionStart: TimeInterval = 0 { didSet { selectionChanged() } }
    var selectionLength: TimeInterval = defaultLength { didSet { selectionChanged() } }
    private(set) var lyrics: LyricsState = .idle
    /// Manual lyrics search, prefilled from the file's metadata or name.
    var lyricsTitle = ""
    var lyricsArtist = ""
    /// Position in the song while the selection preview plays, nil otherwise.
    private(set) var playbackTime: TimeInterval?

    @ObservationIgnored private let inspector: any AudioFileInspecting
    @ObservationIgnored private let lyricsProvider: any LyricsProviding
    @ObservationIgnored private let previewer: any AudioPreviewing
    @ObservationIgnored private let prepare: PrepareSongUseCase
    @ObservationIgnored private let vocalRange: () -> VocalRange?
    /// The prepared song and its stems before transposition.
    @ObservationIgnored private let onPrepared: (PreparedSong, SeparatedStems) -> Void
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var lyricsLookup: Task<Void, Never>?
    @ObservationIgnored private var playback: Task<Void, Never>?

    init(inspector: any AudioFileInspecting, lyrics: any LyricsProviding, previewer: any AudioPreviewing,
         prepare: PrepareSongUseCase,
         vocalRange: @escaping () -> VocalRange?, onPrepared: @escaping (PreparedSong, SeparatedStems) -> Void) {
        self.inspector = inspector
        self.lyricsProvider = lyrics
        self.previewer = previewer
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
                lyricsTitle = audio.title
                lyricsArtist = audio.artist ?? ""
                searchLyrics()
            } catch {
                status = .failed(Self.userFacing(error))
            }
        }
    }

    func prepareSelection() {
        guard let audio, let range = vocalRange() else { return }
        stopSelectionPreview()
        let trim = selectionStart...(selectionStart + selectionLength)
        status = .preparing(step: "Starting…")
        preparation = Task { [prepare] in
            do {
                let (song, stems) = try await prepare.executeReturningStems(audioURL: audio.url, trimRange: trim, vocalRange: range) { step in
                    Task { @MainActor in
                        if case .preparing = self.status { self.status = .preparing(step: step) }
                    }
                }
                try Task.checkCancellation()
                onPrepared(song, stems)
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
        stopSelectionPreview()
        lyricsLookup?.cancel()
        lyrics = .idle
        status = .idle
    }

    // MARK: - Lyrics

    /// Looks up synced lyrics for `lyricsTitle` / `lyricsArtist` (also the manual search).
    func searchLyrics() {
        guard let audio else { return }
        let title = lyricsTitle.trimmingCharacters(in: .whitespaces)
        let artist = lyricsArtist.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            lyrics = .notFound
            return
        }
        lyricsLookup?.cancel()
        lyrics = .loading
        lyricsLookup = Task { [lyricsProvider] in
            do {
                let found = try await lyricsProvider.lyrics(title: title, artist: artist.isEmpty ? nil : artist,
                                                            duration: audio.duration)
                try Task.checkCancellation()
                lyrics = found.map(LyricsState.found) ?? .notFound
            } catch is CancellationError {
            } catch {
                lyrics = .failed(.lyricsUnavailable)
            }
        }
    }

    /// Whether a lyric line is (partly) inside the chosen part.
    func isInSelection(_ line: LyricLine) -> Bool {
        line.end > selectionStart && line.start < selectionStart + selectionLength
    }

    /// The first line of the chosen part, to scroll to.
    var firstSelectedLineID: Int? {
        guard case .found(let song) = lyrics else { return nil }
        return song.lines.first(where: isInSelection)?.id
    }

    /// The line being sung during the selection preview.
    var activeLineID: Int? {
        guard let time = playbackTime, case .found(let song) = lyrics else { return nil }
        return song.lines.last { $0.start <= time && time < $0.end }?.id
    }

    // MARK: - Selection preview

    var isPlayingSelection: Bool { playback != nil }

    /// Plays the chosen part of the original song; the lyrics follow it.
    func toggleSelectionPreview() {
        if isPlayingSelection {
            stopSelectionPreview()
            return
        }
        guard let audio, (try? previewer.play(audio.url, from: selectionStart)) != nil else { return }
        let end = selectionStart + selectionLength
        playbackTime = selectionStart
        playback = Task { [previewer] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.playbackRefresh)
                guard let time = previewer.currentTime, time < end else { break }
                playbackTime = time
            }
            if !Task.isCancelled { stopSelectionPreview() }
        }
    }

    func stopSelectionPreview() {
        playback?.cancel()
        playback = nil
        previewer.stop()
        playbackTime = nil
    }

    private func selectionChanged() {
        clampSelection()
        // Moving the selection ends the preview of the old part.
        if isPlayingSelection { stopSelectionPreview() }
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
