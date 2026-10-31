//
//  PitchSample.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import CoreMedia

/// Raw output of the pitch detector. Knows nothing about target notes.
nonisolated struct PitchSample: Sendable {
    /// Time on the capture session's synchronization clock.
    let captureTime: CMTime
    /// nil when unvoiced or below the noise gate.
    let frequency: Float?
    let rmsDecibels: Float
}
