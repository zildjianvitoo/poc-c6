//
//  AudioFileInspecting.swift
//  poc-c6
//
//  What the import screen needs to know about a picked file before trimming (PRD §5.2):
//  duration, a coarse waveform, title/artist for the lyrics search, and whether it can be used at all.
//  Implemented by AudioFileInspector (Data).
//

import Foundation

nonisolated struct ImportedAudio: Equatable, Sendable {
    let url: URL
    let name: String
    let duration: TimeInterval
    /// Peak level per bin (0…1), evenly spread over the whole file.
    let waveform: [Float]
    /// From the file's metadata, else guessed from the file name.
    let title: String
    let artist: String?
}

nonisolated enum AudioImportError: Error, Equatable {
    /// DRM (e.g. Apple Music downloads).
    case protectedContent
    case noAudio
    case unreadable
}

nonisolated protocol AudioFileInspecting: Sendable {
    /// Copies the picked file into the app's import folder and inspects the copy.
    func importFile(at pickedURL: URL) async throws -> ImportedAudio
}
