import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dragLine = NSMenuItem(title: "Drag: idle", action: nil, keyEquivalent: "")
    private let lastDropLine = NSMenuItem(title: "Last drop: none", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Swivel")

        let menu = NSMenu()
        menu.addItem(dragLine)
        menu.addItem(lastDropLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Swivel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
