import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
import SwivelCore

// Tester gap tests for M3 (AC 7, 8, 9 edges the main suites don't pin).

/// A PDF whose page i carries `lines[i]` as a visible text layer (empty string = blank page).
private func textPDF(_ lines: [String], in dir: URL, name: String = "doc", options: [CFString: Any] = [:]) throws -> URL {
    try writePDF(in: dir, name: name, pages: lines.count, size: CGSize(width: 612, height: 792), options: options) { ctx, i in
        guard !lines[i].isEmpty else { return }
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(
            NSAttributedString(string: lines[i], attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])), ctx)
    }
}

private func textOf(_ outcome: Outcome) throws -> String? {
    guard case .converted(_, let outputs) = outcome, outputs.count == 1 else { return nil }
    return try String(contentsOf: outputs[0], encoding: .utf8)
}

// Catches a missing or off-by-one 100-page cap in extractText, or a missing log note.
@Test func textStopsAtOneHundredPagesAndLogs() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let tag = "txtcap\(UUID().uuidString.prefix(8))"
    let source = try textPDF((1...101).map { "Page \($0)" }, in: dir, name: tag)
    let pages = try #require(try textOf(await Converter.extractText(source))).components(separatedBy: "\n\n")
    #expect(pages.count == 100 && pages.first == "Page 1" && pages.last == "Page 100")
    #expect(try loggedLines(containing: "\(tag).pdf: 1 page skipped (max 100)").count == 1)
}

// Accepted deviation: blank pages are dropped, so no run of blank lines appears between pages.
@Test func blankPageInTheMiddleIsDropped() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try textPDF(["One", "", "Three"], in: dir)
    #expect(try textOf(await Converter.extractText(source)) == "One\n\nThree")
}

// AC 8 bullet 3 applied to Text: catches openPDF's parse failure being mapped to a skip.
@Test func brokenPDFFailsForText() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = dir.appendingPathComponent("broken.pdf")
    try Data("%PDF-1.4 not really".utf8).write(to: source)
    #expect(await Converter.extractText(source) == .failed(source: source, reason: "couldn't read PDF"))
    #expect(try files(in: dir) == ["broken.pdf"])
}

// AC 8: owner-password-only PDFs convert; catches isEncrypted/copy-permission checks blocking Text.
@Test func ownerPasswordOnlyPDFGivesText() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try textPDF(["Owner only"], in: dir, options: [kCGPDFContextOwnerPassword: "own", kCGPDFContextAllowsCopying: false])
    #expect(try textOf(await Converter.extractText(source)) == "Owner only")
}

// AC 9 "UTF-8": catches an ASCII/Latin-1 write or lossy conversion.
@Test func nonASCIITextIsWrittenAsUTF8() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let line = "Café naïve façade — über"
    let outcome = await Converter.extractText(try textPDF([line], in: dir))
    guard case .converted(_, let outputs) = outcome else { Issue.record("got \(outcome)"); return }
    #expect(try Data(contentsOf: outputs[0]) == Data(line.utf8))
}

// Catches removing the 200 MP clamp in render(): 14400 pt square at 150 dpi would be 900 MP.
@Test func hugePageIsClampedTo200MP() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir, size: CGSize(width: 14400, height: 14400))
    let outcome = await Converter.convert(source, to: .jpeg)
    guard case .converted(_, let outputs) = outcome else { Issue.record("got \(outcome)"); return }
    let src = try #require(CGImageSourceCreateWithURL(outputs[0] as CFURL, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
    let w = try #require(props[kCGImagePropertyPixelWidth] as? Int), h = try #require(props[kCGImagePropertyPixelHeight] as? Int)
    #expect(w == h && w * h <= 200_000_000 && w * h > 199_000_000, "\(w)x\(h)")
}

// AC 7: exactly 100 pages gives all 100 and no log line; catches `>=` in the cap check.
@Test func exactlyOneHundredPagesAreAllRendered() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let tag = "hundred\(UUID().uuidString.prefix(8))"
    let source = try writePDF(in: dir, name: tag, pages: 100, size: CGSize(width: 10, height: 10))
    guard case .converted(_, let outputs) = await Converter.convert(source, to: .png) else { Issue.record("not converted"); return }
    #expect(outputs.count == 100 && outputs.last?.lastPathComponent == "\(tag) page 100.png")
    #expect(try loggedLines(containing: "\(tag).pdf:").isEmpty)
}

// AC 5/6: a later source's frames keep their own media box (catches beginPDFPage(nil) reusing the default box).
@Test func eachPageKeepsItsOwnMediaBox() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let a = try write(.png, in: dir, name: "a"), b = try write(.jpeg, in: dir, name: "b"), c = try write(.png, in: dir, name: "c")
    _ = await Converter.makePDF([a, b, c])
    let sizes = try PDFReadBack(dir.appendingPathComponent("a.pdf")).pageSizes
    #expect(sizes == [CGSize(width: 16, height: 8), CGSize(width: 20, height: 40), CGSize(width: 16, height: 8)])
}

// AC 7 renders the crop box: catches drawing or sizing from the media box instead.
@Test func cropBoxIsWhatGetsRendered() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let flat = try writePDF(in: dir, name: "flat") { ctx, _ in
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 72, width: 72, height: 72))  // top half red
    }
    let doc = try #require(PDFDocument(url: flat))
    doc.page(at: 0)?.setBounds(CGRect(x: 0, y: 72, width: 72, height: 72), for: .cropBox)
    let source = dir.appendingPathComponent("cropped.pdf")
    #expect(doc.write(to: source))
    _ = await Converter.convert(source, to: .png)
    let out = try ReadBack(dir.appendingPathComponent("cropped.png"))
    #expect((out.width, out.height) == (150, 150))
    let px = out.pixel(75, 75)
    #expect(px[0] > 245 && px[1] < 10, "centre \(px)")
}
