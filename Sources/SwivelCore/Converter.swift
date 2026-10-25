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
            return .skipped(source: source, reason)
        }
        do {
            let data = try encode(src!, to: target)
            return .converted(source: source, output: try claim(data, source: source, ext: target.fileExtension))
        } catch {
            return .failed(source: source, reason: error.localizedDescription)
        }
    }

    /// Encodes the primary image in memory, so a name is claimed only once the bytes exist.
    static func encode(_ src: CGImageSource, to target: ImageFormat) throws -> Data {
        if target == .webp { return try encodeWebP(src) }
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
    static func encodeWebP(_ src: CGImageSource) throws -> Data {
        let index = CGImageSourceGetPrimaryImageIndex(src)
        let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
        let side = max(props?[kCGImagePropertyPixelWidth] as? Int ?? 0, props?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        guard side <= Int(WEBP_MAX_DIMENSION) else { throw ConvertError("too large for WebP (max \(WEBP_MAX_DIMENSION) px)") }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard side > 0, let image = CGImageSourceCreateThumbnailAtIndex(src, index, options as CFDictionary),
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
