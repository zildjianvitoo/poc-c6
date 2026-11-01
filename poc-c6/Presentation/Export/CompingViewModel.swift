//
//  CompingViewModel.swift
//  poc-c6
//
//  Runs the export and the Save to Photos action for ExportPreviewView. Owner: Zildjian Vito (ZV-13).
//

import Foundation
import Observation

@Observable
final class CompingViewModel {
    enum ExportState: Equatable {
        case idle
        case exporting(progress: Double)
        case finished(URL)
        case failed(String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case denied
        case failed(String)
    }

    let plan: CompingCompositionPlan
    private(set) var exportState: ExportState = .idle
    private(set) var saveState: SaveState = .idle

    private let useCase: AutoCompingVideoUseCase
    private let videoLibrary: any VideoLibrarySaving

    init(plan: CompingCompositionPlan, useCase: AutoCompingVideoUseCase, videoLibrary: any VideoLibrarySaving) {
        self.plan = plan
        self.useCase = useCase
        self.videoLibrary = videoLibrary
    }

    var summary: String {
        let passed = plan.validTakes.count, total = plan.segments.count
        return plan.isPartial ? "Partial cover · \(passed) of \(total) segments" : "Full cover · \(total) segments"
    }

    var exportedURL: URL? {
        if case .finished(let url) = exportState { url } else { nil }
    }

    /// False while running on fakes: the fake export returns a URL without writing a file.
    var hasPlayableFile: Bool {
        exportedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func export() async {
        if case .exporting = exportState { return }
        exportState = .exporting(progress: 0)
        saveState = .idle
        do {
            // The view model is MainActor-isolated (so Sendable); holding it until the export ends is fine.
            let url = try await useCase.export(plan) { progress in
                Task { @MainActor in
                    guard case .exporting = self.exportState else { return }
                    self.exportState = .exporting(progress: progress)
                }
            }
            exportState = .finished(url)
        } catch {
            exportState = .failed(String(describing: error))
        }
    }

    func saveToPhotos() async {
        guard let url = exportedURL, saveState != .saving else { return }
        saveState = .saving
        do {
            try await videoLibrary.saveVideo(at: url)
            saveState = .saved
        } catch VideoLibraryError.accessDenied {
            saveState = .denied
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }
}
