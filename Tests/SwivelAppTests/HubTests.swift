import AppKit
import Testing
@testable import Swivel

// Opaque-enough hub: a fully clear pixel lets WindowServer pass the drop to the window below.
@MainActor @Test func hubCentreIsNotFullyTransparent() {
    let v = WheelView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)!
    #expect(c.alphaComponent > 0)
}
