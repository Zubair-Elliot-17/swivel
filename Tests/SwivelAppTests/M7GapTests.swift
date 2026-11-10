import AppKit
import Testing
@testable import Swivel

// M7 AC 6/10 gap: opening the welcome window (the "Welcome…" path) never touches welcomeSeen,
// reuses one window, and shows the login state it is given.
@MainActor @Test(arguments: [nil, false, true] as [Bool?])
func showingWelcomeNeverChangesTheFlag(_ seen: Bool?) {
    _ = NSApplication.shared  // show() activates NSApp
    let name = "swivel.m7gap.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    defer { d.removePersistentDomain(forName: name) }
    if let seen { WelcomeSetting.write(seen, to: d) }
    let welcome = WelcomeWindow(defaults: d, model: WelcomeModel(translocated: false, loginDisabled: false))
    welcome.show(loginOn: true)
    let first = welcome.window
    #expect(welcome.model.loginOn)
    welcome.show(loginOn: false)
    #expect(welcome.window === first)
    #expect(welcome.model.loginOn == false)
    #expect(d.object(forKey: WelcomeSetting.key) as? Bool == seen)
    welcome.window.close()
    #expect(welcome.window.isVisible == false)
}
