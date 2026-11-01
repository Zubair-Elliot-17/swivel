import AppKit
import os
import ServiceManagement

private let loginLog = Logger(subsystem: "dev.zubair.swivel", category: "login")

/// The "Open at Login" menu item, backed by SMAppService.mainApp; the status is re-read on every menu open.
@MainActor
final class LoginItem: NSObject {
    enum Action: Equatable { case register, unregister, openLoginItems }

    let menuItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        menuItem.target = self
        menuItem.action = #selector(click)
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

    func refresh() {
        menuItem.state = Self.isChecked(SMAppService.mainApp.status) ? .on : .off
    }

    @objc private func click() {
        let service = SMAppService.mainApp
        do {
            switch Self.action(for: service.status) {
            case .register: try service.register()
            case .unregister: try service.unregister()
            case .openLoginItems: SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            loginLog.error("open at login failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }
}
