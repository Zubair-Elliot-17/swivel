import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dragLine = NSMenuItem(title: "Drag: idle", action: nil, keyEquivalent: "")
    private let lastDropLine = NSMenuItem(title: "Last drop: none", action: nil, keyEquivalent: "")
    private var dragMonitor: DragMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Swivel")

        let menu = NSMenu()
        menu.addItem(dragLine)
        menu.addItem(lastDropLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Swivel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        let wheel = WheelPanel { [lastDropLine] name, urls in
            let paths = urls.map(\.path)
            log.info("drop slice=\(name, privacy: .public) urls=\(paths.joined(separator: ", "), privacy: .public)")
            lastDropLine.title = "Last drop: \(name) ← \(paths.count == 1 ? paths[0] : "\(paths.count) files")"
        }
        dragMonitor = DragMonitor(
            onState: { [dragLine] in dragLine.title = "Drag: \($0)" },
            onTrigger: { wheel.show(at: $0) },
            onEnd: { wheel.dragEnded() }
        )
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
