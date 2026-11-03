import AVFoundation
import Foundation
import Testing
import SwivelCore

// Pure: trashCandidates only picks sources; nothing here moves a file.

private func url(_ name: String) -> URL { URL(fileURLWithPath: "/Users/me/Pictures/\(name)") }
private func ok(_ src: String, _ out: String..., complete: Bool = true) -> Outcome {
    .converted(source: url(src), outputs: out.map(url), complete: complete)
}
private let noVideo: @Sendable (URL) async -> Bool = { _ in false }

private func names(_ outcomes: [Outcome], slice: String, isVideo: @escaping @Sendable (URL) async -> Bool = noVideo) async -> [String] {
    await Trash.trashCandidates(outcomes, slice: slice, isVideo: isVideo).map(\.source.lastPathComponent)
}

@Test(arguments: ["PNG", "JPEG", "HEIC", "WebP", "TIFF", "PDF", "MP4", "HEVC", "MOV"])
func conversionsAreCandidates(slice: String) async {
    #expect(await names([ok("a.jpg", "a.png"), ok("doc.pdf", "doc page 1.png", "doc page 2.png")], slice: slice) == ["a.jpg", "doc.pdf"])
}

@Test func candidatesCarryTheirOutputs() async {
    let got = await Trash.trashCandidates([ok("doc.pdf", "doc page 1.png", "doc page 2.png")], slice: "PNG", isVideo: noVideo)
    #expect(got.map(\.outputs) == [[url("doc page 1.png"), url("doc page 2.png")]])
}

@Test(arguments: ["Text", "GIF"])
func extractionsNeverTrash(slice: String) async {
    #expect(await names([ok("shot.png", "shot.txt"), ok("clip.mov", "clip.gif")], slice: slice).isEmpty)
}

@Test(arguments: ["Rotate", "", "png"])
func unknownSlicesNeverTrash(slice: String) async {
    #expect(await names([ok("a.jpg", "a.png")], slice: slice).isEmpty)
}

@Test(arguments: ["M4A", "WAV"])
func extractingAudioKeepsVideoSources(slice: String) async {
    let outcomes = [ok("clip.mov", "clip.m4a"), ok("voice.wav", "voice.m4a"), ok("voice.m4a", "voice.wav")]
    let isVideo: @Sendable (URL) async -> Bool = { $0.lastPathComponent == "clip.mov" }
    #expect(await names(outcomes, slice: slice, isVideo: isVideo) == ["voice.wav", "voice.m4a"])
}

@Test func skippedFailedCancelledAndPartialAreNeverCandidates() async {
    let outcomes: [Outcome] = [
        .skipped(source: url("b.png"), .already(.png)), .failed(source: url("c.heic"), reason: "disk full"),
        .failed(source: url("d.heic"), reason: "cancelled"), ok("multi.tiff", "multi.png", complete: false),
    ]
    #expect(await names(outcomes, slice: "PNG").isEmpty)
}

@Test func noOutputsOrOutputEqualToSourceIsNeverACandidate() async {
    let outcomes: [Outcome] = [
        .converted(source: url("empty.jpg"), outputs: []), ok("same.png", "same.png"),
        .converted(source: url("dot.png"), outputs: [URL(fileURLWithPath: "/Users/me/Pictures/./dot.png")]),
    ]
    #expect(await names(outcomes, slice: "PNG").isEmpty)
}

@Test func duplicatesAreListedOnceInFirstSeenOrder() async {
    let twin = URL(fileURLWithPath: "/Users/me/Pictures/../Pictures/a.jpg")
    let outcomes: [Outcome] = [
        ok("b.jpg", "b.png"), ok("a.jpg", "a.png"), .converted(source: twin, outputs: [url("a 2.png")]), ok("b.jpg", "b 2.png"),
    ]
    let got = await Trash.trashCandidates(outcomes, slice: "PNG", isVideo: noVideo)
    #expect(got.map(\.source.lastPathComponent) == ["b.jpg", "a.jpg"])
    #expect(got.map(\.outputs) == [[url("b.png")], [url("a.png")]])
}

@Test func isVideoIsOnlyAskedForAudioSlices() async {
    let asked = Counter()
    _ = await Trash.trashCandidates([ok("a.mov", "a.mp4")], slice: "MP4") { _ in await asked.bump(); return true }
    #expect(await asked.value == 0)
}

private actor Counter {
    var value = 0
    func bump() { value += 1 }
}

// MARK: hasVideo on real files

@Test func hasVideoReadsTypeAndTracks() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let clip = try await AVFixture.write("clip.mov", in: dir)
    let voice = try await AVFixture.write("voice.m4a", in: dir, video: nil, fileType: .m4a)
    // Audio-only MP4 is still a .movie type, so it counts as video (errs on keeping the file).
    let audioMP4 = try await AVFixture.write("voice.mp4", in: dir, video: nil, fileType: .mp4)
    // A video track behind an audio extension is found by the probe.
    let hidden = try await AVFixture.write("hidden.m4a", in: dir, fileType: .mp4)
    #expect(await Trash.hasVideo(clip))
    #expect(await !Trash.hasVideo(voice))
    #expect(await Trash.hasVideo(audioMP4))
    #expect(await Trash.hasVideo(hidden))
}
