import Foundation
import Testing
import SwivelCore
@testable import Swivel

// Never the real Trash: every test injects `trash`, which records the URL or throws; files live in a temp dir.

private final class Recorder: @unchecked Sendable {
    var trashed: [URL] = []
    func trash(_ url: URL) throws { trashed.append(url) }
}

private struct Refused: Error {}

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swivel-trash-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func file(_ name: String, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try Data("x".utf8).write(to: url)
    return url
}

@MainActor @Test func trashesASourceWhoseOutputsExist() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try file("a.jpg", in: dir), out = try file("a.png", in: dir)
    let r = Recorder()
    #expect(TrashRun.run([(a, [out])], busy: [], trash: r.trash) == 0)
    #expect(r.trashed == [a])
}

@MainActor @Test func aSourceAnotherDropUsesIsKeptAndNotCounted() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try file("a.jpg", in: dir), out = try file("a.png", in: dir)
    let r = Recorder()
    // The other drop names it by another spelling of the same path.
    let other = URL(fileURLWithPath: dir.path + "/./sub/../a.jpg")
    #expect(TrashRun.run([(a, [out])], busy: [other], trash: r.trash) == 0)
    #expect(r.trashed.isEmpty)
}

@MainActor @Test func aSourceAlreadyGoneIsNotCounted() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let out = try file("a.png", in: dir)
    let r = Recorder()
    #expect(TrashRun.run([(dir.appendingPathComponent("a.jpg"), [out])], busy: [], trash: r.trash) == 0)
    #expect(r.trashed.isEmpty)
}

@MainActor @Test func aMissingOutputKeepsTheSourceAndCounts() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try file("doc.pdf", in: dir), page1 = try file("doc page 1.png", in: dir)
    let r = Recorder()
    #expect(TrashRun.run([(a, [page1, dir.appendingPathComponent("doc page 2.png")])], busy: [], trash: r.trash) == 1)
    #expect(r.trashed.isEmpty)
}

@MainActor @Test func aRefusedTrashKeepsTheFileAndCounts() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try file("a.jpg", in: dir), b = try file("b.jpg", in: dir)
    let outA = try file("a.png", in: dir), outB = try file("b.png", in: dir)
    var tried: [URL] = []
    let n = TrashRun.run([(a, [outA]), (b, [outB])], busy: []) { tried.append($0); throw Refused() }
    #expect(n == 2)
    #expect(tried == [a, b])
    #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
}

@MainActor @Test func countsOnlyFailuresInAMixedBatch() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let ok = try file("ok.jpg", in: dir), busy = try file("busy.jpg", in: dir), noOut = try file("noout.jpg", in: dir)
    let refused = try file("refused.jpg", in: dir), out = try file("out.png", in: dir)
    let n = TrashRun.run([(ok, [out]), (busy, [out]), (noOut, [dir.appendingPathComponent("gone.png")]), (refused, [out])],
                         busy: [busy]) { if $0 == refused { throw Refused() } }
    #expect(n == 2)
}

// Two drops of one file: the first to finish sees the other still running, the last one trashes it.
@MainActor @Test func onlyTheLastDropToFinishTrashesASharedFile() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try file("a.jpg", in: dir), png = try file("a.png", in: dir), jpg = try file("a.heic", in: dir)
    let r = Recorder()
    #expect(TrashRun.run([(a, [png])], busy: [a], trash: r.trash) == 0)
    #expect(r.trashed.isEmpty)
    #expect(TrashRun.run([(a, [jpg])], busy: [], trash: r.trash) == 0)
    #expect(r.trashed == [a])
}

// MARK: afterBatch: setting, cancel, slice

private func converted(_ dir: URL) throws -> [Outcome] {
    [.converted(source: try file("a.jpg", in: dir), outputs: [try file("a.png", in: dir)])]
}

@MainActor @Test func offTrashesNothing() async throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = Recorder()
    #expect(await TrashRun.afterBatch(try converted(dir), slice: "PNG", enabled: false, busy: { [] }, trash: r.trash) == 0)
    #expect(r.trashed.isEmpty)
}

@MainActor @Test func onTrashesAConversion() async throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = Recorder(), outcomes = try converted(dir)
    #expect(await TrashRun.afterBatch(outcomes, slice: "PNG", enabled: true, busy: { [] }, trash: r.trash) == 0)
    #expect(r.trashed == [dir.appendingPathComponent("a.jpg")])
}

@MainActor @Test func aCancelledBatchTrashesNothing() async throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = Recorder(), outcomes = try converted(dir)
    let n = await Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        return await TrashRun.afterBatch(outcomes, slice: "PNG", enabled: true, busy: { [] }, trash: r.trash)
    }.value
    #expect(n == 0)
    #expect(r.trashed.isEmpty)
}

@MainActor @Test func anExtractionTrashesNothing() async throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = Recorder()
    #expect(await TrashRun.afterBatch(try converted(dir), slice: "Text", enabled: true, busy: { [] }, trash: r.trash) == 0)
    #expect(r.trashed.isEmpty)
}
