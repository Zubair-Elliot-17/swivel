import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Testing
import UniformTypeIdentifiers
import SwivelCore

// MARK: Helpers

/// A PDF of `pages` pages of `size` points; `draw` paints page i (0-based), `options` can set passwords.
@discardableResult
func writePDF(
    in dir: URL, name: String = "doc", pages: Int = 1, size: CGSize = CGSize(width: 72, height: 144),
    options: [CFString: Any] = [:], draw: (CGContext, Int) -> Void = { _, _ in }
) throws -> URL {
    let url = dir.appendingPathComponent("\(name).pdf")
    var box = CGRect(origin: .zero, size: size)
    let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, options as CFDictionary))
    for i in 0..<pages {
        ctx.beginPDFPage(nil)
        draw(ctx, i)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return url
}

/// A TIFF with `frames` copies of the PNG fixture.
func writeTIFF(frames: Int, in dir: URL, name: String = "multi") throws -> URL {
    let png = try ReadBack(try write(.png, in: dir, name: "\(name)-src"))
    let url = dir.appendingPathComponent("\(name).tiff")
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, frames, nil))
    for _ in 0..<frames { CGImageDestinationAddImage(dest, png.image, nil) }
    #expect(CGImageDestinationFinalize(dest))
    try FileManager.default.removeItem(at: dir.appendingPathComponent("\(name)-src.png"))
    return url
}

struct PDFReadBack {
    let doc: CGPDFDocument, bytes: String
    init(_ url: URL) throws {
        doc = try #require(CGPDFDocument(url as CFURL))
        bytes = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
    var pageSizes: [CGSize] { (1...max(doc.numberOfPages, 1)).compactMap { doc.page(at: $0)?.getBoxRect(.mediaBox).size } }

    /// RGBA at (x, y), y from the top, of page `n` (1-based) rendered at 1 px per point.
    func pixel(page n: Int, _ x: Int, _ y: Int) throws -> [UInt8] {
        let page = try #require(doc.page(at: n))
        let box = page.getBoxRect(.mediaBox)
        let (w, h) = (Int(box.width), Int(box.height))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.drawPDFPage(page)
        }
        let i = (y * w + x) * 4
        return Array(buf[i..<i + 4])
    }
}

/// Swivel log lines this test process wrote that mention `marker`.
func loggedLines(containing marker: String) throws -> [String] {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", "dev.zubair.swivel"))
    return entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }.filter { $0.contains(marker) }
}

// MARK: Orientation

enum Corner { case topLeft, topRight, bottomRight, bottomLeft }

/// EXIF spec: where the stored image's top-left and top-right pixels appear once displayed.
@Test(arguments: [
    (1, Corner.topLeft, Corner.topRight), (2, .topRight, .topLeft), (3, .bottomRight, .bottomLeft), (4, .bottomLeft, .bottomRight),
    (5, .topLeft, .bottomLeft), (6, .topRight, .bottomRight), (7, .bottomRight, .topRight), (8, .bottomLeft, .topLeft),
])
func orientedPageMapsCorners(orientation: Int, storedTopLeft: Corner, storedTopRight: Corner) {
    let (w, h) = (40, 20)
    let page = orientedPage(orientation: orientation, width: w, height: h)
    let swapped = orientation >= 5
    #expect(page.size == (swapped ? CGSize(width: h, height: w) : CGSize(width: w, height: h)))
    // The drawn image rect lands exactly on the page.
    #expect(CGRect(x: 0, y: 0, width: w, height: h).applying(page.transform) == CGRect(origin: .zero, size: page.size))

    func at(_ corner: Corner) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: 0, y: page.size.height)
        case .topRight: CGPoint(x: page.size.width, y: page.size.height)
        case .bottomRight: CGPoint(x: page.size.width, y: 0)
        case .bottomLeft: .zero
        }
    }
    // CG draws the stored top row at the top of the rect (y = h).
    #expect(CGPoint(x: 0, y: h).applying(page.transform) == at(storedTopLeft))
    #expect(CGPoint(x: w, y: h).applying(page.transform) == at(storedTopRight))
}

@Test(arguments: [0, 9])
func unknownOrientationIsUpright(orientation: Int) {
    let page = orientedPage(orientation: orientation, width: 40, height: 20)
    #expect(page.size == CGSize(width: 40, height: 20) && page.transform == .identity)
}

@Test func fixtureJPEGBecomesUprightPortraitPage() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.jpeg, in: dir)
    #expect(await Converter.makePDF([source]) == [.converted(source: source, outputs: [dir.appendingPathComponent("photo.pdf")])])
    let pdf = try PDFReadBack(dir.appendingPathComponent("photo.pdf"))
    #expect(pdf.pageSizes == [CGSize(width: 20, height: 40)])
    let top = try pdf.pixel(page: 1, 10, 5), bottom = try pdf.pixel(page: 1, 10, 35)
    #expect(top[0] > 200 && top[2] < 60, "top \(top)")
    #expect(bottom[2] > 200 && bottom[0] < 60, "bottom \(bottom)")
}

// MARK: Images -> PDF

@Test func pngStaysLosslessAtPixelSize() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir)
    let out = dir.appendingPathComponent("photo.pdf")
    #expect(await Converter.makePDF([source]) == [.converted(source: source, outputs: [out])])
    let pdf = try PDFReadBack(out)
    #expect(pdf.pageSizes == [CGSize(width: 16, height: 8)])
    #expect(pdf.bytes.contains("FlateDecode") && !pdf.bytes.contains("DCTDecode"))
}

@Test func jpegBytesPassThrough() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.jpeg, in: dir)
    _ = await Converter.makePDF([source])
    let out = dir.appendingPathComponent("photo.pdf")
    #expect(try PDFReadBack(out).bytes.contains("DCTDecode"))
    let sourceSize = try Data(contentsOf: source).count, outSize = try Data(contentsOf: out).count
    #expect(Double(outSize) <= Double(sourceSize) * 1.05 + 4096, "\(outSize) vs \(sourceSize)")
}

// Q1: lossy sources are re-encoded to JPEG so a photo stays near its source size.
@Test(arguments: [ImageFormat.heic, .webp])
func lossySourcesBecomeJPEGPages(format: ImageFormat) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let jpeg = try write(.jpeg, in: dir, name: "src")
    guard case .converted(_, let made) = await Converter.convert(jpeg, to: format), let source = made.first else {
        Issue.record("fixture failed"); return
    }
    _ = await Converter.makePDF([source])
    let pdf = try PDFReadBack(dir.appendingPathComponent("src.pdf"))
    #expect(pdf.bytes.contains("DCTDecode"))
    #expect(pdf.pageSizes == [CGSize(width: 20, height: 40)])
    let top = try pdf.pixel(page: 1, 10, 5)
    #expect(top[0] > 200 && top[2] < 60, "top \(top)")
}

@Test func multiFrameTIFFGivesOnePagePerFrame() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writeTIFF(frames: 3, in: dir)
    _ = await Converter.makePDF([source])
    #expect(try PDFReadBack(dir.appendingPathComponent("multi.pdf")).pageSizes == Array(repeating: CGSize(width: 16, height: 8), count: 3))
}

@Test func mixedDropMakesOnePDFInDropOrder() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let b = try write(.png, in: dir, name: "b"), a = try write(.jpeg, in: dir, name: "a")
    let notes = dir.appendingPathComponent("notes.txt")
    try Data("hi".utf8).write(to: notes)
    let doc = try writePDF(in: dir)
    let out = dir.appendingPathComponent("b.pdf")

    #expect(await Converter.makePDF([b, a, notes, doc]) == [
        .converted(source: b, outputs: [out]), .converted(source: a, outputs: [out]),
        .skipped(source: notes, .notImage), .skipped(source: doc, .alreadyPDF),
    ])
    #expect(try PDFReadBack(out).pageSizes == [CGSize(width: 16, height: 8), CGSize(width: 20, height: 40)])
}

@Test func takenPDFNameKeepsBoth() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir, name: "b")
    let existing = dir.appendingPathComponent("b.pdf")
    try Data("old".utf8).write(to: existing)
    #expect(await Converter.makePDF([source]) == [.converted(source: source, outputs: [dir.appendingPathComponent("b 2.pdf")])])
    #expect(try Data(contentsOf: existing) == Data("old".utf8))
}

// MARK: Caps

@Test func sourcesPastThePageCapAreSkippedAndLogged() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let tag = UUID().uuidString.prefix(8)
    let sources = try (1...3).map { try write(.png, in: dir, name: "cap\(tag)-\($0)") }
    let outcomes = await Converter.makePDF(sources, maxPages: 2)
    let out = dir.appendingPathComponent("cap\(tag)-1.pdf")
    #expect(outcomes == [
        .converted(source: sources[0], outputs: [out]), .converted(source: sources[1], outputs: [out]),
        .skipped(source: sources[2], .pageLimit),
    ])
    #expect(try PDFReadBack(out).pageSizes.count == 2)
    #expect(try loggedLines(containing: "cap\(tag)-3.png: 1 page skipped (max 2)").count == 1)
}

@Test func sourceCutPartWayCountsAsConverted() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let tag = UUID().uuidString.prefix(8)
    let source = try writeTIFF(frames: 3, in: dir, name: "cut\(tag)")
    let out = dir.appendingPathComponent("cut\(tag).pdf")
    #expect(await Converter.makePDF([source], maxPages: 2) == [.converted(source: source, outputs: [out])])
    #expect(try PDFReadBack(out).pageSizes.count == 2)
    #expect(try loggedLines(containing: "cut\(tag).tiff: 1 page skipped (max 2)").count == 1)
}

@Test func oversizedFrameFailsOnlyItsSource() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let photo = try write(.png, in: dir), flat = try writeFlatPNG(side: 15000, in: dir)
    let out = dir.appendingPathComponent("photo.pdf")
    #expect(await Converter.makePDF([flat, photo]) == [
        .failed(source: flat, reason: "too large (max 200 MP)"), .converted(source: photo, outputs: [out]),
    ])
    #expect(try PDFReadBack(out).pageSizes.count == 1)
}

@Test func noPagesMeansNoPDF() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let flat = try writeFlatPNG(side: 15000, in: dir)
    let folder = dir.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let before = try files(in: dir)
    #expect(await Converter.makePDF([folder, flat]) == [
        .skipped(source: folder, .notImage), .failed(source: flat, reason: "too large (max 200 MP)"),
    ])
    #expect(try files(in: dir) == before)
    #expect(await Converter.makePDF([]) == [])
}

@Test func unreadableImageIsSkippedFromPDF() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
    #expect(await Converter.makePDF([source]) == [.skipped(source: source, .unreadable)])
    #expect(try files(in: dir) == ["photo.png"])
}

@Test func readOnlyFolderFailsEverySourceThatHadPages() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let a = try write(.png, in: dir, name: "a"), b = try write(.png, in: dir, name: "b")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    let outcomes = await Converter.makePDF([a, b])
    #expect(outcomes.count == 2)
    for (outcome, source) in zip(outcomes, [a, b]) {
        guard case .failed(source, "no permission", _) = outcome else { Issue.record("got \(outcome)"); continue }
    }
}

// JPEG has no alpha; ImageIO flattens a transparent HEIC on black, so frames with alpha stay lossless.
@Test(arguments: [ImageFormat.heic, .webp])
func transparentLossySourceIsNotBlackened(format: ImageFormat) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let png = try write(.png, in: dir, name: "src")
    guard case .converted(_, let made) = await Converter.convert(png, to: format), let source = made.first else {
        Issue.record("fixture failed"); return
    }
    try FileManager.default.removeItem(at: png)
    _ = await Converter.makePDF([source])
    let px = try PDFReadBack(dir.appendingPathComponent("src.pdf")).pixel(page: 1, 2, 4)
    #expect(px[3] < 10 || px[0] > 240, "transparent area drew as \(px)")
}
