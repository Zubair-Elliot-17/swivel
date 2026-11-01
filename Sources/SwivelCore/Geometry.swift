import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// What a drop is, which picks the wheel; each kind has its own stored layout.
public enum FileKind: String, CaseIterable, Sendable {
    case image, video, audio

    /// UserDefaults key holding the ordered visible slice names.
    public var key: String { "wheel.\(rawValue)" }

    /// Every slice this kind can show, in default order.
    public var known: [String] {
        switch self {
        case .image: Geometry.sliceNames
        case .video: Geometry.videoSlices
        case .audio: Geometry.audioSlices
        }
    }
}

/// Pure wheel geometry, kept free of AppKit so it can be unit-tested.
public enum Geometry {
    public static let sliceNames = ["PNG", "JPEG", "HEIC", "WebP", "TIFF", "PDF", "Text"]
    public static let videoSlices = AVTarget.allCases.map(\.rawValue)
    public static let audioSlices = [AVTarget.m4a.rawValue, AVTarget.wav.rawValue]

    /// The kind of a drop: the first file's, from its extension only (no file reads on the drag path).
    public static func kind(for urls: [URL]) -> FileKind {
        guard let ext = urls.first?.pathExtension, !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .image
    }

    /// A stored layout cleaned against `known`: known names only, first of each, order kept; junk or empty gives `known`.
    public static func clean(_ raw: Any?, known: [String]) -> [String] {
        var seen = Set<String>()
        let names = (raw as? [String] ?? []).filter { known.contains($0) && seen.insert($0).inserted }
        return names.isEmpty ? known : names
    }

    /// The user's visible slices for `kind`, in their order.
    public static func slices(for kind: FileKind, defaults: UserDefaults) -> [String] {
        clean(defaults.object(forKey: kind.key), known: kind.known)
    }

    /// VoiceOver label for slice `name` on a `kind` wheel.
    public static func label(for name: String, kind: FileKind) -> String {
        switch name {
        case "Text": "Extract text"
        case "GIF": "Make GIF"
        case "M4A" where kind == .video, "WAV" where kind == .video: "Extract audio as \(name)"
        default: "Convert to \(name)"
        }
    }

    /// Slice under `point`, or nil in the dead zone (`r < inner`) or outside the ring (`r > outer`).
    /// Angles run clockwise from 12 o'clock (y up); slice 0 is centred on the top.
    public static func slice(at point: CGPoint, center: CGPoint, inner: CGFloat, outer: CGFloat, count: Int) -> Int? {
        let dx = point.x - center.x, dy = point.y - center.y
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= inner, r <= outer, count > 0 else { return nil }
        let width = 360 / Double(count)
        let degrees = atan2(Double(dx), Double(dy)) * 180 / .pi
        // Offset by half a slice so slice 0 straddles 0°, then wrap into [0, 360).
        let shifted = (degrees + width / 2).truncatingRemainder(dividingBy: 360)
        let positive = shifted < 0 ? shifted + 360 : shifted
        return Int(positive / width) % count
    }

    /// A `size` frame centred on `center`, shifted to stay inside `visible` (bottom-left origin).
    public static func clampedFrame(size: CGSize, center: CGPoint, visible: CGRect) -> CGRect {
        let x = min(max(center.x - size.width / 2, visible.minX), visible.maxX - size.width)
        let y = min(max(center.y - size.height / 2, visible.minY), visible.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
