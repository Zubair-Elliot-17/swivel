import AppKit
import os
import ServiceManagement

private let loginLog = Logger(subsystem: "dev.zubair.swivel", category: "login")

/// The "Open at Login" menu item, backed by SMAppService.mainApp; the status is re-read on every menu open.
@MainActor
final class LoginItem: NSObject {
    enum Action: Equatable { case register, unregister, openLoginItems }

    let menuItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")
    private let status: () -> SMAppService.Status
    private let run: @MainActor (Action) throws -> Void
    private let alert: @MainActor (String) -> Void

    /// Translocated, a login item would point at a random read-only path, so it is never registered.
    var disabled = false {
        didSet { menuItem.isEnabled = !disabled }
    }

    /// The seams default to the real service and an NSAlert; tests pass their own.
    init(status: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         run: @escaping @MainActor (Action) throws -> Void = LoginItem.perform,
         alert: @escaping @MainActor (String) -> Void = LoginItem.showAlert) {
        self.status = status
        self.run = run
        self.alert = alert
        super.init()
        menuItem.target = self
        menuItem.action = #selector(toggle)
    }

    /// Checked only when enabled; a fresh bundle reports notFound (OV4) and shows unchecked.
    nonisolated static func isChecked(_ status: SMAppService.Status) -> Bool { status == .enabled }

    nonisolated static func action(for status: SMAppService.Status) -> Action {
        switch status {
        case .enabled: .unregister
        case .requiresApproval: .openLoginItems
        default: .register
        }
    }

    var isOn: Bool { Self.isChecked(status()) }

    func refresh() {
        menuItem.state = isOn ? .on : .off
    }

    /// The one toggle for the menu item and the welcome checkbox.
    @objc func toggle() {
        guard !disabled else { return }
        do {
            try run(Self.action(for: status()))
        } catch {
            loginLog.error("open at login failed: \((error as NSError).code)")
            alert("Couldn't change Open at Login.")
        }
        refresh()
    }

    private static func perform(_ action: Action) throws {
        let service = SMAppService.mainApp
        switch action {
        case .register: try service.register()
        case .unregister: try service.unregister()
        case .openLoginItems: SMAppService.openSystemSettingsLoginItems()
        }
    }

    private static func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate(ignoringOtherApps: true)  // an accessory app's alert would open behind the frontmost app
        alert.runModal()
    }
}
