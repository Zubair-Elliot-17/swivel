import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import libwebp
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

@Test(arguments: ["folder", "notes.txt", "missing.png"])
func nonImagesAreSkipped(name: String) async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = dir.appendingPathComponent(name)
    if name == "folder" { try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false) }
    if name == "notes.txt" { try Data("hello".utf8).write(to: source) }
    let before = try files(in: dir)
    #expect(await Converter.convert(source, to: .jpeg) == .skipped(source: source, .notImage))
    #expect(try files(in: dir) == before)
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
