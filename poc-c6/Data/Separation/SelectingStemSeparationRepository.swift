//
//  SelectingStemSeparationRepository.swift
//  poc-c6
//
//  Chooses how an imported song is separated (PRD §3). With `useCoreMLSeparation` on: htdemucs
//  (when provided) → Open-Unmix → center-channel, each one a fallback for a model that can't be
//  used (missing, out of memory, prediction failed). Errors about the file
//  itself (DRM, unreadable, bad trim) are not retried.
//

import Foundation

nonisolated struct SelectingStemSeparationRepository: StemSeparationRepository {
    let coreML: any StemSeparationRepository
    let centerChannel: any StemSeparationRepository
    /// Read on every call so the Debug Settings flag applies to the next song.
    let useCoreML: @Sendable () -> Bool
    /// Tried before `coreML` (Open-Unmix) when set.
    var htDemucs: (any StemSeparationRepository)? = nil

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        guard useCoreML() else {
            return try await centerChannel.separateStems(from: audioURL, trimRange: trimRange)
        }
        let models = [htDemucs, coreML].compactMap { $0 }
        for model in models {
            do {
                return try await model.separateStems(from: audioURL, trimRange: trimRange)
            } catch CoreMLSeparationError.drmProtected {
                throw CoreMLSeparationError.drmProtected
            } catch CoreMLSeparationError.invalidTrim {
                throw CoreMLSeparationError.invalidTrim
            } catch {
                // Model missing or failed (e.g. memory): try the next, lighter method.
                continue
            }
        }
        // Basic vocal removal still gives a usable song.
        return try await centerChannel.separateStems(from: audioURL, trimRange: trimRange)
    }
}
