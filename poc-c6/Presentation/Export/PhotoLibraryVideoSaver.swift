//
//  PhotoLibraryVideoSaver.swift
//  poc-c6
//
//  Saves the final cover to Photos with add-only access. Owner: Zildjian Vito (ZV-13).
//

import Foundation
import Photos

nonisolated final class PhotoLibraryVideoSaver: VideoLibrarySaving {
    func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw VideoLibraryError.accessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
