import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import SwivelCore

// MARK: Fixtures

/// Black text lines at 72 pt on white, `width` x 120 px per line.
private func textImage(_ lines: [String], width: Int = 1400) throws -> CGImage {
    let height = 120 * lines.count + 40
    let ctx = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (i, text) in lines.enumerated() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 72, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        ctx.textPosition = CGPoint(x: 40, y: height - 100 - i * 120)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
    }
    return try #require(ctx.makeImage())
}

private func save(_ image: CGImage, as type: UTType, to url: URL, orientation: Int? = nil) throws -> URL {
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    let props: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
    return url
}

private func text(_ outcome: Outcome) throws -> String? {
    guard case .converted(_, let outputs) = outcome, outputs.count == 1 else { return nil }
    return try String(contentsOf: outputs[0], encoding: .utf8)
}

// MARK: Images

@Test func imageTextIsRecognised() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try save(try textImage(["SWIVEL 2026", "quick brown fox"]), as: .png, to: dir.appendingPathComponent("shot.png"))
    let outcome = await Converter.extractText(source)
    #expect(outcome == .converted(source: source, outputs: [dir.appendingPathComponent("shot.txt")]))
    let got = try #require(try text(outcome)).lowercased()
    for word in ["swivel", "2026", "quick", "brown", "fox"] { #expect(got.contains(word), "missing \(word) in \(got)") }
}

// Stored sideways with EXIF 6. Vision also reads it untold, so this guards the result, not the orientation pass-through.
@Test func sidewaysPhotoIsReadUpright() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let upright = try textImage(["SWIVEL 2026"])
    let ctx = try #require(CGContext(
        data: nil, width: upright.height, height: upright.width, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.translateBy(x: CGFloat(upright.height), y: 0)
    ctx.rotate(by: .pi / 2)
    ctx.draw(upright, in: CGRect(x: 0, y: 0, width: upright.width, height: upright.height))
    let source = try save(try #require(ctx.makeImage()), as: .jpeg, to: dir.appendingPathComponent("side.jpg"), orientation: 6)
    let got = try #require(try text(await Converter.extractText(source))).lowercased()
    #expect(got.contains("swivel") && got.contains("2026"), "got \(got)")
}

@Test func blankImageHasNoText() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try save(try textImage([""]), as: .png, to: dir.appendingPathComponent("blank.png"))
    #expect(await Converter.extractText(source) == .skipped(source: source, .noText))
    #expect(try files(in: dir) == ["blank.png"])
}

// MARK: PDFs

@Test func pdfTextLayerIsUsedExactly() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let lines = ["Invisible layer one", "Second page words"]
    // Invisible text: only the text layer has it, so OCR would find nothing.
    let source = try writePDF(in: dir, pages: 2, size: CGSize(width: 612, height: 792)) { ctx, i in
        ctx.setTextDrawingMode(.invisible)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let attributed = NSAttributedString(string: lines[i], attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
    }
    #expect(try text(await Converter.extractText(source)) == "Invisible layer one\n\nSecond page words")
}

@Test func scannedPDFIsOCRdPageByPage() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let scans = [try textImage(["SWIVEL 2026"]), try textImage(["quick brown fox"])]
    let source = try writePDF(in: dir, pages: 2, size: CGSize(width: 700, height: 80)) { ctx, i in
        ctx.draw(scans[i], in: CGRect(x: 0, y: 0, width: 700, height: 80))
    }
    let got = try #require(try text(await Converter.extractText(source))).lowercased()
    let pages = got.components(separatedBy: "\n\n")
    #expect(pages.count == 2, "got \(got)")
    #expect(pages.first?.contains("swivel") == true && pages.first?.contains("2026") == true)
    #expect(pages.last?.contains("quick brown fox") == true)
}

@Test func lockedPDFIsSkippedForText() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir, options: [kCGPDFContextUserPassword: "pw", kCGPDFContextOwnerPassword: "own"])
    #expect(await Converter.extractText(source) == .skipped(source: source, .locked))
    #expect(try files(in: dir) == ["doc.pdf"])
}

@Test func blankPDFHasNoText() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir, pages: 2)
    #expect(await Converter.extractText(source) == .skipped(source: source, .noText))
}

// MARK: Batch

@Test func mixedDropGivesOneTextFilePerSource() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let shot = try save(try textImage(["SWIVEL 2026"]), as: .png, to: dir.appendingPathComponent("shot.png"))
    let doc = try writePDF(in: dir, size: CGSize(width: 612, height: 792)) { ctx, _ in
        ctx.textPosition = CGPoint(x: 72, y: 700)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        CTLineDraw(CTLineCreateWithAttributedString(
            NSAttributedString(string: "Layer text", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])), ctx)
    }
    let notes = dir.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: notes)
    let folder = dir.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

    #expect(await Converter.textBatch([shot, doc, notes, folder]) == [
        .converted(source: shot, outputs: [dir.appendingPathComponent("shot.txt")]),
        .converted(source: doc, outputs: [dir.appendingPathComponent("doc.txt")]),
        .skipped(source: notes, .notImage), .skipped(source: folder, .notImage),
    ])
    #expect(try String(contentsOf: dir.appendingPathComponent("doc.txt"), encoding: .utf8) == "Layer text")
}

@Test func takenTextNameKeepsBoth() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try save(try textImage(["SWIVEL 2026"]), as: .png, to: dir.appendingPathComponent("shot.png"))
    let existing = dir.appendingPathComponent("shot.txt")
    try Data("old".utf8).write(to: existing)
    #expect(await Converter.extractText(source) == .converted(source: source, outputs: [dir.appendingPathComponent("shot 2.txt")]))
    #expect(try Data(contentsOf: existing) == Data("old".utf8))
}

@Test func oversizedImageFailsBeforeOCR() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writeFlatPNG(side: 15000, in: dir)
    #expect(await Converter.extractText(source) == .failed(source: source, reason: "too large (max 200 MP)"))
}
