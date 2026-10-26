import AppKit
import os
import SwivelCore

let log = Logger(subsystem: "dev.zubair.swivel", category: "drag")

/// Watches other apps' drags via global mouse monitors and the drag pasteboard (no Accessibility).
/// Polls from mouse-down; once the drag carries file URLs, a Shift/Ctrl rising edge is a trigger.
@MainActor
final class DragMonitor {
    private let onState: (String) -> Void
    private let onLive: () -> Void
    private let onTrigger: (NSPoint) -> Void
    private let onEnd: () -> Void
    private let pasteboard = NSPasteboard(name: .drag)
    private var startCount = 0
    private var lastCount = 0
    private var timer: Timer?
    private var trigger = DragTrigger(shift: false, control: false)
    private(set) var isLive = false

    init(onState: @escaping (String) -> Void, onLive: @escaping () -> Void, onTrigger: @escaping (NSPoint) -> Void,
         onEnd: @escaping () -> Void) {
        self.onState = onState
        self.onLive = onLive
        self.onTrigger = onTrigger
        self.onEnd = onEnd
        // Global monitor handlers arrive on the main thread.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    private func mouseDown() {
        end()
        startCount = pasteboard.changeCount
        lastCount = startCount
        // Baseline at mouse-down so Shift held from a multi-select never fires (D2).
        let flags = CGEventSource.flagsState(.combinedSessionState)
        trigger = DragTrigger(shift: flags.contains(.maskShift), control: flags.contains(.maskControl))
        // Common mode keeps polling while a run loop is in event tracking.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        // The drag is over once the left button is up: a drop, a release elsewhere or Esc (D1).
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return end() }
        // Finder bumps changeCount before it writes its types, so re-read on every change until live.
        if !isLive, pasteboard.changeCount != lastCount {
            lastCount = pasteboard.changeCount
            // Promise-only drags (Photos, Mail) carry no .fileURL and are ignored (D8).
            if pasteboard.types?.contains(.fileURL) == true {
                isLive = true
                setState("file drag seen")
                onLive()
            }
        }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if trigger.tick(shift: flags.contains(.maskShift), control: flags.contains(.maskControl), live: isLive) {
            log.info("trigger")
            setState("wheel requested")
            onTrigger(NSEvent.mouseLocation)
        }
    }

    private func end() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        if isLive {
            isLive = false
            onEnd()
        } else if pasteboard.changeCount != startCount, pasteboard.types?.contains(.fileURL) != true {
            setState("non-file drag")
        }
    }

    private func setState(_ state: String) {
        log.info("drag state: \(state, privacy: .public)")
        onState(state)
    }
}
