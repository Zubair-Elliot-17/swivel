import Foundation
import ImageIO
import UniformTypeIdentifiers

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
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, target.utType.identifier as CFString, 1, nil)
        else { throw ConvertError("can't write \(target.rawValue)") }
        // AddImageFromSource keeps EXIF, orientation and ICC; alpha to JPEG flattens on white.
        let options: [CFString: Any] = target == .jpeg || target == .heic ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]
        CGImageDestinationAddImageFromSource(dest, src, CGImageSourceGetPrimaryImageIndex(src), options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError("couldn't encode \(target.rawValue)") }
        return data as Data
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
