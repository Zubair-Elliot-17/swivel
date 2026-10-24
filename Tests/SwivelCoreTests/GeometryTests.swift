import CoreGraphics
import Foundation
import Testing
import SwivelCore

private let center = CGPoint(x: 500, y: 300)

/// A point at `degrees` clockwise from 12 o'clock, in AppKit (y-up) coordinates.
private func point(_ degrees: Double, radius: Double = 70) -> CGPoint {
    let rad = degrees * .pi / 180
    return CGPoint(x: center.x + radius * sin(rad), y: center.y + radius * cos(rad))
}

private func slice(_ p: CGPoint) -> Int? {
    Geometry.slice(at: p, center: center, inner: 30, outer: 110, count: 6)
}

@Test func wheelHasSixSlices() {
    #expect(Geometry.sliceNames == ["PNG", "JPEG", "HEIC", "WebP", "TIFF", "PDF"])
}

@Test(arguments: [(0.0, 0), (60, 1), (120, 2), (180, 3), (240, 4), (300, 5)])
func sliceCentres(degrees: Double, expected: Int) {
    #expect(slice(point(degrees)) == expected)
}

@Test(arguments: [(359.0, 0), (1, 0), (329, 5), (331, 0), (29, 0)])
func wrapAroundTop(degrees: Double, expected: Int) {
    #expect(slice(point(degrees)) == expected)
}

// Only 90° and 270° are exactly representable boundary points; they pin the tie rule.
@Test func exactBoundaryGoesToClockwiseSlice() {
    #expect(slice(CGPoint(x: center.x + 70, y: center.y)) == 2)
    #expect(slice(CGPoint(x: center.x - 70, y: center.y)) == 5)
}

// sin/cos round-off moves an exact 30° point off the line, so test each side of every boundary.
@Test(arguments: [(30.0, 0, 1), (90, 1, 2), (150, 2, 3), (210, 3, 4), (270, 4, 5), (330, 5, 0)])
func everyBoundarySplitsNeighbours(degrees: Double, before: Int, after: Int) {
    #expect(slice(point(degrees - 1e-6)) == before)
    #expect(slice(point(degrees + 1e-6)) == after)
}

@Test(arguments: [0.0, 10, 29.9])
func deadZoneIsNil(radius: Double) {
    #expect(slice(point(45, radius: radius)) == nil)
}

@Test(arguments: [110.1, 200])
func outsideRingIsNil(radius: Double) {
    #expect(slice(point(45, radius: radius)) == nil)
}

@Test(arguments: [30.0, 110])
func ringEdgesAreInside(radius: Double) {
    #expect(slice(point(60, radius: radius)) == 1)
}

private let panel = CGSize(width: 240, height: 240)

@Test func unclampedFrameIsCentredOnCursor() {
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    #expect(Geometry.clampedFrame(size: panel, center: CGPoint(x: 500, y: 400), visible: visible)
        == CGRect(x: 380, y: 280, width: 240, height: 240))
}

// Second screen to the lower left: negative origin.
@Test(arguments: [
    (CGRect(x: 0, y: 25, width: 1440, height: 875), CGPoint(x: 10, y: 400), CGRect(x: 0, y: 280, width: 240, height: 240)),
    (CGRect(x: 0, y: 25, width: 1440, height: 875), CGPoint(x: 1435, y: 400), CGRect(x: 1200, y: 280, width: 240, height: 240)),
    (CGRect(x: 0, y: 25, width: 1440, height: 875), CGPoint(x: 700, y: 30), CGRect(x: 580, y: 25, width: 240, height: 240)),
    (CGRect(x: 0, y: 25, width: 1440, height: 875), CGPoint(x: 700, y: 899), CGRect(x: 580, y: 660, width: 240, height: 240)),
    (CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGPoint(x: -1915, y: -195), CGRect(x: -1920, y: -200, width: 240, height: 240)),
    (CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGPoint(x: -3, y: 875), CGRect(x: -240, y: 640, width: 240, height: 240)),
    (CGRect(x: 1440, y: 0, width: 1920, height: 1055), CGPoint(x: 1450, y: 1050), CGRect(x: 1440, y: 815, width: 240, height: 240)),
])
func clampedFrameStaysInsideVisible(visible: CGRect, cursor: CGPoint, expected: CGRect) {
    let frame = Geometry.clampedFrame(size: panel, center: cursor, visible: visible)
    #expect(frame == expected)
    #expect(visible.contains(frame))
}
