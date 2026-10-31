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

/// Image (7), video (6) and audio (2) wheels.
private let counts = [7, 6, 2]

private func slice(_ p: CGPoint, count: Int = 7) -> Int? {
    Geometry.slice(at: p, center: center, inner: 30, outer: 110, count: count)
}

@Test func wheelHasSevenSlices() {
    #expect(Geometry.sliceNames == ["PNG", "JPEG", "HEIC", "WebP", "TIFF", "PDF", "Text"])
}

@Test(arguments: counts)
func sliceCentres(count: Int) {
    let width = 360 / Double(count)
    for index in 0..<count { #expect(slice(point(Double(index) * width), count: count) == index) }
}

@Test(arguments: counts)
func wrapAroundTop(count: Int) {
    let width = 360 / Double(count)
    let cases: [(Double, Int)] = [
        (359, 0), (1, 0), (360 - width / 2 - 1, count - 1), (360 - width / 2 + 1, 0), (width / 2 - 1, 0),
    ]
    for (degrees, expected) in cases { #expect(slice(point(degrees), count: count) == expected) }
}

// With 2 slices, 90° and 270° are exactly representable boundaries; they pin the tie rule.
@Test func exactBoundaryGoesToClockwiseSlice() {
    #expect(slice(CGPoint(x: center.x + 70, y: center.y), count: 2) == 1)
    #expect(slice(CGPoint(x: center.x - 70, y: center.y), count: 2) == 0)
}

// sin/cos round-off moves an exact boundary point off the line, so test each side of every boundary.
@Test(arguments: counts)
func everyBoundarySplitsNeighbours(count: Int) {
    let width = 360 / Double(count)
    for before in 0..<count {
        let degrees = (Double(before) + 0.5) * width
        #expect(slice(point(degrees - 1e-6), count: count) == before)
        #expect(slice(point(degrees + 1e-6), count: count) == (before + 1) % count)
    }
}

// MARK: Slice sets (extension only: these paths don't exist)

private func f(_ name: String) -> URL { URL(fileURLWithPath: "/nonexistent/swivel/\(name)") }

@Test(arguments: [[], ["a.png"], ["doc.pdf"], ["folder"], ["notes.txt"], ["a.png", "clip.mov"], ["x.unknownext"]])
func imageSetForNonAVDrops(names: [String]) {
    #expect(Geometry.slices(for: names.map(f)) == Geometry.sliceNames)
}

@Test(arguments: ["clip.mov", "clip.mp4", "clip.m4v", "clip.mkv", "clip.avi", "CLIP.MOV"])
func videoSetForMovies(name: String) {
    #expect(Geometry.slices(for: [f(name)]) == ["MP4", "HEVC", "MOV", "GIF", "M4A", "WAV"])
}

@Test(arguments: ["a.m4a", "a.wav", "a.mp3", "a.aiff", "a.flac"])
func audioSetForAudio(name: String) {
    #expect(Geometry.slices(for: [f(name)]) == ["M4A", "WAV"])
}

@Test func mixedDropTakesTheFirstFilesSet() {
    #expect(Geometry.slices(for: [f("clip.mov"), f("a.png")]) == Geometry.videoSlices)
    #expect(Geometry.slices(for: [f("a.m4a"), f("clip.mov")]) == Geometry.audioSlices)
}

@Test func voiceOverLabelsPerSet() {
    #expect(Geometry.videoSlices.map { Geometry.label(for: $0, in: Geometry.videoSlices) } == [
        "Convert to MP4", "Convert to HEVC", "Convert to MOV", "Make GIF", "Extract audio as M4A", "Extract audio as WAV",
    ])
    #expect(Geometry.audioSlices.map { Geometry.label(for: $0, in: Geometry.audioSlices) } == ["Convert to M4A", "Convert to WAV"])
    #expect(Geometry.sliceNames.map { Geometry.label(for: $0, in: Geometry.sliceNames) } == [
        "Convert to PNG", "Convert to JPEG", "Convert to HEIC", "Convert to WebP", "Convert to TIFF", "Convert to PDF", "Extract text",
    ])
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
    // Straight up is exact; a sin/cos point can round just inside the dead zone.
    #expect(slice(CGPoint(x: center.x, y: center.y + radius)) == 0)
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
