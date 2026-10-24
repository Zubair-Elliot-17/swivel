import AppKit
import SwivelCore

private let wheelSize = CGSize(width: 240, height: 240)
private let innerRadius: CGFloat = 30
private let outerRadius: CGFloat = 110

/// Borderless, non-activating panel that shows the wheel under the cursor without stealing focus.
@MainActor
final class WheelPanel {
    private let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: wheelSize),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let view = WheelView(frame: NSRect(origin: .zero, size: wheelSize))
    private var pendingHide: Timer?

    init(onDrop: @escaping (String, [URL]) -> Void) {
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = view
        view.onDrop = { [weak self] name, urls in
            onDrop(name, urls)
            self?.hide()
        }
    }

    func show(at point: NSPoint) {
        pendingHide?.invalidate()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        panel.setFrame(Geometry.clampedFrame(size: wheelSize, center: point, visible: screen.visibleFrame), display: true)
        panel.orderFrontRegardless()
    }

    /// Called when the mouse button is up. A drop over a slice may still be on its way,
    /// so give performDragOperation a moment before hiding.
    func dragEnded() {
        guard view.highlight != nil else { return hide() }
        pendingHide = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        pendingHide?.invalidate()
        pendingHide = nil
        view.highlight = nil
        panel.orderOut(nil)
    }
}

/// Drop target that maps the drag location to a slice and accepts a copy only on a slice (D4).
final class WheelView: NSView {
    var onDrop: ((String, [URL]) -> Void)?
    var highlight: Int? {
        didSet { if highlight != oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("Swivel format wheel")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func slice(for sender: NSDraggingInfo) -> Int? {
        Geometry.slice(
            at: convert(sender.draggingLocation, from: nil), center: CGPoint(x: bounds.midX, y: bounds.midY),
            inner: innerRadius, outer: outerRadius, count: Geometry.sliceNames.count)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlight = slice(for: sender)
        return highlight != nil && sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        highlight = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let index = slice(for: sender),
              let urls = sender.draggingPasteboard.readObjects(
                  forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty
        else { return false }
        // Finder can hand over /.file/id= reference URLs; resolve them to real paths.
        onDrop?(Geometry.sliceNames[index], urls.map { ($0 as NSURL).filePathURL ?? $0 })
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let count = Geometry.sliceNames.count
        let width = 360 / CGFloat(count)
        for (i, name) in Geometry.sliceNames.enumerated() {
            // Slice angles run clockwise from 12 o'clock; AppKit arcs run counter-clockwise from 3 o'clock.
            let start = 90 - (CGFloat(i) * width - width / 2), end = start - width
            let wedge = NSBezierPath()
            wedge.appendArc(withCenter: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: true)
            wedge.appendArc(withCenter: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: false)
            wedge.close()
            (i == highlight ? NSColor.controlAccentColor : NSColor.windowBackgroundColor.withAlphaComponent(0.92)).setFill()
            wedge.fill()
            NSColor.separatorColor.setStroke()
            wedge.stroke()

            let mid = (CGFloat(i) * width) * .pi / 180, labelRadius = (innerRadius + outerRadius) / 2
            let color: NSColor = i == highlight ? .alternateSelectedControlTextColor : .labelColor
            let label = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color,
            ])
            let size = label.size()
            label.draw(at: CGPoint(
                x: center.x + labelRadius * sin(mid) - size.width / 2,
                y: center.y + labelRadius * cos(mid) - size.height / 2))
        }
    }
}
