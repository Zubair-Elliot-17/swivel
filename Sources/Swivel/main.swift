import AppKit
import SwivelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dragLine = NSMenuItem(title: "Drag: idle", action: nil, keyEquivalent: "")
    private let lastDropLine = NSMenuItem(title: "Last: none", action: nil, keyEquivalent: "")
    private let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal), keyEquivalent: "")
    private var dragMonitor: DragMonitor?
    private var revealTargets: [URL] = []
    private var busy = 0  // batches in flight; overlapping drops keep the icon busy until all finish

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
        menu.addItem(NSMenuItem(title: "Quit Swivel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let wheel = WheelPanel { [weak self] name, urls in self?.drop(name, urls) }
        dragMonitor = DragMonitor(
            onState: { [dragLine] in dragLine.title = "Drag: \($0)" },
            onTrigger: { wheel.show(at: $0) },
            onEnd: { wheel.dragEnded() }
        )
    }

    private func drop(_ name: String, _ urls: [URL]) {
        let paths = urls.map(\.path)
        log.info("drop slice=\(name, privacy: .public) urls=\(paths.joined(separator: ", "), privacy: .public)")
        guard let format = ImageFormat(rawValue: name) else {
            lastDropLine.title = "PDF arrives in M3"
            return
        }
        busy += 1
        updateIcon()
        Task { @MainActor in
            let outcomes = await Converter.convertBatch(urls, to: format)
            for outcome in outcomes { logOutcome(outcome) }
            // The batch that finishes last owns the line and Reveal.
            let summary = BatchSummary(outcomes)
            lastDropLine.title = summary.menuLine
            revealTargets = summary.outputs
            revealItem.isEnabled = !revealTargets.isEmpty
            busy -= 1
            updateIcon()
        }
    }

    private func logOutcome(_ outcome: Outcome) {
        switch outcome {
        case .converted(let source, let output):
            log.info("converted \(source.lastPathComponent, privacy: .public) -> \(output.lastPathComponent, privacy: .public)")
        case .skipped(let source, let reason):
            log.info("skipped \(source.lastPathComponent, privacy: .public): \(reason.description, privacy: .public)")
        case .failed(let source, let reason):
            log.info("failed \(source.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
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
