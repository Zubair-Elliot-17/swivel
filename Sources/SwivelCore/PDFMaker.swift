import CoreGraphics

/// Page size and CTM that draw a `width` x `height` image (in `(0,0,w,h)`) upright for EXIF `orientation` 1-8.
/// Rotating the drawing, not the pixels, keeps JPEG bytes passed through.
public func orientedPage(orientation: Int, width: Int, height: Int) -> (size: CGSize, transform: CGAffineTransform) {
    let w = CGFloat(width), h = CGFloat(height)
    let upright = CGSize(width: w, height: h), turned = CGSize(width: h, height: w)
    switch orientation {
    case 2: return (upright, CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
    case 3: return (upright, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
    case 4: return (upright, CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h))
    case 5: return (turned, CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w))
    case 6: return (turned, CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
    case 7: return (turned, CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
    case 8: return (turned, CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
    default: return (upright, .identity)
    }
}
