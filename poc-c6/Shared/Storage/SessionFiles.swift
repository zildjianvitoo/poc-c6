//
//  SessionFiles.swift
//  poc-c6
//
//  Where a recording session keeps its large files, and how they are cleaned up (ZV-16).
//  Owner: Zildjian Vito. Capture (Takin) writes the raw video to `rawVideoURL`;
//  comping writes the final cover to `finalVideoURL`.
//

import Foundation

nonisolated enum SessionFiles {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Session", isDirectory: true)
    }

    static var rawVideoURL: URL { directory.appendingPathComponent("RawMasterVideo.mov") }
    static var finalVideoURL: URL { directory.appendingPathComponent("FinalCoverVideo.mp4") }

    /// Free space for important data on the app's volume, in bytes (PRD §5.8 storage checks).
    static func availableCapacity() -> Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Creates the session folder if needed.
    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Deletes every file from earlier sessions (raw recording, final export, leftovers after a crash).
    /// The synthesized demo cache lives elsewhere and is kept.
    @discardableResult
    static func cleanUp() -> Int {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for file in files where (try? fileManager.removeItem(at: file)) != nil {
            removed += 1
        }
        return removed
    }
}
