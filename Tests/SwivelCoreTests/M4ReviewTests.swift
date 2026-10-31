import AVFoundation
import Foundation
import ImageIO
import Testing
@testable import SwivelCore

// Regression tests for the M4 review fix round.

// MARK: F1 WAV rate outside what AVFoundation accepts

@Test func wavRateClampsToAVFoundationRange() {
    #expect(wavFormat(rate: 1, channels: 1) == (8_000, 1))
    #expect(wavFormat(rate: 5_512, channels: 1) == (8_000, 1))
    #expect(wavFormat(rate: 384_000, channels: 1) == (192_000, 1))
    #expect(wavFormat(rate: 1e9, channels: 1) == (192_000, 1))
    #expect(wavFormat(rate: 8_000, channels: 1) == (8_000, 1))
    #expect(wavFormat(rate: 192_000, channels: 1) == (192_000, 1))
    // 1 h at 1 GHz would be over 4 GiB; at the clamped 192 kHz it is ~1.4 GB, so it fits.
    var p = AVProbe()
    (p.contentType, p.opened, p.playable, p.hasAudio, p.duration, p.audioRate, p.audioChannels) = (.mpeg4Audio, true, true, true, 3_600, 1e9, 1)
    #expect(avDecision(p, .wav) == .encode)
}

// Rates outside 8...192 kHz once raised an uncatchable ObjC exception and left a .swivel-* folder.
@Test(arguments: [(5_512.0, 8_000.0), (384_000, 192_000)])
func extremeRateSourceConvertsToWAV(rate: Double, expected: Double) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    // AVAudioFile clamps the rate itself, so afconvert writes the source.
    let wav = try await AVFixture.write("tone.wav", in: dir, video: nil, seconds: 1, fileType: .wav)
    let src = dir.appendingPathComponent("tone.caf")
    let run = try Process.run(URL(fileURLWithPath: "/usr/bin/afconvert"), arguments: ["-f", "caff", "-d", "BEI16@\(Int(rate))", wav.path, src.path])
    run.waitUntilExit()
    #expect(run.terminationStatus == 0)
    try FileManager.default.removeItem(at: wav)
    let p = await Converter.probe(src)
    #expect(p.audioRate == rate, "\(p)")
    let outcome = await Converter.convertAV(src, to: .wav)
    guard case .converted(_, let outputs) = outcome, let out = outputs.first else { Issue.record("\(outcome)"); return }
    #expect(try await wavFormatOf(out).mSampleRate == expected)
    #expect(abs(try await AVURLAsset(url: out).load(.duration).seconds - 1) < 0.05)
    #expect(try files(in: dir) == ["tone.caf", "tone.wav"])
}

// MARK: F2 GIF length from the video track

// A 1 s video under 6 s of audio: frames past the video's end once failed the whole GIF.
@Test func gifUsesTheVideoTrackLength() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("short.mov", in: dir, seconds: 1, audioSeconds: 6)
    #expect(abs(try await AVFixture.duration(src) - 6) < 0.05)
    let outcome = await Converter.convertAV(src, to: .gif)
    guard case .converted(_, let outputs) = outcome, let out = outputs.first else { Issue.record("\(outcome)"); return }
    let gif = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
    #expect(CGImageSourceGetCount(gif) == 10)
    try expectNoTemp(dir)
}

// The cap and the hostile-value checks read the video track's span, not the file's.
@Test func gifDecisionUsesTheVideoSpan() {
    var p = AVProbe()
    (p.contentType, p.opened, p.playable, p.hasVideo, p.videoSize) = (.quickTimeMovie, true, true, true, CGSize(width: 320, height: 240))
    (p.duration, p.videoStart, p.videoDuration) = (60, 0, 1)
    #expect(avDecision(p, .gif) == .encode)
    (p.duration, p.videoDuration) = (31, 30.5)
    #expect(avDecision(p, .gif) == .fail("too long for GIF (max 30 s)"))
    for bad in [0, -1, Double.nan, .infinity] {
        (p.videoStart, p.videoDuration) = (0, bad)
        #expect(avDecision(p, .gif) == .skip(.notSupported), "duration \(bad)")
        (p.videoStart, p.videoDuration) = (bad == 0 ? -1 : bad, 1)
        #expect(avDecision(p, .gif) == .skip(.notSupported), "start \(bad)")
    }
}

// MARK: F5 makePDF cancelled between sources

// Q8 at every point of the loop: the open PDF is closed and dropped, nothing is written.
@Test func makePDFCancelledMidwayWritesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let urls = try (0..<40).map { try write(.png, in: dir, name: "p\($0)") }
    let sources = try files(in: dir)
    for delay in stride(from: 0, through: 12_000, by: 250) {
        let task = Task { await Converter.makePDF(urls) }
        try await Task.sleep(for: .microseconds(delay))
        task.cancel()
        let outcomes = await task.value
        if case .converted(_, let outputs) = outcomes[0] {
            #expect(outcomes == urls.map { .converted(source: $0, outputs: outputs) }, "\(delay) µs")
            for url in outputs { try FileManager.default.removeItem(at: url) }
        } else {
            #expect(outcomes == urls.map { .failed(source: $0, reason: "cancelled") }, "\(delay) µs: \(outcomes)")
        }
        #expect(try files(in: dir) == sources, "\(delay) µs")
    }
}

// MARK: F6 GIF written through the temp folder

// A GIF now goes through viaTemp like WAV/export: same Keep Both naming, no temp left, read-only fails cleanly.
@Test func gifGoesThroughTheTempFolder() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let src = try await AVFixture.write("clip.mov", in: dir)
    for name in ["clip.gif", "clip 2.gif"] {
        let outcome = await Converter.convertAV(src, to: .gif)
        #expect(outcome == .converted(source: src, outputs: [dir.appendingPathComponent(name)]), "\(outcome)")
    }
    try expectNoTemp(dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    let outcome = await Converter.convertAV(src, to: .gif)
    guard case .failed(_, let reason, _) = outcome else { Issue.record("\(outcome)"); return }
    #expect(reason == "no permission")
    #expect(try files(in: dir) == ["clip.mov", "clip.gif", "clip 2.gif"])
}
