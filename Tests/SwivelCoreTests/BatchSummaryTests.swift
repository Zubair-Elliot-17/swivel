import Foundation
import Testing
import SwivelCore

private func url(_ name: String) -> URL { URL(fileURLWithPath: "/Users/me/Pictures/\(name)") }
private func ok(_ src: String, _ out: String) -> Outcome { .converted(source: url(src), output: url(out)) }

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

@Test(arguments: [
    (allConverted, "Last: photo.jpg (3 of 3)"),
    (withSkip, "Last: photo.jpg (2 of 3, 1 skipped)"),
    (withFailure, "Failed: photo.heic: disk full (1 of 3 converted)"),
    (mixed, "Failed: photo.heic: read-only (1 of 3 converted, 1 skipped)"),
    (allSkipped, "Skipped 3 of 3: already PNG"),
])
func menuLine(outcomes: [Outcome], expected: String) {
    #expect(BatchSummary(outcomes).menuLine == expected)
}

@Test(arguments: [allConverted, withSkip, withFailure, mixed, allSkipped])
func countsSumToInput(outcomes: [Outcome]) {
    let s = BatchSummary(outcomes)
    #expect(s.converted + s.skipped + s.failed == outcomes.count)
}

@Test func outputsAreOnlyConvertedFilesInOrder() {
    #expect(BatchSummary(withSkip).outputs == [url("a.jpg"), url("photo.jpg")])
    #expect(BatchSummary(allSkipped).outputs.isEmpty)
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
