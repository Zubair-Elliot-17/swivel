import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SwivelCore

// Regression tests for the M3 review fix round.

/// A one-page PDF written by hand, so the media box can hold values CGContext would refuse.
private func rawPDF(mediaBox: String, in dir: URL, name: String = "raw") throws -> URL {
    var out = "%PDF-1.4\n", offsets: [Int] = []
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [\(mediaBox)] >>",
    ]
    for (i, object) in objects.enumerated() {
        offsets.append(out.utf8.count)
        out += "\(i + 1) 0 obj\n\(object)\nendobj\n"
    }
    let xref = out.utf8.count
    out += "xref\n0 4\n0000000000 65535 f \n" + offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
    out += "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    let url = dir.appendingPathComponent("\(name).pdf")
    try Data(out.utf8).write(to: url)
    return url
}

// MARK: F1 crafted page boxes

private let hostileBoxes = ["0 0 100000000000000000000 0.00000000001", "0 0 100000000000000000000 1", "0 0 0.5 0.5"]

@Test(arguments: hostileBoxes)
func hostilePageBoxFailsForImages(box: String) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try rawPDF(mediaBox: box, in: dir)
    #expect(await Converter.convert(source, to: .png) == .failed(source: source, reason: "couldn't read PDF"))
    #expect(try files(in: dir) == ["raw.pdf"])
}

@Test(arguments: hostileBoxes)
func hostilePageBoxFailsForText(box: String) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try rawPDF(mediaBox: box, in: dir)
    #expect(await Converter.extractText(source) == .failed(source: source, reason: "couldn't read PDF"))
    #expect(try files(in: dir) == ["raw.pdf"])
}

@Test func longThinPageIsClampedPerSide() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try rawPDF(mediaBox: "0 0 40000 10", in: dir)
    guard case .converted(_, let outputs) = await Converter.convert(source, to: .png) else { Issue.record("not converted"); return }
    let out = try ReadBack(outputs[0])
    #expect(out.width == 65535 && (1...21).contains(out.height), "\(out.width)x\(out.height)")
}

// MARK: F2 TIFF size and per-document pixel budget

private func tiffCompression(_ url: URL) throws -> Int? {
    let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    return (props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int
}

// A blank 2000x2000 page was 12 MB as uncompressed TIFF.
@Test func pdfPageTIFFIsLZWCompressed() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir, size: CGSize(width: 960, height: 960))
    guard case .converted(_, let outputs) = await Converter.convert(source, to: .tiff) else { Issue.record("not converted"); return }
    #expect(try ReadBack(outputs[0]).width == 2000)
    #expect(try tiffCompression(outputs[0]) == 5)
    #expect(try Data(contentsOf: outputs[0]).count < 1_000_000)
}

@Test func imageToTIFFIsLZWCompressed() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir)
    guard case .converted(_, let outputs) = await Converter.convert(source, to: .tiff) else { Issue.record("not converted"); return }
    #expect(try tiffCompression(outputs[0]) == 5)
}

/// Three 480 pt pages: 1000 x 1000 px each at 150 dpi.
private func megapixelPages(in dir: URL, name: String) throws -> URL {
    try writePDF(in: dir, name: name, pages: 3, size: CGSize(width: 480, height: 480))
}

@Test func pagesPastThePixelBudgetAreSkippedAndLogged() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let tag = "budget\(UUID().uuidString.prefix(8))"
    let source = try megapixelPages(in: dir, name: tag)
    guard case .converted(_, let outputs) = Converter.renderPDF(source, to: .png, maxPixels: 2_000_000) else {
        Issue.record("not converted"); return
    }
    #expect(outputs.map(\.lastPathComponent) == ["\(tag) page 1.png", "\(tag) page 2.png"])
    #expect(try loggedLines(containing: "\(tag).pdf: 1 page skipped (max 2 MP)").count == 1)
}

@Test func firstPageOverThePixelBudgetWritesNothing() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try megapixelPages(in: dir, name: "big")
    #expect(Converter.renderPDF(source, to: .png, maxPixels: 500_000) == .skipped(source: source, .pageLimit))
    #expect(try files(in: dir) == ["big.pdf"])
}

// At 300 dpi each 240 pt page is 1 MP; text-layer pages would not count, these are blank so they are OCR'd.
@Test func ocrStopsAtThePixelBudgetAndLogs() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let tag = "ocrbudget\(UUID().uuidString.prefix(8))"
    let source = try writePDF(in: dir, name: tag, pages: 3, size: CGSize(width: 240, height: 240))
    #expect(await Converter.extractText(source, maxPixels: 2_000_000) == .skipped(source: source, .noText))
    #expect(try loggedLines(containing: "\(tag).pdf: 1 page skipped (max 2 MP)").count == 1)
}

// MARK: F3 combined PDF streams to a temp file

@Test func combinedPDFLeavesNoTempFileBehind() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let a = try write(.png, in: dir, name: "a"), b = try write(.jpeg, in: dir, name: "b")
    try Data("old".utf8).write(to: dir.appendingPathComponent("a.pdf"))
    let out = dir.appendingPathComponent("a 2.pdf")
    #expect(await Converter.makePDF([a, b]) == [.converted(source: a, outputs: [out]), .converted(source: b, outputs: [out])])
    #expect(try PDFReadBack(out).pageSizes == [CGSize(width: 16, height: 8), CGSize(width: 20, height: 40)])
    #expect(try files(in: dir) == ["a.png", "b.jpg", "a.pdf", "a 2.pdf"])
}

@Test func combinedPDFLandsNextToTheFirstSourceAcrossFolders() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let x = dir.appendingPathComponent("x"), y = dir.appendingPathComponent("y")
    for folder in [x, y] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
    let a = try write(.png, in: x, name: "a"), b = try write(.png, in: y, name: "b")
    let out = x.appendingPathComponent("a.pdf")
    #expect(await Converter.makePDF([a, b]) == [.converted(source: a, outputs: [out]), .converted(source: b, outputs: [out])])
    #expect(try files(in: x) == ["a.png", "a.pdf"] && files(in: y) == ["b.png"])
}

@Test func noFreeNameFailsAndRemovesTheTempFile() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir, name: "a")
    for attempt in 1...9999 {
        FileManager.default.createFile(atPath: OutputName.candidate(for: source, ext: "pdf", attempt: attempt).path, contents: nil)
    }
    let before = try files(in: dir)
    #expect(await Converter.makePDF([source]) == [.failed(source: source, reason: "no free file name")])
    #expect(try files(in: dir) == before)
}
