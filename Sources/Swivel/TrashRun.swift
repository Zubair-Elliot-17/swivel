import Foundation
import os
import SwivelCore

private let trashLog = Logger(subsystem: "dev.zubair.swivel", category: "trash")

/// Moves fully converted originals to the Trash at the end of a batch (setting `trashOriginal`).
@MainActor
enum TrashRun {
    /// Runs once per batch; nothing when off or cancelled. `busy` is read last: URLs other running drops still use.
    /// Returns how many sources should have gone but stayed (the menu's "N not moved to Trash").
    static func afterBatch(
        _ outcomes: [Outcome], slice: String, enabled: Bool, busy: () -> [URL],
        isVideo: @Sendable (URL) async -> Bool = Trash.hasVideo, trash: (URL) throws -> Void = moveToTrash
    ) async -> Int {
        guard enabled, !Task.isCancelled else { return 0 }
        let candidates = await Trash.trashCandidates(outcomes, slice: slice, isVideo: isVideo)
        guard !Task.isCancelled else { return 0 }
        return run(candidates, busy: busy(), trash: trash)
    }

    /// Trashes each source whose outputs all exist. In use elsewhere or already gone: kept, logged, not counted.
    static func run(_ candidates: [(source: URL, outputs: [URL])], busy: [URL], trash: (URL) throws -> Void = moveToTrash) -> Int {
        let inUse = Set(busy.map(\.standardizedFileURL.path))
        let fm = FileManager.default
        var kept = 0
        for (source, outputs) in candidates {
            let name = source.lastPathComponent
            if inUse.contains(source.standardizedFileURL.path) {
                trashLog.info("not trashed \(name, privacy: .private): in use by another drop")
            } else if !fm.fileExists(atPath: source.path) {
                trashLog.info("not trashed \(name, privacy: .private): already gone")
            } else if let missing = outputs.first(where: { !fm.fileExists(atPath: $0.path) }) {
                kept += 1
                trashLog.info("not trashed \(name, privacy: .private): output missing \(missing.lastPathComponent, privacy: .private)")
            } else {
                do {
                    try trash(source)
                    trashLog.info("trashed \(name, privacy: .private)")
                } catch {
                    kept += 1
                    trashLog.info("not trashed \(name, privacy: .private): \(error.localizedDescription, privacy: .private)")
                }
            }
        }
        return kept
    }

    /// Recoverable: Finder's Put Back works. Volumes without a Trash throw, so the file stays.
    nonisolated static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
