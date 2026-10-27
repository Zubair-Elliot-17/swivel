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
