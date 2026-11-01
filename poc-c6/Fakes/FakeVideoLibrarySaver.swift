//
//  FakeVideoLibrarySaver.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-13).
//

import Foundation

nonisolated final class FakeVideoLibrarySaver: VideoLibrarySaving {
    let result: Result<Void, VideoLibraryError>

    init(result: Result<Void, VideoLibraryError> = .success(())) {
        self.result = result
    }

    func saveVideo(at url: URL) async throws {
        try await Task.sleep(for: .milliseconds(300))
        try result.get()
    }
}
