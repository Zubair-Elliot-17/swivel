import Accelerate
import Foundation
import ImageIO
import UniformTypeIdentifiers
import libwebp

struct ConvertError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Converts dropped files off the main actor; outputs go next to the source and never overwrite.
public enum Converter {
    /// Never throws: skips and errors come back as an `Outcome`.
    public static func convert(_ source: URL, to target: ImageFormat) async -> Outcome {
        let src = CGImageSourceCreateWithURL(source as CFURL, nil)
        let type = src.flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
        let count = src.map(CGImageSourceGetCount) ?? 0
        if let reason = skipReason(sourceType: type, imageCount: count, target: target) {
            // A file that exists but won't open (no read permission) isn't "not an image"; folders stay .notImage.
            var isDir: ObjCBool = false
            let unreadable = reason == .notImage && FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir)
                && !isDir.boolValue && !FileManager.default.isReadableFile(atPath: source.path)
            return .skipped(source: source, unreadable ? .unreadable : reason)
        }
        do {
            let data = try encode(src!, to: target)
            return .converted(source: source, output: try claim(data, source: source, ext: target.fileExtension))
        } catch {
            return .failed(source: source, reason: error.localizedDescription)
        }
    }

    /// Converts `urls` with at most `maxInFlight` decodes at once (each holds a full bitmap); keeps input order.
    public static func convertBatch(_ urls: [URL], to target: ImageFormat, maxInFlight: Int = 4) async -> [Outcome] {
        await withTaskGroup(of: (Int, Outcome).self) { group in
            var results = [Outcome?](repeating: nil, count: urls.count)
            var next = 0
            // Sliding window: seed the cap, then start one more as each finishes.
            while next < min(max(maxInFlight, 1), urls.count) {
                let i = next
                group.addTask { (i, await convert(urls[i], to: target)) }
                next += 1
            }
            while let (i, outcome) = await group.next() {
                results[i] = outcome
                if next < urls.count {
                    let j = next
                    group.addTask { (j, await convert(urls[j], to: target)) }
                    next += 1
                }
            }
            return results.map { $0! }
        }
    }

    /// Encodes the primary image in memory, so a name is claimed only once the bytes exist.
    static func encode(_ src: CGImageSource, to target: ImageFormat) throws -> Data {
        let props = CGImageSourceCopyPropertiesAtIndex(src, CGImageSourceGetPrimaryImageIndex(src), nil) as? [CFString: Any]
        guard let width = props?[kCGImagePropertyPixelWidth] as? Int, let height = props?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { throw ConvertError("couldn't read image") }
        // 200 MP is ~800 MB as RGBA; with 4 in flight that stays a few GB, and it stops small-file bombs.
        guard width * height <= 200_000_000 else { throw ConvertError("too large (max 200 MP)") }
        if target == .webp { return try encodeWebP(src, side: max(width, height)) }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, target.utType.identifier as CFString, 1, nil)
        else { throw ConvertError("can't write \(target.rawValue)") }
        // AddImageFromSource keeps EXIF, orientation and ICC; alpha to JPEG flattens on white.
        let options: [CFString: Any] = target == .jpeg || target == .heic ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]
        CGImageDestinationAddImageFromSource(dest, src, CGImageSourceGetPrimaryImageIndex(src), options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError("couldn't encode \(target.rawValue)") }
        return data as Data
    }

    /// ImageIO can't write WebP: bake orientation into upright straight-alpha sRGB pixels, then libwebp lossy q75.
    static func encodeWebP(_ src: CGImageSource, side: Int) throws -> Data {
        let index = CGImageSourceGetPrimaryImageIndex(src)
        guard side <= Int(WEBP_MAX_DIMENSION) else { throw ConvertError("too large for WebP (max \(WEBP_MAX_DIMENSION) px)") }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, index, options as CFDictionary),
              let format = vImage_CGImageFormat(
                  bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue))
        else { throw ConvertError("couldn't read image") }
        let buffer = try vImage_Buffer(cgImage: image, format: format)
        defer { buffer.free() }
        var output: UnsafeMutablePointer<UInt8>?
        defer { WebPFree(output) }
        let size = WebPEncodeRGBA(
            buffer.data.assumingMemoryBound(to: UInt8.self), Int32(buffer.width), Int32(buffer.height),
            Int32(buffer.rowBytes), 75, &output)
        guard size > 0, let output else { throw ConvertError("couldn't encode WebP") }
        return Data(bytes: output, count: size)
    }

    /// Writes `data` to the first free "Keep Both" name; `.withoutOverwriting` makes the claim atomic.
    static func claim(_ data: Data, source: URL, ext: String) throws -> URL {
        for attempt in 1...9999 {
            let url = OutputName.candidate(for: source, ext: ext, attempt: attempt)
            do {
                // shortcut: disk-full may leave partial output, use temp+renamex_np(RENAME_EXCL) if seen
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw ConvertError("no free file name")
    }
}
