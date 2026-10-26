import AppKit
import CoreServices
import os
import SwivelCore

private let tapLog = Logger(subsystem: "dev.zubair.swivel", category: "tap")
private let automationPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

/// Bare Shift/Ctrl tap with Finder frontmost: reads Finder's selection via Apple events (Automation only).
/// flagsChanged reaches a global monitor without Accessibility on macOS 26 (observed, not documented).
@MainActor
final class FinderTap {
    var isDragLive: () -> Bool = { false }
    /// Hides a click-mode wheel if one is up; returns true so the tap only toggles it off.
    var dismissWheel: () -> Bool = { false }
    var onTap: (NSPoint, [URL]) -> Void = { _, _ in }
    var onStatus: (TapStatus) -> Void = { _ in }
    private(set) var status = TapStatus.needsAccess
    private var detector = TapDetector()
    private var checking = false
    // Runs on main: a hung Finder must fail fast (-1712) instead of the 2-minute default AE timeout.
    private lazy var script = NSAppleScript(source: """
        with timeout of 2 seconds
            tell application "Finder" to set s to selection as alias list
        end timeout
        set out to {}
        repeat with a in s
            set end of out to POSIX path of a
        end repeat
        return out
        """)

    init() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.flagsChanged(event) }
        }
    }

    /// Non-prompting check for the launch-time menu line.
    func refresh() {
        Task {
            setStatus(TapStatus(permission: await Self.permission(ask: false)))
        }
    }

    /// Menu item: prompts once; if already denied the system won't ask again, so open the Automation pane.
    func enable() {
        Task {
            let code = await Self.permission(ask: true)
            tapLog.info("enable: AE permission \(code)")
            setStatus(TapStatus(permission: code))
            if status == .denied { NSWorkspace.shared.open(automationPane) }
        }
    }

    private func flagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        guard let tap = detector.update(
            shift: flags.contains(.shift), control: flags.contains(.control),
            other: !flags.intersection([.command, .option, .function]).isEmpty, time: event.timestamp)
        else { return }
        if dismissWheel() { return }
        if let rule = TapRule.rejection(
            held: tap.held, sinceKeyDown: since(.keyDown), sinceLeftDown: since(.leftMouseDown),
            sinceRightDown: since(.rightMouseDown), buttonsDown: NSEvent.pressedMouseButtons, dragLive: isDragLive(),
            finderFrontmost: Self.finderFrontmost) {
            tapLog.info("tap rejected: \(rule, privacy: .public) (held \(tap.held, format: .fixed(precision: 3)) s)")
            return
        }
        guard !checking else { return tapLog.info("tap ignored: check in flight") }
        checking = true
        let point = NSEvent.mouseLocation, tapTime = event.timestamp
        Task {
            defer { checking = false }
            let code = await Self.permission(ask: false)
            guard code == noErr else {
                tapLog.info("tap: AE permission \(code)")
                return setStatus(TapStatus(permission: code))
            }
            guard let urls = readSelection() else { return }
            setStatus(urls.isEmpty ? .nothingSelected : .ready)
            guard !urls.isEmpty else { return }
            // The check and read can take ~2 s cold; drop the wheel if the user moved on meanwhile.
            if let rule = TapRule.lateRejection(
                elapsed: ProcessInfo.processInfo.systemUptime - tapTime, sinceKeyDown: since(.keyDown),
                sinceLeftDown: since(.leftMouseDown), sinceRightDown: since(.rightMouseDown),
                buttonsDown: NSEvent.pressedMouseButtons, finderFrontmost: Self.finderFrontmost) {
                return tapLog.info("tap dropped: \(rule, privacy: .public) after read")
            }
            onTap(point, urls)
        }
    }

    private static var finderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private func since(_ type: CGEventType) -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    /// Finder's selection as file URLs; nil if the script failed (logged).
    private func readSelection() -> [URL]? {
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else {
            let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
            tapLog.error("Finder selection failed: \(code) \(error?[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)")
            if code == -1743 || code == -1744 { setStatus(TapStatus(permission: Int32(code))) }
            return nil
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }.map { URL(fileURLWithPath: $0) }
    }

    private func setStatus(_ new: TapStatus) {
        status = new
        onStatus(new)
    }

    /// The header says never call this on the main thread: a prompt can block for a long time.
    private nonisolated static func permission(ask: Bool) async -> OSStatus {
        await Task.detached {
            let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
            return AEDeterminePermissionToAutomateTarget(finder.aeDesc, typeWildCard, typeWildCard, ask)
        }.value
    }
}
