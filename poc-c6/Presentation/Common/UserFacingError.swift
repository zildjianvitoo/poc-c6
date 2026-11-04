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
    case protectedFile
    case songTooShort(minimumSeconds: Int)
    case monoSong
    case noVocalDetected
    case speakerOutput
    case lowStorage(requiredGB: Double)
    case exportFailed(details: String)
    case recordingFailed(details: String)
    case recordingInterrupted
    case nothingToExport
    case vocalRangeCaptureFailed
    case headsetMicrophoneRequired
    case vocalRangeTooNarrow
    case keyPreviewFailed
    case keyPreparationFailed

    var title: String {
        switch self {
        case .permissionDenied(let permissions):
            "\(Self.list(permissions)) access is off"
        case .unreadableFile: "This file can't be used"
        case .protectedFile: "This song is protected"
        case .songTooShort: "This song is too short"
        case .monoSong: "Vocals can't be removed"
        case .noVocalDetected: "No vocal melody found"
        case .speakerOutput: "Plug in earphones"
        case .lowStorage: "Not enough storage"
        case .exportFailed: "Export failed"
        case .recordingFailed: "Recording stopped"
        case .recordingInterrupted: "Recording was interrupted"
        case .nothingToExport: "Nothing to export yet"
        case .vocalRangeCaptureFailed: "We couldn't capture your voice"
        case .headsetMicrophoneRequired: "Connect a headset microphone"
        case .vocalRangeTooNarrow: "Try a higher comfortable note"
        case .keyPreviewFailed: "The preview couldn't play"
        case .keyPreparationFailed: "The keys couldn't be prepared"
        }
    }

    var message: String {
        switch self {
        case .permissionDenied(let permissions):
            "Turn on \(Self.list(permissions).lowercased()) access in Settings. "
                + permissions.map { "\($0.displayName) is needed \($0.reason)." }.joined(separator: " ")
        case .unreadableFile:
            "Try an MP3, M4A or WAV file."
        case .protectedFile:
            "Songs from Apple Music and other streaming apps are copy-protected. Pick a file you own, like an MP3 or M4A."
        case .songTooShort(let minimumSeconds):
            "Pick a song that is at least \(minimumSeconds) seconds long."
        case .monoSong:
            "This recording is mono, so the singer can't be separated from the music. Try a stereo version."
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
        case .vocalRangeCaptureFailed:
            "Try again in a quiet place. Speak naturally for the reading, and hold each sung note steadily without straining."
        case .headsetMicrophoneRequired:
            "Connect wired or Bluetooth earphones with a microphone, then try again. Headphones that only play audio can't be used as a microphone."
        case .vocalRangeTooNarrow:
            "Your highest note must be above your lowest note. Stay comfortable and don't force your voice."
        case .keyPreviewFailed:
            "Try listening again. If playback still fails, prepare the song again."
        case .keyPreparationFailed:
            "Try preparing the song again or choose another section."
        }
    }

    var systemImage: String {
        switch self {
        case .permissionDenied(let permissions): permissions.first?.systemImage ?? "lock.fill"
        case .unreadableFile: "doc.questionmark"
        case .protectedFile: "lock.doc"
        case .songTooShort: "timer"
        case .monoSong: "speaker.slash"
        case .noVocalDetected: "waveform.slash"
        case .speakerOutput: "headphones"
        case .lowStorage: "externaldrive.badge.exclamationmark"
        case .exportFailed: "exclamationmark.triangle"
        case .recordingFailed: "video.slash"
        case .recordingInterrupted: "pause.circle"
        case .nothingToExport: "film.stack"
        case .vocalRangeCaptureFailed, .vocalRangeTooNarrow: "mic.badge.xmark"
        case .headsetMicrophoneRequired: "headphones"
        case .keyPreviewFailed: "speaker.slash"
        case .keyPreparationFailed: "music.note.list"
        }
    }

    private static func list(_ permissions: [MediaPermission]) -> String {
        permissions.map(\.displayName).formatted(.list(type: .and))
    }
}
