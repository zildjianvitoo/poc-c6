//
//  UserFacingError.swift
//  poc-c6
//
//  One place for the error wording in PRD §9, so every screen says the same thing.
//  Owner: Zildjian Vito (ZV-14). Add a case here instead of writing a new message in your view.
//

import Foundation

nonisolated enum UserFacingError: Equatable, Sendable {
    case permissionDenied([MediaPermission])
    case unreadableFile
    case noVocalDetected
    case speakerOutput
    case lowStorage(requiredGB: Double)
    case exportFailed(details: String)
    case recordingFailed(details: String)
    case recordingInterrupted
    case nothingToExport

    var title: String {
        switch self {
        case .permissionDenied(let permissions):
            "\(Self.list(permissions)) access is off"
        case .unreadableFile: "This file can't be used"
        case .noVocalDetected: "No vocal melody found"
        case .speakerOutput: "Plug in earphones"
        case .lowStorage: "Not enough storage"
        case .exportFailed: "Export failed"
        case .recordingFailed: "Recording stopped"
        case .recordingInterrupted: "Recording was interrupted"
        case .nothingToExport: "Nothing to export yet"
        }
    }

    var message: String {
        switch self {
        case .permissionDenied(let permissions):
            "Turn on \(Self.list(permissions).lowercased()) access in Settings. "
                + permissions.map { "\($0.displayName) is needed \($0.reason)." }.joined(separator: " ")
        case .unreadableFile:
            "Try an MP3, M4A or WAV file."
        case .noVocalDetected:
            "We couldn't find a vocal melody in this section. Try another part of the song."
        case .speakerOutput:
            "Plug in earphones to record, so the song doesn't leak into the microphone."
        case .lowStorage(let requiredGB):
            "Free up at least \(requiredGB.formatted(.number.precision(.fractionLength(0...1)))) GB to record."
        case .exportFailed(let details):
            details
        case .recordingFailed(let details):
            details
        case .recordingInterrupted:
            "A call, another app or unplugged earphones stopped the session. Your passed segments are saved."
        case .nothingToExport:
            "Pass at least one segment to make a cover."
        }
    }

    var systemImage: String {
        switch self {
        case .permissionDenied(let permissions): permissions.first?.systemImage ?? "lock.fill"
        case .unreadableFile: "doc.questionmark"
        case .noVocalDetected: "waveform.slash"
        case .speakerOutput: "headphones"
        case .lowStorage: "externaldrive.badge.exclamationmark"
        case .exportFailed: "exclamationmark.triangle"
        case .recordingFailed: "video.slash"
        case .recordingInterrupted: "pause.circle"
        case .nothingToExport: "film.stack"
        }
    }

    private static func list(_ permissions: [MediaPermission]) -> String {
        permissions.map(\.displayName).formatted(.list(type: .and))
    }
}
