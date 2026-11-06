import Foundation
import Testing
import SwivelCore
@testable import Swivel

// M6 gaps for TrashRun.afterBatch (AC6). Never the real Trash: `trash` is injected; files live in a temp dir.

private final class Box: @unchecked Sendable {
    var trashed: [URL] = []
    var probed = false
}

private func batch() throws -> (dir: URL, outcomes: [Outcome]) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swivel-m6gap-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let src = dir.appendingPathComponent("voice.wav"), out = dir.appendingPathComponent("voice.m4a")
    try Data("x".utf8).write(to: src)
    try Data("x".utf8).write(to: out)
    return (dir, [.converted(source: src, outputs: [out])])
}

// Cancel lands while the video probe runs: the batch still trashes nothing.
@MainActor @Test func aCancelDuringTheVideoProbeTrashesNothing() async throws {
    let (dir, outcomes) = try batch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let box = Box()
    let n = await Task { @MainActor in
        await TrashRun.afterBatch(outcomes, slice: "M4A", enabled: true, busy: { [] },
                                  isVideo: { _ in withUnsafeCurrentTask { $0?.cancel() }; return false },
                                  trash: { box.trashed.append($0) })
    }.value
    #expect(n == 0)
    #expect(box.trashed.isEmpty)
}

// A drop that starts during the probe and uses the file must still block it, so `busy` is read after.
@MainActor @Test func busyIsReadAfterTheVideoProbe() async throws {
    let (dir, outcomes) = try batch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let box = Box(), src = outcomes.compactMap { if case .converted(let s, _, _) = $0 { s } else { nil } }
    let n = await TrashRun.afterBatch(outcomes, slice: "M4A", enabled: true, busy: { box.probed ? src : [] },
                                      isVideo: { _ in box.probed = true; return false }, trash: { box.trashed.append($0) })
    #expect(n == 0)
    #expect(box.trashed.isEmpty)
}

// The default isVideo is the real probe: an audio file on an audio slice is trashed (through the fake).
@MainActor @Test func theDefaultProbeLetsAnAudioSourceGo() async throws {
    let (dir, outcomes) = try batch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let box = Box()
    #expect(await TrashRun.afterBatch(outcomes, slice: "M4A", enabled: true, busy: { [] }, trash: { box.trashed.append($0) }) == 0)
    #expect(box.trashed.map(\.lastPathComponent) == ["voice.wav"])
}
