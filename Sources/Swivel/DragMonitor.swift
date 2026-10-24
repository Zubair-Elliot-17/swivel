import AppKit
import os
import SwivelCore

let log = Logger(subsystem: "dev.zubair.swivel", category: "drag")

/// Watches other apps' drags via global mouse monitors and the drag pasteboard (no Accessibility).
/// While a file drag is live it polls Shift/Ctrl and reports a rising edge as a trigger.
@MainActor
final class DragMonitor {
    private let onState: (String) -> Void
    private let onTrigger: (NSPoint) -> Void
    private let onEnd: () -> Void
    private let pasteboard = NSPasteboard(name: .drag)
    private var startCount = 0
    private var checked = true  // nothing to check until the first mouse-down snapshot
    private var timer: Timer?
    private var shift = ModifierEdge(initiallyDown: false)
    private var control = ModifierEdge(initiallyDown: false)

    init(onState: @escaping (String) -> Void, onTrigger: @escaping (NSPoint) -> Void, onEnd: @escaping () -> Void) {
        self.onState = onState
        self.onTrigger = onTrigger
        self.onEnd = onEnd
        // Global monitor handlers arrive on the main thread.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    private func mouseDown() {
        end()
        startCount = pasteboard.changeCount
        checked = false
    }

    // Fires at pointer rate, so only compare changeCount; read types once per drag (D7).
    private func mouseDragged() {
        guard !checked, pasteboard.changeCount != startCount else { return }
        checked = true
        // Promise-only drags (Photos, Mail) carry no .fileURL and are ignored in M1 (D8).
        guard pasteboard.types?.contains(.fileURL) == true else {
            setState("non-file drag")
            return
        }
        setState("file drag seen")
        let flags = CGEventSource.flagsState(.combinedSessionState)
        shift = ModifierEdge(initiallyDown: flags.contains(.maskShift))
        control = ModifierEdge(initiallyDown: flags.contains(.maskControl))
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        // The drag is over once the left button is up: a drop, a release elsewhere or Esc (D1).
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return end() }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let shiftEdge = shift.update(down: flags.contains(.maskShift))
        let controlEdge = control.update(down: flags.contains(.maskControl))
        if shiftEdge || controlEdge {
            log.info("trigger")
            setState("wheel requested")
            onTrigger(NSEvent.mouseLocation)
        }
    }

    private func end() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        onEnd()
    }

    private func setState(_ state: String) {
        log.info("drag state: \(state, privacy: .public)")
        onState(state)
    }
}
