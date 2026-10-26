import Foundation
import UniformTypeIdentifiers

/// Image targets on the wheel; raw values are the slice names, so "PDF" maps to nil.
public enum ImageFormat: String, CaseIterable, Sendable {
    case png = "PNG", jpeg = "JPEG", heic = "HEIC", webp = "WebP", tiff = "TIFF"

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .webp: "webp"
        case .tiff: "tiff"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .webp: .webP
        case .tiff: .tiff
        }
    }
}

/// Finder "Keep Both" naming: attempt 1 is `<stem>.<ext>`, attempt n is `<stem> n.<ext>`, next to the source.
public enum OutputName {
    public static func candidate(for source: URL, ext: String, attempt: Int) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        let name = attempt == 1 ? "\(stem).\(ext)" : "\(stem) \(attempt).\(ext)"
        return source.deletingLastPathComponent().appendingPathComponent(name)
    }
}

public enum SkipReason: Equatable, Sendable, CustomStringConvertible {
    case notImage
    case unreadable
    case already(ImageFormat)

    public var description: String {
        switch self {
        case .notImage: "not an image"
        case .unreadable: "can't read"
        case .already(let format): "already \(format.rawValue)"
        }
    }
}

/// Why a source is skipped for `target`, or nil when it should be converted.
public func skipReason(sourceType: UTType?, imageCount: Int, target: ImageFormat) -> SkipReason? {
    guard let sourceType, sourceType.conforms(to: .image), imageCount > 0 else { return .notImage }
    return sourceType.conforms(to: target.utType) ? .already(target) : nil
}
