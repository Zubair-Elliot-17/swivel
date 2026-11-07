import Foundation
import Testing
import SwivelCore

private func url(_ name: String) -> URL { URL(fileURLWithPath: "/Users/me/Pictures/\(name)") }
private func ok(_ src: String, _ out: String...) -> Outcome { .converted(source: url(src), outputs: out.map(url)) }

private let allConverted = [ok("a.png", "a.jpg"), ok("b.heic", "b.jpg"), ok("photo.png", "photo.jpg")]
private let withSkip = [ok("a.png", "a.jpg"), .skipped(source: url("b.jpg"), .already(.jpeg)), ok("photo.png", "photo.jpg")]
private let withFailure: [Outcome] = [
    ok("a.png", "a.jpg"), .failed(source: url("photo.heic"), reason: "disk full"),
    .failed(source: url("c.heic"), reason: "other"),
]
private let mixed: [Outcome] = [
    .skipped(source: url("d"), .notImage), .failed(source: url("photo.heic"), reason: "read-only"), ok("a.png", "a.jpg"),
]
private let allSkipped: [Outcome] = [
    .skipped(source: url("a.png"), .already(.png)), .skipped(source: url("dir"), .notImage),
    .skipped(source: url("b.png"), .already(.png)),
]
// Two images into one PDF share its output; the other two sources are skipped.
private let combinedPDF: [Outcome] = [
    ok("b.png", "b.pdf"), ok("a.jpg", "b.pdf"), .skipped(source: url("notes.txt"), .notImage),
    .skipped(source: url("doc.pdf"), .alreadyPDF),
]
private let pdfPages = [ok("doc.pdf", "doc page 1.png", "doc page 2.png", "doc page 3.png")]

@Test(arguments: [
    (allConverted, "Last: photo.jpg (3 of 3)"),
    (withSkip, "Last: photo.jpg (2 of 3, 1 skipped)"),
    (withFailure, "Failed: photo.heic: disk full (1 of 3 converted)"),
    (mixed, "Failed: photo.heic: read-only (1 of 3 converted, 1 skipped)"),
    (allSkipped, "Skipped 3 of 3: already PNG"),
    (combinedPDF, "Last: b.pdf (2 of 4, 2 skipped)"),
    (pdfPages, "Last: doc page 3.png (1 of 1)"),
    ([.skipped(source: url("s.pdf"), .locked)], "Skipped 1 of 1: password protected"),
    ([.skipped(source: url("s.pdf"), .alreadyPDF)], "Skipped 1 of 1: already PDF"),
    ([.skipped(source: url("s.png"), .noText)], "Skipped 1 of 1: no text found"),
    ([.skipped(source: url("s.png"), .pageLimit)], "Skipped 1 of 1: page limit"),
])
func menuLine(outcomes: [Outcome], expected: String) {
    #expect(BatchSummary(outcomes).menuLine == expected)
}

@Test(arguments: [allConverted, withSkip, withFailure, mixed, allSkipped, combinedPDF, pdfPages])
func countsSumToInput(outcomes: [Outcome]) {
    let s = BatchSummary(outcomes)
    #expect(s.converted + s.skipped + s.failed == outcomes.count)
}

@Test func outputsAreOnlyConvertedFilesInOrder() {
    #expect(BatchSummary(withSkip).outputs == [url("a.jpg"), url("photo.jpg")])
    #expect(BatchSummary(allSkipped).outputs.isEmpty)
}

@Test func sharedOutputIsListedOnceAndPagesInOrder() {
    #expect(BatchSummary(combinedPDF).outputs == [url("b.pdf")])
    #expect(BatchSummary(combinedPDF + pdfPages).outputs
        == [url("b.pdf"), url("doc page 1.png"), url("doc page 2.png"), url("doc page 3.png")])
}

@Test(arguments: [
    (CocoaError(.fileWriteNoPermission) as Error, "no permission"),
    (CocoaError(.fileWriteOutOfSpace), "disk full"),
    (CocoaError(.fileWriteVolumeReadOnly), "read-only volume"),
    (POSIXError(.ENOSPC), "disk full"),
    (POSIXError(.EACCES), "no permission"),
    (POSIXError(.EROFS), "read-only volume"),
    (NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "too large (max 200 MP)"]), "too large (max 200 MP)"),
    (NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: String(repeating: "a", count: 61)]),
     String(repeating: "a", count: 59) + "…"),
])
func menuReasonIsShort(error: Error, expected: String) {
    #expect(menuReason(for: error) == expected)
}

@Test func sixtyCharReasonIsKept() {
    let sixty = String(repeating: "b", count: 60)
    #expect(menuReason(for: NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: sixty])) == sixty)
}

// MARK: M4 audio/video states

private let cancelledAV: [Outcome] = [
    ok("a.mov", "a.mp4"), .failed(source: url("b.mov"), reason: "cancelled"), .failed(source: url("c.mov"), reason: "cancelled"),
    .failed(source: url("d.mov"), reason: "cancelled"), .failed(source: url("e.mov"), reason: "cancelled"),
]
private let mixedAV: [Outcome] = [ok("clip.mov", "clip.mp4"), .skipped(source: url("a.jpg"), .noVideo)]

private let avLines: [([Outcome], String)] = [
    (cancelledAV, "Failed: b.mov: cancelled (1 of 5 converted)"),
    (mixedAV, "Last: clip.mp4 (1 of 2, 1 skipped)"),
    ([.skipped(source: url("v.m4a"), .noVideo)], "Skipped 1 of 1: no video"),
    ([.skipped(source: url("m.mov"), .noAudio)], "Skipped 1 of 1: no audio"),
    ([.skipped(source: url("x.mkv"), .notSupported)], "Skipped 1 of 1: not supported by macOS"),
    ([.skipped(source: url("x.mp4"), .codec)], "Skipped 1 of 1: codec not supported"),
    ([.skipped(source: url("x.m4v"), .drm)], "Skipped 1 of 1: DRM protected"),
    ([.skipped(source: url("x.mp4"), .alreadyAV(.mp4))], "Skipped 1 of 1: already MP4"),
    ([.skipped(source: url("x.mp4"), .alreadyAV(.hevc))], "Skipped 1 of 1: already HEVC"),
    ([.skipped(source: url("x.wav"), .alreadyAV(.wav))], "Skipped 1 of 1: already WAV"),
]

@Test(arguments: avLines)
func avMenuLine(outcomes: [Outcome], expected: String) {
    let s = BatchSummary(outcomes)
    #expect(s.menuLine == expected)
    #expect(s.converted + s.skipped + s.failed == outcomes.count)
}

@Test func avTargetsMatchTheVideoSlices() {
    #expect(AVTarget.allCases.map(\.rawValue) == ["MP4", "HEVC", "MOV", "GIF", "M4A", "WAV"])
    #expect(AVTarget.allCases.map(\.fileExtension) == ["mp4", "mp4", "mov", "gif", "m4a", "wav"])
    #expect(AVTarget.allCases.filter(\.needsVideo) == [.mp4, .hevc, .mov, .gif])
}

@Test(arguments: [
    (CancellationError() as Error, "cancelled"),
    (NSError(domain: "AVFoundationErrorDomain", code: -11807), "disk full"),
])
func avMenuReason(error: Error, expected: String) {
    #expect(menuReason(for: error) == expected)
}

@Test(arguments: [
    (0.42, "Converting clip.mov 42% (2 of 5)"),
    (1.7, "Converting clip.mov 100% (2 of 5)"),
    (-0.3, "Converting clip.mov 0% (2 of 5)"),
    (Double.nan, "Converting clip.mov 0% (2 of 5)"),
    (Double.infinity, "Converting clip.mov 100% (2 of 5)"),
    (0.999, "Converting clip.mov 99% (2 of 5)"),
])
func progressLineIsClamped(fraction: Double, expected: String) {
    #expect(progressLine(name: "clip.mov", fraction: fraction, index: 2, total: 5) == expected)
}

// MARK: not moved to Trash (M6)

@Test(arguments: [
    (allConverted, 0, "Last: photo.jpg (3 of 3)"),
    (allConverted, 1, "Last: photo.jpg (3 of 3) (1 not moved to Trash)"),
    (allConverted, 3, "Last: photo.jpg (3 of 3) (3 not moved to Trash)"),
    (withFailure, 0, "Failed: photo.heic: disk full (1 of 3 converted)"),
    (withFailure, 1, "Failed: photo.heic: disk full (1 of 3 converted) (1 not moved to Trash)"),
    (mixed, 3, "Failed: photo.heic: read-only (1 of 3 converted, 1 skipped) (3 not moved to Trash)"),
    (allSkipped, 0, "Skipped 3 of 3: already PNG"),
    (allSkipped, 1, "Skipped 3 of 3: already PNG (1 not moved to Trash)"),
    (allSkipped, 3, "Skipped 3 of 3: already PNG (3 not moved to Trash)"),
])
func notTrashedSuffix(outcomes: [Outcome], notTrashed: Int, expected: String) {
    #expect(BatchSummary(outcomes, notTrashed: notTrashed).menuLine == expected)
}

@Test func notTrashedLeavesCountsAndOutputs() {
    let plain = BatchSummary(withSkip), marked = BatchSummary(withSkip, notTrashed: 2)
    #expect([marked.converted, marked.skipped, marked.failed] == [2, 1, 0] as [Int])
    #expect([plain.converted, plain.skipped, plain.failed] == [2, 1, 0] as [Int])
    #expect(marked.outputs == plain.outputs)
}

@Test func partialConversionCountsLikeAFullOne() {
    let partial: [Outcome] = [.converted(source: url("multi.tiff"), outputs: [url("multi.png")], complete: false)]
    let s = BatchSummary(partial)
    #expect(s.menuLine == "Last: multi.png (1 of 1)")
    #expect(s.converted == 1 && s.outputs == [url("multi.png")])
}

// MARK: Menu names (M7 AC 8): control, format and separator characters never reach the menu.

@Test(arguments: [
    "\u{0}", "\u{1F}", "\n", "\r", "\t", "\u{7F}", "\u{85}", "\u{9F}",  // C0, DEL, C1
    "\u{200B}", "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}",  // zero width, LRM/RLM
    "\u{202A}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2069}",  // bidi embeddings, overrides, isolates
    "\u{2028}", "\u{2029}", "\u{FEFF}",  // line/paragraph separators, BOM
])
func menuNameStripsInvisibleCharacters(_ c: String) {
    #expect(menuName("x\(c)y.jpg") == "xy.jpg")
}

@Test(arguments: ["café.png", "cafe\u{301}.png", "🙂 photo.png", "my  file .png", "日本語.heic", "a-b_c (2).mov"])
func menuNameKeepsVisibleText(_ name: String) {
    #expect(menuName(name) == name)
}

@Test(arguments: ["", "\u{202E}", "\n\u{200B}\u{FEFF}"])
func menuNameOfNothingVisibleIsFile(_ name: String) {
    #expect(menuName(name) == "file")
}

@Test func menuLinesUseMenuNames() {
    let rlo = url("x\u{202E}gnp.exe"), lf = url("a\nb.png")
    #expect(BatchSummary([.converted(source: rlo, outputs: [lf])]).menuLine == "Last: ab.png (1 of 1)")
    #expect(BatchSummary([.failed(source: rlo, reason: "disk full")]).menuLine == "Failed: xgnp.exe: disk full (0 of 1 converted)")
    #expect(progressLine(name: "a\nb.mov", fraction: 0.5, index: 1, total: 1) == "Converting ab.mov 50% (1 of 1)")
    // Reveal still gets the real URL.
    #expect(BatchSummary([.converted(source: rlo, outputs: [lf])]).outputs == [lf])
}
