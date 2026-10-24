import CoreGraphics
import Foundation

/// Pure wheel geometry, kept free of AppKit so it can be unit-tested.
public enum Geometry {
    public static let sliceNames = ["PNG", "JPEG", "HEIC", "WebP", "TIFF", "PDF"]

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
