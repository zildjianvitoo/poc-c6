//
//  SelectingStemSeparationRepository.swift
//  poc-c6
//
//  Chooses how an imported song is separated (PRD §3): the htdemucs CoreML model when
//  `useCoreMLSeparation` is on, with the center-channel fallback if the model can't be used
//  (missing, out of memory, prediction failed). Errors about the file itself (DRM, unreadable,
//  bad trim) are not retried.
//

import Foundation

nonisolated struct SelectingStemSeparationRepository: StemSeparationRepository {
    let coreML: any StemSeparationRepository
    let centerChannel: any StemSeparationRepository
    /// Read on every call so the Debug Settings flag applies to the next song.
    let useCoreML: @Sendable () -> Bool

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        guard useCoreML() else {
            return try await centerChannel.separateStems(from: audioURL, trimRange: trimRange)
        }
        do {
            return try await coreML.separateStems(from: audioURL, trimRange: trimRange)
        } catch CoreMLSeparationError.drmProtected {
            throw CoreMLSeparationError.drmProtected
        } catch CoreMLSeparationError.invalidTrim {
            throw CoreMLSeparationError.invalidTrim
        } catch {
            // Model missing or failed (e.g. memory): basic vocal removal still gives a usable song.
            return try await centerChannel.separateStems(from: audioURL, trimRange: trimRange)
        }
    }
}
