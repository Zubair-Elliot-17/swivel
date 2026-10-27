import CoreGraphics
import Foundation
import ImageIO
import OSLog
import PDFKit
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

// MARK: PDF -> images

private func names(_ outcome: Outcome) -> [String] {
    guard case .converted(_, let outputs) = outcome else { return [] }
    return outputs.map(\.lastPathComponent)
}

@Test(arguments: ImageFormat.allCases)
func pdfPagesBecomeImagesAt150DPI(target: ImageFormat) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir, pages: 3)
    let outcome = await Converter.convert(source, to: target)
    let ext = target.fileExtension
    #expect(names(outcome) == ["doc page 1.\(ext)", "doc page 2.\(ext)", "doc page 3.\(ext)"])
    for name in names(outcome) {
        let out = try ReadBack(dir.appendingPathComponent(name))
        #expect(out.type == target.utType.identifier)
        #expect((out.width, out.height) == (150, 300))
        let px = out.pixel(75, 150)
        #expect(px[3] == 255 && px[0] > 245 && px[1] > 245 && px[2] > 245, "blank page should be opaque white, got \(px)")
    }
}

@Test func pngPageHasNoAlphaChannel() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    _ = await Converter.convert(try writePDF(in: dir), to: .png)
    let src = try #require(CGImageSourceCreateWithURL(dir.appendingPathComponent("doc.png") as CFURL, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
    #expect(props[kCGImagePropertyHasAlpha] as? Bool != true)
}

@Test func pageContentIsDrawn() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir) { ctx, _ in
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 72, width: 72, height: 72))  // top half
    }
    _ = await Converter.convert(source, to: .png)
    let out = try ReadBack(dir.appendingPathComponent("doc.png"))
    let top = out.pixel(75, 50), bottom = out.pixel(75, 250)
    #expect(top[0] > 245 && top[1] < 10, "top \(top)")
    #expect(bottom[0] > 245 && bottom[1] > 245, "bottom \(bottom)")
}

@Test func singlePagePDFHasNoPageSuffix() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    #expect(names(await Converter.convert(try writePDF(in: dir), to: .jpeg)) == ["doc.jpg"])
}

@Test func pageNumbersArePaddedToThePageCount() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let got = names(await Converter.convert(try writePDF(in: dir, pages: 12), to: .png))
    #expect(got == (1...12).map { String(format: "doc page %02d.png", $0) })
}

@Test func takenPageNameKeepsBoth() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let existing = dir.appendingPathComponent("doc page 1.png")
    try Data("old".utf8).write(to: existing)
    #expect(names(await Converter.convert(try writePDF(in: dir, pages: 2), to: .png)) == ["doc page 1 2.png", "doc page 2.png"])
    #expect(try Data(contentsOf: existing) == Data("old".utf8))
}

@Test func pagesPastOneHundredAreSkippedAndLogged() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let tag = "long\(UUID().uuidString.prefix(8))"
    let source = try writePDF(in: dir, name: tag, pages: 101, size: CGSize(width: 10, height: 10))
    let got = names(await Converter.convert(source, to: .png))
    #expect(got.count == 100 && got.first == "\(tag) page 001.png" && got.last == "\(tag) page 100.png")
    #expect(try files(in: dir).count == 101)
    #expect(try loggedLines(containing: "\(tag).pdf: 1 page skipped (max 100)").count == 1)
}

@Test func rotatedPageIsRenderedUpright() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let flat = try writePDF(in: dir, name: "flat")
    let doc = try #require(PDFDocument(url: flat))
    doc.page(at: 0)?.rotation = 90
    let source = dir.appendingPathComponent("turned.pdf")
    #expect(doc.write(to: source))
    _ = await Converter.convert(source, to: .png)
    let out = try ReadBack(dir.appendingPathComponent("turned.png"))
    #expect((out.width, out.height) == (300, 150))
}

// MARK: PDF security and failures

private var userPassword: [CFString: Any] { [kCGPDFContextUserPassword: "pw", kCGPDFContextOwnerPassword: "own"] }

@Test(arguments: [ImageFormat.png, .jpeg, .heic, .webp, .tiff])
func lockedPDFIsSkipped(target: ImageFormat) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir, pages: 2, options: userPassword)
    #expect(await Converter.convert(source, to: target) == .skipped(source: source, .locked))
    #expect(try files(in: dir) == ["doc.pdf"])
}

@Test func ownerPasswordOnlyPDFConverts() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir, options: [kCGPDFContextOwnerPassword: "own", kCGPDFContextAllowsCopying: false])
    #expect(names(await Converter.convert(source, to: .png)) == ["doc.png"])
}

@Test func brokenPDFFails() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = dir.appendingPathComponent("broken.pdf")
    try Data("%PDF-1.4 not really".utf8).write(to: source)
    #expect(await Converter.convert(source, to: .png) == .failed(source: source, reason: "couldn't read PDF"))
    #expect(try files(in: dir) == ["broken.pdf"])
}

@Test func unreadablePDFIsSkippedAsUnreadable() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writePDF(in: dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
    #expect(await Converter.convert(source, to: .png) == .skipped(source: source, .unreadable))
}

// Page 2 is too wide for WebP; page 1 is already on disk and must be named for the log.
@Test func failureAfterSomePagesNamesThemInTheDetail() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let url = dir.appendingPathComponent("doc.pdf")
    let ctx = try #require(CGContext(url as CFURL, mediaBox: nil, nil))
    for size in [CGSize(width: 72, height: 144), CGSize(width: 7900, height: 10)] {
        var box = CGRect(origin: .zero, size: size)
        ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
        ctx.endPDFPage()
    }
    ctx.closePDF()

    let outcome = await Converter.convert(url, to: .webp)
    guard case .failed(url, let reason, let detail) = outcome else { Issue.record("got \(outcome)"); return }
    #expect(reason == "too large for WebP (max 16383 px)")
    #expect(detail?.contains("doc page 1.webp") == true, "detail: \(detail ?? "nil")")
    #expect(try files(in: dir) == ["doc.pdf", "doc page 1.webp"])
}

@Test func batchMixesPDFsAndImages() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let pdf = try writePDF(in: dir, pages: 2), png = try write(.png, in: dir)
    let outcomes = await Converter.convertBatch([pdf, png], to: .jpeg)
    #expect(outcomes.map(names) == [["doc page 1.jpg", "doc page 2.jpg"], ["photo.jpg"]])
}
