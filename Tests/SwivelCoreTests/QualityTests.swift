import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SwivelCore

// MARK: Reading the setting (UserDefaults is untrusted: every value is clamped or falls back)

private func stored(_ value: Any?) -> Double {
    let name = "swivel.tests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    if let value { suite.set(value, forKey: "quality") }
    return Converter.quality(suite.object(forKey: "quality"))
}

@Test func absentQualityIsTheDefault() {
    #expect(stored(nil) == 0.85)
    #expect(Converter.quality(nil) == 0.85)
}

@Test func nonNumberQualityIsTheDefault() {
    #expect(Converter.quality(Double.nan) == 0.85)
    for value: Any in ["abc", "0.3", [0.5], Data([1])] { #expect(stored(value) == 0.85, "\(value)") }
}

@Test func lowQualityClampsToHalf() {
    for value: Any in [-1.0, 0, -Double.infinity] { #expect(stored(value) == 0.5, "\(value)") }
}

@Test func highQualityClampsToOne() {
    for value: Any in [Double.infinity, 5.0, 1e20] { #expect(stored(value) == 1.0, "\(value)") }
}

@Test func numberQualityIsUsed() {
    #expect(stored(0.7) == 0.7)
    #expect(stored(1) == 1.0)
    #expect(stored(true) == 1.0)
}

// MARK: Quality reaches the encoder

/// A 256 px PNG whose JPEG/HEIC size follows quality clearly.
private func noisy(in dir: URL) throws -> URL {
    let side = 256
    var seed: UInt32 = 12345
    var bytes = [UInt8](repeating: 255, count: side * side * 4)
    // Gradient plus light noise: photo-like, so every encoder's size follows quality.
    for i in bytes.indices where i % 4 != 3 {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        let pixel = i / 4, x = pixel % side, y = pixel / side
        bytes[i] = UInt8(truncatingIfNeeded: (x + y) / 2 + Int(seed >> 28))
    }
    let image = try #require(bytes.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
    })
    let url = dir.appendingPathComponent("noise.png")
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    #expect(CGImageDestinationFinalize(dest))
    return url
}

/// Output bytes of converting a fresh copy of `make`'s source to `target` at `quality` (nil = the default argument).
private func output(_ target: ImageFormat, quality: Double?, make: (URL) throws -> URL = noisy) async throws -> Data {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    let source = try make(dir)
    let outcomes = if let quality { await Converter.convertBatch([source], to: target, quality: quality) }
        else { await Converter.convertBatch([source], to: target) }
    guard case .converted(_, let outputs, _) = outcomes.first, let url = outputs.first else {
        Issue.record("not converted: \(outcomes)"); return Data()
    }
    return try Data(contentsOf: url)
}

@Test(arguments: [ImageFormat.jpeg, .heic])
func lossySizeFollowsQuality(target: ImageFormat) async throws {
    let low = try await output(target, quality: 0.5).count
    let standard = try await output(target, quality: nil).count
    let high = try await output(target, quality: 1.0).count
    #expect(low < standard && standard < high, "\(low) \(standard) \(high)")
    // HEIC bytes vary run to run (hardware or software encoder), so only JPEG pins the default to exactly 0.85.
    if target == .jpeg { #expect(try await output(target, quality: 0.85).count == standard) }
}

// Amendment: HEIC at 1.0 fails while AV encodes run, so HEIC caps at 0.99; JPEG keeps 1.0.
@Test func heicQualityCapsAtNinetyNine() {
    let setting = { (target: ImageFormat, q: Double) in
        Converter.imageIOOptions(target, quality: q)[kCGImageDestinationLossyCompressionQuality] as? Double
    }
    #expect(setting(.heic, 1.0) == 0.99)
    #expect(setting(.heic, 0.99) == 0.99)
    #expect(setting(.heic, 0.85) == 0.85)
    #expect(setting(.jpeg, 1.0) == 1.0)
}

@Test(arguments: [ImageFormat.png, .tiff, .webp])
func losslessAndWebPIgnoreQuality(target: ImageFormat) async throws {
    let jpeg: (URL) throws -> URL = { try write(.jpeg, in: $0) }
    #expect(try await output(target, quality: 0.5, make: jpeg) == output(target, quality: 1.0, make: jpeg))
}

/// A one-page PDF showing the noise image, 256 pt square.
private func noisyPDF(in dir: URL) throws -> URL {
    let src = try #require(CGImageSourceCreateWithURL(try noisy(in: dir) as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    return try writePDF(in: dir, size: CGSize(width: 256, height: 256)) { ctx, _ in
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
    }
}

@Test func pdfPageSizeFollowsQuality() async throws {
    let low = try await output(.jpeg, quality: 0.5, make: noisyPDF).count
    let standard = try await output(.jpeg, quality: 0.85, make: noisyPDF).count
    #expect(low < standard, "\(low) \(standard)")
}

// D4: a combined PDF embeds lossy frames at the fixed 0.85, whatever the setting.
@Test func combinedPDFEmbedsFramesAtFixedQuality() async throws {
    let dir = try makeScratch()
    defer { cleanUp(dir) }
    guard case .converted(_, let made, _) = await Converter.convert(try noisy(in: dir), to: .heic, quality: 0.5),
          let heic = made.first else { Issue.record("fixture failed"); return }
    _ = await Converter.makePDF([heic])
    let pdf = try Data(contentsOf: dir.appendingPathComponent("noise.pdf"))
    let src = try #require(CGImageSourceCreateWithURL(heic as CFURL, nil))
    let frame = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    #expect(pdf.range(of: try Converter.encode(frame, to: .jpeg, quality: Converter.defaultQuality)) != nil)
    #expect(pdf.range(of: try Converter.encode(frame, to: .jpeg, quality: 0.5)) == nil)
}
