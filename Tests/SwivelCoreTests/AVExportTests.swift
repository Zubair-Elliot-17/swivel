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

// MARK: WAV (AC 8)

/// Sample format of the first audio track.
private func pcmFormat(_ url: URL) async throws -> AudioStreamBasicDescription {
    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
    let desc = try #require(try await track.load(.formatDescriptions).first)
    return try #require(CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee)
}

@Test(arguments: [("voice.m4a", AVFileType.m4a, false), ("clip.mov", .mov, true)])
func aacSourcesGive16BitWAV(name: String, type: AVFileType, video: Bool) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write(name, in: dir, video: video ? .h264 : nil, fileType: type)
    let log = ProgressLog()
    let out = try output(await Converter.convertAV(src, to: .wav) { log.add($0) })
    #expect(out.lastPathComponent == src.deletingPathExtension().lastPathComponent + ".wav")
    let asbd = try await pcmFormat(out)
    #expect(asbd.mFormatID == kAudioFormatLinearPCM)
    #expect(asbd.mBitsPerChannel == 16)
    #expect(asbd.mFormatFlags & kLinearPCMFormatFlagIsFloat == 0)
    #expect(asbd.mChannelsPerFrame >= 1 && asbd.mChannelsPerFrame <= 2)
    #expect(asbd.mSampleRate == 44100)
    #expect(abs(try await AVFixture.duration(out) - AVFixture.duration(src)) < 0.05)
    let values = log.all
    #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 } && (values.last ?? 0) >= 0.99, "\(values)")
    try expectNoTemp(dir)
}

@Test func wavSourceIsAlreadyWAV() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("voice.wav", in: dir, video: nil, fileType: .wav)
    #expect(await Converter.convertAV(src, to: .wav) == .skipped(source: src, .alreadyAV(.wav)))
}

@Test func cancelDuringWAVLeavesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("voice.m4a", in: dir, video: nil, seconds: 20, fileType: .m4a)
    // The first progress call cancels the converting task itself.
    let outcome = await Task { await Converter.convertAV(src, to: .wav) { _ in withUnsafeCurrentTask { $0?.cancel() } } }.value
    #expect(outcome == .failed(source: src, reason: "cancelled"))
    let left = try files(in: dir)
    #expect(left == ["voice.m4a"], "\(left)")
}

// Cancelling before the export starts once raised an uncatchable ObjC exception (macOS 26), and a cancelled
// session could write its file after returning; cancel across the whole conversion, every target.
@Test(arguments: AVTarget.allCases)
func cancelAtAnyPointNeverCrashesOrLeavesFiles(target: AVTarget) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let name = target == .mov ? "clip.mp4" : "clip.mov"
    let src = try await AVFixture.write(name, in: dir, fileType: target == .mov ? .mp4 : .mov)
    for delay in stride(from: 0, through: 12_000, by: 200) {
        let task = Task { await Converter.convertAV(src, to: target) }
        try await Task.sleep(for: .microseconds(delay))
        task.cancel()
        let outcome = await task.value
        if case .converted(_, let outputs) = outcome { for url in outputs { try FileManager.default.removeItem(at: url) } } else {
            #expect(outcome == .failed(source: src, reason: "cancelled"), "\(delay) µs: \(outcome)")
        }
        let left = try files(in: dir)
        #expect(left == [name], "\(delay) µs: \(left)")
    }
}

// MARK: GIF (AC 9)

private struct GIFReadBack {
    let count: Int, loop: Int?, delays: [Double], size: CGSize
    init(_ url: URL) throws {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        count = CGImageSourceGetCount(src)
        let file = CGImageSourceCopyProperties(src, nil) as? [CFString: Any]
        loop = (file?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
        delays = (0..<count).map { i in
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            return (props?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFDelayTime] as? Double ?? -1
        }
        let first = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        size = CGSize(width: first.width, height: first.height)
    }
}

@Test func twoSecondClipGivesTwentyFramesAtTenFPS() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    let log = ProgressLog()
    let out = try output(await Converter.convertAV(src, to: .gif) { log.add($0) })
    #expect(out.lastPathComponent == "clip.gif")
    let gif = try GIFReadBack(out)
    #expect(gif.count == 20)
    #expect(gif.delays.allSatisfy { $0 == 0.1 }, "\(gif.delays)")
    #expect(gif.loop == 0)
    #expect(gif.size == CGSize(width: 320, height: 240))  // never upscaled
    let values = log.all
    #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 } && (values.last ?? 0) >= 0.99, "\(values)")
    try expectNoTemp(dir)
}

@Test func gifLongSideIsAtMost480() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("wide.mov", in: dir, audio: false, size: CGSize(width: 960, height: 540), seconds: 1)
    #expect(try GIFReadBack(try output(await Converter.convertAV(src, to: .gif))).size == CGSize(width: 480, height: 270))
}

@Test func rotatedClipGivesAnUprightGIF() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("rot.mov", in: dir, seconds: 1, transform: CGAffineTransform(rotationAngle: .pi / 2))
    #expect(try GIFReadBack(try output(await Converter.convertAV(src, to: .gif))).size == CGSize(width: 240, height: 320))
}

@Test func longClipFailsGIFAndWritesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("long.mov", in: dir, audio: false, seconds: 31, frames: 2)
    #expect(await Converter.convertAV(src, to: .gif) == .failed(source: src, reason: "too long for GIF (max 30 s)"))
    #expect(try files(in: dir) == ["long.mov"])
}

@Test func cancelDuringGIFLeavesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir, seconds: 20)
    let outcome = await Task { await Converter.convertAV(src, to: .gif) { _ in withUnsafeCurrentTask { $0?.cancel() } } }.value
    #expect(outcome == .failed(source: src, reason: "cancelled"))
    #expect(try files(in: dir) == ["clip.mov"])
}
