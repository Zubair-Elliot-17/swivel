import AVFoundation
import Foundation
import os
import Testing
@testable import SwivelCore

/// Fails the test if a `.swivel-*` temp file is left in `dir`.
func expectNoTemp(_ dir: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(try files(in: dir).filter { $0.hasPrefix(".swivel-") }.isEmpty, sourceLocation: sourceLocation)
}

/// Collects progress values from any thread.
final class ProgressLog: Sendable {
    private let values = OSAllocatedUnfairLock(initialState: [Double]())
    func add(_ v: Double) { values.withLock { $0.append(v) } }
    var all: [Double] { values.withLock { $0 } }
}

private func output(_ outcome: Outcome) throws -> URL {
    guard case .converted(_, let outputs) = outcome, outputs.count == 1 else { throw ConvertTestError("not converted: \(outcome)") }
    return outputs[0]
}

struct ConvertTestError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: MP4 / HEVC / MOV (AC 6)

@Test func h264MovToMP4IsARemux() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    #expect(avDecision(await Converter.probe(src), .mp4) == .remux)
    let out = try output(await Converter.convertAV(src, to: .mp4))
    #expect(out.lastPathComponent == "clip.mp4")
    #expect(try await AVFixture.codec(out, .video) == "avc1")
    #expect(try await AVFixture.codec(out, .audio) == "aac ")
    #expect(abs(try await AVFixture.duration(out) - AVFixture.duration(src)) < 0.05)
    try expectNoTemp(dir)
}

@Test func hevcMovToMP4GivesH264() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir, video: .hevc)
    let out = try output(await Converter.convertAV(src, to: .mp4))
    #expect(try await AVFixture.codec(out, .video) == "avc1")
    try expectNoTemp(dir)
}

@Test func h264MovToHEVCGivesHvc1InMP4() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    let out = try output(await Converter.convertAV(src, to: .hevc))
    #expect(out.lastPathComponent == "clip.mp4")
    #expect(try await AVFixture.codec(out, .video) == "hvc1")
    try expectNoTemp(dir)
}

@Test func mp4ToMOVIsARemux() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mp4", in: dir, fileType: .mp4)
    #expect(avDecision(await Converter.probe(src), .mov) == .remux)
    let out = try output(await Converter.convertAV(src, to: .mov))
    #expect(out.lastPathComponent == "clip.mov")
    #expect(try await AVFixture.codec(out, .video) == "avc1")
    try expectNoTemp(dir)
}

@Test func takenNameKeepsBoth() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    let taken = dir.appendingPathComponent("clip.mp4")
    try Data("original".utf8).write(to: taken)
    let out = try output(await Converter.convertAV(src, to: .mp4))
    #expect(out.lastPathComponent == "clip 2.mp4")
    #expect(try Data(contentsOf: taken) == Data("original".utf8))
    try expectNoTemp(dir)
}

@Test func alreadyTargetsWriteNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let mp4 = try await AVFixture.write("a.mp4", in: dir, fileType: .mp4)
    let hevc = try await AVFixture.write("h.mp4", in: dir, video: .hevc, fileType: .mp4)
    let mov = try await AVFixture.write("m.mov", in: dir)
    let before = try files(in: dir)
    #expect(await Converter.convertAV(mp4, to: .mp4) == .skipped(source: mp4, .alreadyAV(.mp4)))
    #expect(await Converter.convertAV(hevc, to: .hevc) == .skipped(source: hevc, .alreadyAV(.hevc)))
    #expect(await Converter.convertAV(mov, to: .mov) == .skipped(source: mov, .alreadyAV(.mov)))
    #expect(try files(in: dir) == before)
}

// MARK: M4A (AC 7)

@Test func videoToM4AIsAACWithNoVideo() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mp4", in: dir, fileType: .mp4)
    #expect(avDecision(await Converter.probe(src), .m4a) == .remux)
    let out = try output(await Converter.convertAV(src, to: .m4a))
    #expect(out.lastPathComponent == "clip.m4a")
    #expect(try await AVFixture.codec(out, .audio) == "aac ")
    #expect(try await AVFixture.codec(out, .video) == nil)
    try expectNoTemp(dir)
}

@Test func wavToM4AIsAAC() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("voice.wav", in: dir, video: nil, fileType: .wav)
    let out = try output(await Converter.convertAV(src, to: .m4a))
    #expect(try await AVFixture.codec(out, .audio) == "aac ")
    try expectNoTemp(dir)
}

@Test func aacM4AIsAlreadyM4A() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("voice.m4a", in: dir, video: nil, fileType: .m4a)
    #expect(await Converter.convertAV(src, to: .m4a) == .skipped(source: src, .alreadyAV(.m4a)))
}

// MARK: Route table (AC 11)

@Test func everyRouteUsesASupportedFileType() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let clip = try await AVFixture.write("clip.mov", in: dir)
    let voice = try await AVFixture.write("voice.m4a", in: dir, video: nil, fileType: .m4a)
    for target in AVTarget.allCases {
        for remux in [true, false] {
            let routes = Converter.routes(target, remux: remux)
            #expect(routes.isEmpty == (target == .gif || target == .wav))
            for (src, route) in routes.flatMap({ r in (target == .m4a ? [clip, voice] : [clip]).map { ($0, r) } }) {
                let session = try #require(AVAssetExportSession(asset: AVURLAsset(url: src), presetName: route.preset))
                #expect(session.supportedFileTypes.contains(route.fileType), "\(target) \(route.preset) \(src.lastPathComponent)")
            }
        }
    }
    #expect(Converter.routes(.mp4, remux: true).map(\.preset) == [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality])
    #expect(Converter.routes(.mp4, remux: false).map(\.preset) == [AVAssetExportPresetHighestQuality])
    #expect(Converter.routes(.hevc, remux: false).map(\.preset) == [AVAssetExportPresetHEVCHighestQuality])
    #expect(Converter.routes(.m4a, remux: false).map(\.preset) == [AVAssetExportPresetAppleM4A])
    #expect(Converter.routes(.mov, remux: true).map(\.fileType) == [.mov, .mov])
    #expect(Converter.routes(.hevc, remux: true).map(\.fileType) == [.mp4, .mp4])
    #expect(Converter.routes(.m4a, remux: true).map(\.fileType) == [.m4a, .m4a])
}

// MARK: Temp files, permissions (AC 12)

@Test func readOnlyFolderFailsAndWritesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    let outcome = await Converter.convertAV(src, to: .mp4)
    guard case .failed(_, let reason, _) = outcome else { Issue.record("\(outcome)"); return }
    #expect(reason == "no permission")
    #expect(try files(in: dir) == ["clip.mov"])
}

@Test func unreadableMediaIsCantRead() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: src.path)
    #expect(await Converter.convertAV(src, to: .mp4) == .skipped(source: src, .unreadable))
}

// MARK: Progress and cancel (AC 13, 14)

@Test func progressRisesToTheEnd() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("long.mov", in: dir, seconds: 20)
    let log = ProgressLog()
    _ = try output(await Converter.convertAV(src, to: .hevc) { log.add($0) })
    let values = log.all
    #expect(!values.isEmpty)
    #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }, "\(values)")
    #expect((values.last ?? 0) >= 0.99)
}

@Test func cancelDuringHEVCLeavesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("long.mov", in: dir, seconds: 20)
    let (calls, call) = AsyncStream.makeStream(of: Void.self)
    let task = Task { await Converter.convertAV(src, to: .hevc) { _ in call.yield() } }
    for await _ in calls { break }
    task.cancel()
    let outcome = await task.value
    #expect(outcome == .failed(source: src, reason: "cancelled"), "\(outcome)")
    let left = try files(in: dir)
    #expect(left == ["long.mov"], "\(left)")
}

@Test func avBatchKeepsOrderAndReportsPerSource() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let a = try await AVFixture.write("a.mov", in: dir)
    let voice = try await AVFixture.write("voice.m4a", in: dir, video: nil, fileType: .m4a)
    let seen = OSAllocatedUnfairLock(initialState: Set<String>())
    let outcomes = await Converter.avBatch([a, voice], to: .mp4) { url, _ in seen.withLock { _ = $0.insert(url.lastPathComponent) } }
    #expect(outcomes.count == 2)
    #expect(try output(outcomes[0]).lastPathComponent == "a.mp4")
    #expect(outcomes[1] == .skipped(source: voice, .noVideo))
    #expect(seen.withLock { $0 } == ["a.mov"])
    #expect(BatchSummary(outcomes).menuLine == "Last: a.mp4 (1 of 2, 1 skipped)")
}
