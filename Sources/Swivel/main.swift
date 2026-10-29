import AppKit
import SwivelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dragLine = NSMenuItem(title: "Drag: idle", action: nil, keyEquivalent: "")
    private let lastDropLine = NSMenuItem(title: "Last: none", action: nil, keyEquivalent: "")
    private let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal), keyEquivalent: "")
    private let tapLine = NSMenuItem(title: TapStatus.needsAccess.menuLine, action: nil, keyEquivalent: "")
    private let enableTapItem = NSMenuItem(title: "Enable Shift-tap in Finder…", action: #selector(enableTap), keyEquivalent: "")
    private var dragMonitor: DragMonitor?
    private var finderTap: FinderTap?
    private var revealTargets: [URL] = []
    private var busy = 0  // batches in flight; overlapping drops keep the icon busy until all finish
    private var qaMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(dragLine)
        menu.addItem(lastDropLine)
        revealItem.target = self
        revealItem.isEnabled = false
        menu.addItem(revealItem)
        menu.addItem(.separator())
        menu.addItem(tapLine)
        enableTapItem.target = self
        menu.addItem(enableTapItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Swivel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let wheel = WheelPanel { [weak self] name, urls in self?.drop(name, urls) }
        let dragMonitor = DragMonitor(
            onState: { [dragLine] in dragLine.title = "Drag: \($0)" },
            onLive: { _ = wheel.hideClickMode() },
            onTrigger: { wheel.show(at: $0) },
            onEnd: { wheel.dragEnded() }
        )
        self.dragMonitor = dragMonitor

        // Tap path: the click wheel converts through the same drop(_:_:) as a drag.
        let finderTap = FinderTap()
        finderTap.isDragLive = { dragMonitor.isLive }
        finderTap.dismissWheel = { wheel.hideClickMode() }
        finderTap.onTap = { wheel.showForClick(at: $0, urls: $1) }
        finderTap.onStatus = { [tapLine, enableTapItem] status in
            tapLine.title = status.menuLine
            // nothingSelected means access is granted, so there is nothing to enable.
            enableTapItem.isEnabled = status == .needsAccess || status == .denied
        }
        finderTap.refresh()
        self.finderTap = finderTap

        // QA entry point for scripts/qa.sh: SWIVEL_QA=1 Swivel --qa-drop <slice> <path>... runs one drop, prints the menu line, quits.
        let args = CommandLine.arguments
        if ProcessInfo.processInfo.environment["SWIVEL_QA"] == "1", args.count > 2, args[1] == "--qa-drop" {
            qaMode = true
            drop(args[2], args.dropFirst(3).map { URL(fileURLWithPath: $0) })
            if busy == 0 { NSApp.terminate(nil) }  // unknown slice: nothing started
        }
    }

    @objc private func enableTap() {
        finderTap?.enable()
    }

    private func drop(_ name: String, _ urls: [URL]) {
        let paths = urls.map(\.path)
        log.info("drop slice=\(name, privacy: .public) urls=\(paths.joined(separator: ", "), privacy: .public)")
        let job: @Sendable () async -> [Outcome]
        switch (ImageFormat(rawValue: name), name) {
        case (let format?, _): job = { await Converter.convertBatch(urls, to: format) }
        case (nil, "PDF"): job = { await Converter.makePDF(urls) }
        case (nil, "Text"): job = { await Converter.textBatch(urls) }
        default:
            log.info("drop on unknown slice \(name, privacy: .public)")
            return
        }
        busy += 1
        updateIcon()
        Task { @MainActor in
            let outcomes = await job()
            for outcome in outcomes { logOutcome(outcome) }
            // The batch that finishes last owns the line and Reveal.
            let summary = BatchSummary(outcomes)
            lastDropLine.title = summary.menuLine
            revealTargets = summary.outputs
            revealItem.isEnabled = !revealTargets.isEmpty
            busy -= 1
            updateIcon()
            if qaMode {
                print(summary.menuLine)
                NSApp.terminate(nil)
            }
        }
    }

    private func logOutcome(_ outcome: Outcome) {
        switch outcome {
        case .converted(let source, let outputs):
            let names = outputs.map(\.lastPathComponent).joined(separator: ", ")
            log.info("converted \(source.lastPathComponent, privacy: .public) -> \(names, privacy: .public)")
        case .skipped(let source, let reason):
            log.info("skipped \(source.lastPathComponent, privacy: .public): \(reason.description, privacy: .public)")
        case .failed(let source, let reason, let detail):
            log.info("failed \(source.lastPathComponent, privacy: .public): \(detail ?? reason, privacy: .public)")
        }
    }

    private func updateIcon() {
        statusItem.button?.image = busy > 0
            ? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Swivel, converting")
            : NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Swivel")
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(revealTargets)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
