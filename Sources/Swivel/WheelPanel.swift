import AppKit
import SwivelCore

private let wheelSize = CGSize(width: 240, height: 240)
private let innerRadius: CGFloat = 30
private let outerRadius: CGFloat = 110

/// Borderless, non-activating panel that shows the wheel under the cursor without stealing focus.
/// Drag mode takes a drop; click mode (Finder tap) takes a click and never makes the panel key.
@MainActor
final class WheelPanel {
    private let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: wheelSize),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let view = WheelView(frame: NSRect(origin: .zero, size: wheelSize))
    private var pendingHide: Timer?
    private var keyWatch: Timer?

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
        view.onDismiss = { [weak self] in self?.hide() }
        // Own-app clicks never reach a global monitor, so this only sees clicks outside the wheel.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.hideClickMode() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.hideClickMode() }
        }
    }

    /// Opens the wheel at `point` for `urls` already chosen (Finder selection); a click picks the slice.
    func showForClick(at point: NSPoint, urls: [URL]) {
        hide()
        view.clickURLs = urls
        place(at: point)
        // Finder keeps the keys, so arrows or typing would change its selection under the wheel: hide on any keyDown (not under VoiceOver).
        let opened = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let sinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
                if TapRule.keyTyped(sinceKeyDown: sinceKey, elapsed: ProcessInfo.processInfo.systemUptime - opened,
                                    voiceOver: NSWorkspace.shared.isVoiceOverEnabled) {
                    self?.hide()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        keyWatch = timer
    }

    /// Hides a click-mode wheel; returns whether one was up.
    func hideClickMode() -> Bool {
        guard view.clickURLs != nil else { return false }
        hide()
        return true
    }

    func show(at point: NSPoint) {
        // A wheel already up for this drag stays put; one awaiting its delayed hide belongs to the last drag.
        if view.clickURLs != nil { hide() }
        if panel.isVisible && pendingHide == nil { return }
        pendingHide?.invalidate()
        pendingHide = nil
        place(at: point)
    }

    private func place(at point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        panel.setFrame(Geometry.clampedFrame(size: wheelSize, center: point, visible: screen.visibleFrame), display: true)
        panel.orderFrontRegardless()
    }

    /// Called when the mouse button is up. A drop over a slice may still be on its way,
    /// so give performDragOperation a moment before hiding.
    func dragEnded() {
        guard view.clickURLs == nil else { return }
        guard view.highlight != nil else { return hide() }
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingHide = timer
    }

    func hide() {
        pendingHide?.invalidate()
        pendingHide = nil
        keyWatch?.invalidate()
        keyWatch = nil
        view.highlight = nil
        view.clickURLs = nil
        panel.orderOut(nil)
    }
}

/// Drop target that maps the drag location to a slice and accepts a copy only on a slice (D4).
/// With `clickURLs` set it is a click target instead: hover highlights, a click converts or dismisses.
final class WheelView: NSView {
    var onDrop: ((String, [URL]) -> Void)?
    var onDismiss: (() -> Void)?
    var clickURLs: [URL]? {
        didSet { setAccessibilityChildren(clickURLs == nil ? nil : sliceElements) }
    }
    private lazy var sliceElements: [NSAccessibilityElement] = Geometry.sliceNames.indices.map { i in
        let c = labelCenter(i)
        return SliceElement(
            label: "Convert to \(Geometry.sliceNames[i])", frame: NSRect(x: c.x - 22, y: c.y - 12, width: 44, height: 24),
            parent: self, press: { [weak self] in self?.pick(i) })
    }
    var highlight: Int? {
        didSet { if highlight != oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Swivel format wheel")
        // .activeAlways: Swivel is never the active app, so hover needs it.
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func slice(for sender: NSDraggingInfo) -> Int? {
        slice(at: sender.draggingLocation)
    }

    private func slice(at windowPoint: NSPoint) -> Int? {
        Geometry.slice(
            at: convert(windowPoint, from: nil), center: CGPoint(x: bounds.midX, y: bounds.midY),
            inner: innerRadius, outer: outerRadius, count: Geometry.sliceNames.count)
    }

    /// Centre of slice `i`'s label, in view coordinates.
    func labelCenter(_ i: Int) -> CGPoint {
        let mid = CGFloat(i) * 2 * .pi / CGFloat(Geometry.sliceNames.count), r = (innerRadius + outerRadius) / 2
        return CGPoint(x: bounds.midX + r * sin(mid), y: bounds.midY + r * cos(mid))
    }

    /// Click mode: convert the Finder selection with slice `i`.
    func pick(_ i: Int) {
        guard let urls = clickURLs else { return }
        onDrop?(Geometry.sliceNames[i], urls)
    }

    // The panel is never key, so the first click must act.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard clickURLs != nil else { return }
        if let i = slice(at: event.locationInWindow) { pick(i) } else { onDismiss?() }
    }

    override func mouseMoved(with event: NSEvent) {
        if clickURLs != nil { highlight = slice(at: event.locationInWindow) }
    }

    override func mouseExited(with event: NSEvent) {
        if clickURLs != nil { highlight = nil }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard clickURLs == nil else { return [] }
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

            let color: NSColor = i == highlight ? .alternateSelectedControlTextColor : .labelColor
            let label = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color,
            ])
            let size = label.size()
            let labelAt = labelCenter(i)
            label.draw(at: CGPoint(x: labelAt.x - size.width / 2, y: labelAt.y - size.height / 2))
        }
    }
}

/// VoiceOver button for one slice in click mode; pressing it converts like a click.
private final class SliceElement: NSAccessibilityElement {
    private let press: @MainActor @Sendable () -> Void

    init(label: String, frame: NSRect, parent: NSView, press: @escaping @MainActor @Sendable () -> Void) {
        self.press = press
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityParent(parent)
        setAccessibilityFrameInParentSpace(frame)
    }

    // Accessibility actions are delivered on the main thread.
    override func accessibilityPerformPress() -> Bool {
        let press = press
        MainActor.assumeIsolated { press() }
        return true
    }
}
