// Draws the Swivel app icon (an original wheel mark) and builds assets/AppIcon.icns.
// Run from the repo root: swift scripts/icon.swift
import AppKit

/// One icon at `px` pixels: a rounded-square body on Apple's 1024 grid (824 body, 100 inset) holding a six-slice wheel.
func draw(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.55, blue: 0.20, alpha: 1),
               ending: NSColor(srgbRed: 0.86, green: 0.24, blue: 0.30, alpha: 1))!.draw(in: body, angle: -90)

    let c = NSPoint(x: 512 * s, y: 512 * s), outer = 300 * s, inner = 120 * s
    for i in 0..<6 {
        // Slices with gaps; the top one is lit, like a highlighted format.
        let start = 90 - CGFloat(i) * 60 + 26, end = start - 52
        let wedge = NSBezierPath()
        wedge.appendArc(withCenter: c, radius: outer, startAngle: start, endAngle: end, clockwise: true)
        wedge.appendArc(withCenter: c, radius: inner, startAngle: end, endAngle: start, clockwise: false)
        wedge.close()
        NSColor.white.withAlphaComponent(i == 0 ? 1 : 0.55).setFill()
        wedge.fill()
    }
    // The swivel: an arrow arc around the hub.
    let arc = NSBezierPath()
    arc.appendArc(withCenter: c, radius: 70 * s, startAngle: 120, endAngle: -150, clockwise: true)
    arc.lineWidth = 22 * s
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()
    let tip = NSPoint(x: c.x + 70 * s * cos(-150 * .pi / 180), y: c.y + 70 * s * sin(-150 * .pi / 180))
    let head = NSBezierPath()
    head.move(to: NSPoint(x: tip.x - 34 * s, y: tip.y + 6 * s))
    head.line(to: NSPoint(x: tip.x + 14 * s, y: tip.y + 40 * s))
    head.line(to: NSPoint(x: tip.x + 10 * s, y: tip.y - 30 * s))
    head.close()
    NSColor.white.setFill()
    head.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try draw(px: size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(px: size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", "assets/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: set)
guard iconutil.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
print("Wrote assets/AppIcon.icns")
