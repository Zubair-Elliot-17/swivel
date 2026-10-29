import Foundation
import os
import Testing
import SwivelCore

/// Runs `job` in a task that is cancelled before its first await.
private func cancelled(_ job: @escaping @Sendable () async -> [Outcome]) async -> [Outcome] {
    await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await job()
    }.value
}

private func expectAllCancelled(_ outcomes: [Outcome], _ urls: [URL], sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcomes == urls.map { .failed(source: $0, reason: "cancelled") }, sourceLocation: sourceLocation)
    let s = BatchSummary(outcomes)
    #expect(s.converted + s.skipped + s.failed == urls.count, sourceLocation: sourceLocation)
    #expect(s.menuLine == "Failed: \(urls[0].lastPathComponent): cancelled (0 of \(urls.count) converted)", sourceLocation: sourceLocation)
}

@Test func cancelledImageBatchConvertsNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let urls = [try write(.png, in: dir, name: "a"), try write(.png, in: dir, name: "b")]
    expectAllCancelled(await cancelled { await Converter.convertBatch(urls, to: .jpeg) }, urls)
    #expect(try files(in: dir) == ["a.png", "b.png"])
}

@Test func cancelledTextBatchConvertsNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let urls = [try write(.png, in: dir, name: "a"), try write(.png, in: dir, name: "b")]
    expectAllCancelled(await cancelled { await Converter.textBatch(urls) }, urls)
    #expect(try files(in: dir) == ["a.png", "b.png"])
}

// Q8: a cancelled combined PDF writes nothing and every source fails.
@Test func cancelledMakePDFWritesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let urls = [try write(.png, in: dir, name: "a"), try write(.jpeg, in: dir, name: "b"), dir.appendingPathComponent("missing.txt")]
    expectAllCancelled(await cancelled { await Converter.makePDF(urls) }, urls)
    #expect(try files(in: dir) == ["a.png", "b.jpg"])
}

@Test func cancelledAVBatchConvertsNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let urls = [try await AVFixture.write("a.mov", in: dir), try await AVFixture.write("b.mov", in: dir)]
    expectAllCancelled(await cancelled { await Converter.avBatch(urls, to: .mp4) }, urls)
    #expect(try files(in: dir) == ["a.mov", "b.mov"])
}

// AC 15: cancelled during source 2 of 5.
@Test func avBatchCancelledMidwayKeepsWhatWasConverted() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    var urls: [URL] = []
    for name in ["a", "b", "c", "d", "e"] { urls.append(try await AVFixture.write("\(name).mov", in: dir)) }
    let handle = OSAllocatedUnfairLock<Task<[Outcome], Never>?>(initialState: nil)
    let task = Task {
        await Converter.avBatch(urls, to: .hevc) { url, _ in
            if url.lastPathComponent == "b.mov" { handle.withLock { $0?.cancel() } }
        }
    }
    handle.withLock { $0 = task }
    let outcomes = await task.value
    #expect(outcomes.dropFirst().allSatisfy { if case .failed(_, "cancelled", nil) = $0 { true } else { false } }, "\(outcomes)")
    let s = BatchSummary(outcomes)
    #expect(s.menuLine == "Failed: b.mov: cancelled (1 of 5 converted)")
    #expect(s.converted + s.skipped + s.failed == 5)
    #expect(s.outputs.map(\.lastPathComponent) == ["a.mp4"])
    #expect(try files(in: dir) == ["a.mov", "b.mov", "c.mov", "d.mov", "e.mov", "a.mp4"])
}
