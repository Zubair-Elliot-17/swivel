import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import libwebp
import zlib
import SwivelCore

@Test func libwebpLinks() {
    #expect(WebPGetEncoderVersion() > 0)
}

// MARK: Fixtures

enum Fixture: String, CaseIterable, Sendable {
    /// 16x8 RGBA PNG: left half transparent, right half opaque green.
    case png
    /// 40x20 JPEG tagged orientation 6: left half red, right half blue (displays 20x40, red on top).
    case jpeg

    var format: ImageFormat { self == .png ? .png : .jpeg }
}

private func makeScratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swivel-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func cleanUp(_ dir: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
    try? FileManager.default.removeItem(at: dir)
}

@discardableResult
func write(_ fixture: Fixture, in dir: URL, name: String = "photo") throws -> URL {
    let (w, h) = fixture == .png ? (16, 8) : (40, 20)
    let ctx = try #require(CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let left = CGRect(x: 0, y: 0, width: w / 2, height: h), right = CGRect(x: w / 2, y: 0, width: w / 2, height: h)
    if fixture == .png {
        ctx.clear(left)
        ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
    } else {
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(left)
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    }
    ctx.fill(right)
    let url = dir.appendingPathComponent("\(name).\(fixture.format.fileExtension)")
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, fixture.format.utType.identifier as CFString, 1, nil))
    let props: [CFString: Any] = fixture == .jpeg ? [kCGImagePropertyOrientation: 6] : [:]
    CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), props as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
    return url
}

struct ReadBack {
    let type: String, width: Int, height: Int, orientation: Int?
    let image: CGImage

    init(_ url: URL) throws {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        type = try #require(CGImageSourceGetType(src)) as String
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        orientation = props[kCGImagePropertyOrientation] as? Int
        image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// RGBA at (x, y) with y counted from the top, read through an sRGB context.
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let i = (y * width + x) * 4
        return Array(buf[i..<i + 4])
    }
}

private func files(in dir: URL) throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
}

// MARK: ImageIO path

private let imageIOTargets: [ImageFormat] = [.png, .jpeg, .heic, .tiff]

@Test(arguments: Fixture.allCases, imageIOTargets)
func imageIOConvertsToEachOtherFormat(fixture: Fixture, target: ImageFormat) async throws {
    guard fixture.format != target else { return }
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(fixture, in: dir)

    let outcome = await Converter.convert(source, to: target)
    let expected = dir.appendingPathComponent("photo.\(target.fileExtension)")
    #expect(outcome == .converted(source: source, output: expected))

    let out = try ReadBack(expected)
    #expect(out.type == target.utType.identifier)
    #expect((out.width, out.height) == (fixture == .png ? (16, 8) : (40, 20)))
    if fixture == .jpeg && target != .jpeg {
        #expect(out.orientation == 6)
    }
}

@Test func transparentPixelBecomesWhiteInJPEG() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir)
    _ = await Converter.convert(source, to: .jpeg)
    let px = try ReadBack(dir.appendingPathComponent("photo.jpg")).pixel(2, 4)
    #expect(px[0] >= 245 && px[1] >= 245 && px[2] >= 245)
}

// MARK: Collisions, skips, failures

@Test func takenNameMovesToNextCandidateAndKeepsOriginal() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let existing = dir.appendingPathComponent("photo.jpg")
    let original = Data("not really a jpeg".utf8)
    try original.write(to: existing)
    let source = try write(.png, in: dir)

    let outcome = await Converter.convert(source, to: .jpeg)
    #expect(outcome == .converted(source: source, output: dir.appendingPathComponent("photo 2.jpg")))
    #expect(try Data(contentsOf: existing) == original)
}

@Test(arguments: Fixture.allCases)
func sameTypeIsSkippedAndWritesNothing(fixture: Fixture) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(fixture, in: dir)
    let before = try files(in: dir)
    #expect(await Converter.convert(source, to: fixture.format) == .skipped(source: source, .already(fixture.format)))
    #expect(try files(in: dir) == before)
}

@Test(arguments: ["folder", "locked folder", "notes.txt", "missing.png"])
func nonImagesAreSkipped(name: String) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = dir.appendingPathComponent(name)
    if name.hasSuffix("folder") { try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false) }
    if name == "locked folder" { try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path) }
    if name == "notes.txt" { try Data("hello".utf8).write(to: source) }
    let before = try files(in: dir)
    #expect(await Converter.convert(source, to: .jpeg) == .skipped(source: source, .notImage))
    #expect(try files(in: dir) == before)
}

@Test func unreadableImageIsSkippedAsUnreadable() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
    #expect(await Converter.convert(source, to: .jpeg) == .skipped(source: source, .unreadable))
    #expect(try files(in: dir) == ["photo.png"])
}

@Test func readOnlyFolderFailsWithReason() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(.png, in: dir)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

    let outcome = await Converter.convert(source, to: .jpeg)
    guard case .failed(let failed, let reason) = outcome else {
        Issue.record("expected failure, got \(outcome)")
        return
    }
    #expect(failed == source)
    #expect(!reason.isEmpty)
    #expect(try files(in: dir) == ["photo.png"])
}

// MARK: WebP path

@Test(arguments: Fixture.allCases)
func webPOutputIsWebP(fixture: Fixture) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try write(fixture, in: dir)
    let expected = dir.appendingPathComponent("photo.webp")
    #expect(await Converter.convert(source, to: .webp) == .converted(source: source, output: expected))
    #expect(try ReadBack(expected).type == "org.webmproject.webp")
}

@Test func webPBakesInOrientation() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    _ = await Converter.convert(try write(.jpeg, in: dir), to: .webp)
    let out = try ReadBack(dir.appendingPathComponent("photo.webp"))
    #expect((out.width, out.height) == (20, 40))
    let top = out.pixel(10, 5), bottom = out.pixel(10, 35)
    #expect(top[0] > 200 && top[2] < 60)
    #expect(bottom[2] > 200 && bottom[0] < 60)
}

@Test func webPKeepsAlpha() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    _ = await Converter.convert(try write(.png, in: dir), to: .webp)
    let out = try ReadBack(dir.appendingPathComponent("photo.webp"))
    #expect(out.pixel(2, 4)[3] <= 2)
    #expect(out.pixel(12, 4)[3] >= 253)
}

@Test func webPRejectsImagesOverItsSizeLimit() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let ctx = try #require(CGContext(
        data: nil, width: 16384, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let source = dir.appendingPathComponent("wide.png")
    let dest = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
    #expect(CGImageDestinationFinalize(dest))

    #expect(await Converter.convert(source, to: .webp) == .failed(source: source, reason: "too large for WebP (max 16383 px)"))
    #expect(try files(in: dir) == ["wide.png"])
}

/// A 1-bit grey PNG of side x side zero pixels, built by hand: a 225 MP bomb is ~27 KB on disk.
/// With `fakeBody` the IDAT is empty, so ImageIO can't report the dimensions.
private func writeFlatPNG(side: Int, in dir: URL, fakeBody: Bool = false) throws -> URL {
    func be(_ v: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) } }
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return be(body.count) + typed + be(Int(crc32(0, typed, uInt(typed.count))))
    }
    let raw = [UInt8](repeating: 0, count: side * (1 + (side + 7) / 8))  // filter byte + packed bits per row
    var packed = [UInt8](repeating: 0, count: Int(compressBound(uLong(raw.count))))
    var packedLen = uLongf(packed.count)
    #expect(compress2(&packed, &packedLen, raw, uLong(raw.count), Z_BEST_COMPRESSION) == Z_OK)
    let idat = fakeBody ? [0x78, 0x9C, 0x03, 0x00, 0, 0, 0, 1] : Array(packed[..<Int(packedLen)])
    let png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", be(side) + be(side) + [1, 0, 0, 0, 0])
        + chunk("IDAT", idat) + chunk("IEND", [])
    let url = dir.appendingPathComponent("flat.png")
    try Data(png).write(to: url)
    return url
}

@Test(arguments: [ImageFormat.jpeg, .webp])
func imagesOverThePixelCapFailBeforeDecoding(target: ImageFormat) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writeFlatPNG(side: 15000, in: dir)
    #expect(await Converter.convert(source, to: target) == .failed(source: source, reason: "too large (max 200 MP)"))
    #expect(try files(in: dir) == ["flat.png"])
}

@Test func imagesWithoutReadableDimensionsFail() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try writeFlatPNG(side: 1000, in: dir, fakeBody: true)
    #expect(await Converter.convert(source, to: .jpeg) == .failed(source: source, reason: "couldn't read image"))
    #expect(try files(in: dir) == ["flat.png"])
}

// MARK: Batch

@Test func batchSourcesSharingAStemNeverClobber() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let png = try write(.png, in: dir)
    // Build photo.heic and photo.tiff from the PNG, then occupy photo.jpg.
    var sources = [png]
    for format in [ImageFormat.heic, .tiff] {
        let url = dir.appendingPathComponent("photo.\(format.fileExtension)")
        #expect(await Converter.convert(png, to: format) == .converted(source: png, output: url))
        sources.append(url)
    }
    let existing = dir.appendingPathComponent("photo.jpg")
    let original = Data("keep me".utf8)
    try original.write(to: existing)

    let outcomes = await Converter.convertBatch(sources, to: .jpeg)
    let outputs = outcomes.compactMap { outcome -> String? in
        guard case .converted(_, let output) = outcome else { return nil }
        return output.lastPathComponent
    }
    #expect(outputs.count == 3)
    #expect(Set(outputs) == ["photo 2.jpg", "photo 3.jpg", "photo 4.jpg"])
    #expect(try Data(contentsOf: existing) == original)
}

@Test func batchReturnsOutcomesInInputOrder() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let sources = try (0..<10).map { try write(.png, in: dir, name: "p\($0)") }
    let outcomes = await Converter.convertBatch(sources, to: .jpeg)
    #expect(outcomes == sources.map { .converted(source: $0, output: $0.deletingPathExtension().appendingPathExtension("jpg")) })
}

@Test(arguments: [0, 1])
func emptyBatchOrTinyCapStillWorks(cap: Int) async throws {
    #expect(await Converter.convertBatch([], to: .png, maxInFlight: cap) == [])
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let sources = try (0..<3).map { try write(.png, in: dir, name: "p\($0)") }
    #expect(await Converter.convertBatch(sources, to: .tiff, maxInFlight: cap).count == 3)
}
