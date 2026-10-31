//
//  VideoLibrarySaving.swift
//  poc-c6
//
//  Presentation-side capability (like ShareLink), not a Domain contract. Owner: Zildjian Vito (ZV-13).
//

import Foundation

nonisolated enum VideoLibraryError: Error {
    case accessDenied
}

nonisolated protocol VideoLibrarySaving: Sendable {
    func saveVideo(at url: URL) async throws
}
