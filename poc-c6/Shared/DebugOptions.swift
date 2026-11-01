//
//  DebugOptions.swift
//  poc-c6
//
//  Developer-only switches that are not part of PoCConfiguration (the shared contract).
//  Always off in Release builds.
//

import Foundation

nonisolated enum DebugOptions {
    private static let speakerKey = "DebugOptions.allowsSpeakerRecording"

    /// Lets a session record with the built-in speaker (no earphones) and plays the song through
    /// the loudspeaker. For device testing only: the song leaks into the microphone, so scores and
    /// the final mix are not representative (PRD §7.2 blocks this in the real app).
    static var allowsSpeakerRecording: Bool {
        get {
            #if DEBUG
            UserDefaults.standard.bool(forKey: speakerKey)
            #else
            false
            #endif
        }
        set { UserDefaults.standard.set(newValue, forKey: speakerKey) }
    }
}
