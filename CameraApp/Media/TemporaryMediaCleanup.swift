//
//  TemporaryMediaCleanup.swift
//  CameraApp
//
//  A recorded video that failed to save to Photos is deliberately left on
//  disk — there is no retry UI, but throwing away someone's only copy of a
//  clip because the library was briefly locked is worse than a stray file.
//  This is what keeps those stray files from accumulating forever: a sweep
//  at the next launch, well past the point where anything could still be
//  waiting to import them.
//

import Foundation

enum TemporaryMediaCleanup {

    /// Prefix shared with `VideoRecorder`'s output files.
    static let filePrefix = "capture-"

    /// Removes leftover recording files older than `interval`. Safe to call
    /// on every launch — recent files are left alone in case a save from the
    /// previous session is, improbably, still in flight.
    static func purgeStaleRecordings(olderThan interval: TimeInterval = 3600) {
        let directory = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-interval)
        for url in items where url.lastPathComponent.hasPrefix(filePrefix) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified == nil || modified! < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
