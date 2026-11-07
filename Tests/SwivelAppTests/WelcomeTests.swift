import AppKit
import Testing
import SwivelCore
@testable import Swivel

/// A fresh suite per case; nil leaves the key absent.
@MainActor private func stored(_ value: Any?, _ body: (UserDefaults) -> Void) {
    let name = "swivel.welcometests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    defer { d.removePersistentDomain(forName: name) }
    if let value { d.set(value, forKey: WelcomeSetting.key) }
    body(d)
}

// AC 6: anything but a real Bool true reads as not seen, shows the window once and stores Bool true.
@MainActor @Test(arguments: [nil, "YES", "true", "1", 2, -1, 0.5, [true], Data([1]), ["seen": true], false] as [(any Sendable)?])
func junkWelcomeSeenShowsOnceAndWritesTrue(_ value: (any Sendable)?) {
    stored(value) { d in
        #expect(WelcomeSetting.read(d) == false)
        #expect(Launch.welcomeAtLaunch(d, qa: false, translocated: false))
        #expect(d.object(forKey: "welcomeSeen") as? Bool == true)
        #expect(Launch.welcomeAtLaunch(d, qa: false, translocated: false) == false)
    }
}

// NSNumber 1 bridges `as? Bool` to true, like TrashSetting; pinned so a bridging change shows up.
@MainActor @Test(arguments: [true, NSNumber(value: 1)] as [any Sendable])
func seenWelcomeIsNotShown(_ value: any Sendable) {
    stored(value) { d in
        #expect(WelcomeSetting.read(d))
        #expect(Launch.welcomeAtLaunch(d, qa: false, translocated: false) == false)
    }
}

// QA mode never shows it and never touches the flag, absent or junk.
@MainActor @Test(arguments: [nil, "YES", false, true] as [(any Sendable)?], [false, true])
func qaModeNeverShowsOrWrites(_ value: (any Sendable)?, translocated: Bool) {
    stored(value) { d in
        let before = d.object(forKey: WelcomeSetting.key) as? NSObject
        #expect(Launch.welcomeAtLaunch(d, qa: true, translocated: translocated) == false)
        #expect(d.object(forKey: WelcomeSetting.key) as? NSObject == before)
    }
}

// AC 11: translocated, the window shows even when seen and the flag is left alone.
@MainActor @Test(arguments: [nil, true] as [Bool?])
func translocatedAlwaysShowsAndDoesNotWrite(_ seen: Bool?) {
    stored(seen) { d in
        #expect(Launch.welcomeAtLaunch(d, qa: false, translocated: true))
        #expect(d.object(forKey: WelcomeSetting.key) as? Bool == seen)
    }
}

@Test(arguments: [
    ("/private/var/folders/xy/T/AppTranslocation/1A2B-3C4D/d/Swivel.app", true),
    ("/Applications/Swivel.app", false),
    ("/Users/me/Downloads/Swivel-1.0.0/Swivel.app", false),
    ("/x/AppTranslocationNotes/Swivel.app", false),
])
func translocationIsDetectedFromThePath(path: String, translocated: Bool) {
    #expect(Launch.isTranslocated(path) == translocated)
}

@Test(arguments: TriggerKeys.allCases)
func welcomeStepsNameTheTriggerKey(_ keys: TriggerKeys) {
    #expect(WelcomeView.steps(keys) == ["Drag a file.", "While dragging, tap \(TriggerSetting.label(keys)).", "Drop it on a format."])
}

// The window is built once, survives a close and closes on Esc; translocated, it leads with the move line.
@MainActor @Test func welcomeWindowBuildsAndClosesOnEscape() {
    stored(nil) { d in
        let model = WelcomeModel(translocated: true, loginDisabled: true)
        let welcome = WelcomeWindow(defaults: d, model: model)
        welcome.window.contentView?.layoutSubtreeIfNeeded()
        #expect(welcome.window === welcome.window)
        #expect(welcome.window.isReleasedWhenClosed == false)
        welcome.window.orderFrontRegardless()
        welcome.window.cancelOperation(nil)
        #expect(welcome.window.isVisible == false)
        #expect(d.object(forKey: WelcomeSetting.key) == nil)  // opening it never changes the flag
    }
}
