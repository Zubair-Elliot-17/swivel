import AppKit
import Testing
import SwivelCore
@testable import Swivel

// Tester gap tests for M5 (untracked): throwaway suites only, removed after each test.
@MainActor private func withSuite(_ body: (UserDefaults) -> Void) {
    let name = "swivel.apptests.gap.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    body(suite)
}

private func f(_ name: String) -> URL { URL(fileURLWithPath: "/nonexistent/swivel/\(name)") }

// U7 at unit level: a hostile stored layout gives the full default wheel and 7 AX buttons.
@MainActor @Test func hostileStoredLayoutGivesTheDefaultWheel() {
    withSuite { d in
        d.set("junk", forKey: FileKind.image.key)
        d.set([1, 2], forKey: FileKind.video.key)
        let wheel = WheelPanel(defaults: d) { _, _ in }
        defer { wheel.hide() }
        #expect(wheel.view.slices == FileKind.image.known)
        wheel.showForClick(at: .zero, urls: [f("a.jpg")])
        #expect(wheel.view.accessibilityChildren()?.count == 7)
        wheel.showForClick(at: .zero, urls: [f("clip.mov")])
        #expect(wheel.view.slices == FileKind.video.known)
    }
}

// "The next wheel shows exactly that list": a Settings change after launch reaches the next show.
@MainActor @Test func layoutChangedAfterLaunchReachesTheNextWheel() {
    withSuite { d in
        let wheel = WheelPanel(defaults: d) { _, _ in }
        defer { wheel.hide() }
        LayoutRows.save(["HEIC", "PNG"], kind: .image, defaults: d)
        wheel.showForClick(at: .zero, urls: [f("a.jpg")])
        #expect(wheel.view.slices == ["HEIC", "PNG"])
        #expect(wheel.view.accessibilityChildren()?.count == 2)
        LayoutRows.reset(.image, defaults: d)
        wheel.hide()
        #expect(wheel.view.slices == FileKind.image.known)
    }
}

// AC9: one visible slice is the only AX button, and nothing outside click mode.
@MainActor @Test func oneSliceWheelExposesOnlyThatSlice() {
    withSuite { d in
        d.set(["WebP"], forKey: FileKind.image.key)
        let wheel = WheelPanel(defaults: d) { _, _ in }
        defer { wheel.hide() }
        wheel.showForClick(at: .zero, urls: [f("a.jpg")])
        let ax = (wheel.view.accessibilityChildren() ?? []).compactMap { ($0 as? NSAccessibilityElement)?.accessibilityLabel() }
        #expect(ax == ["Convert to WebP"])
        wheel.hide()
        #expect((wheel.view.accessibilityChildren() ?? []).isEmpty)
    }
}

// The slider never stores an out-of-range or NaN value.
@Test func qualityWriteClampsEveryValue() {
    let name = "swivel.apptests.gap.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    defer { d.removePersistentDomain(forName: name) }
    QualitySetting.write(.nan, to: d)
    #expect(d.double(forKey: QualitySetting.key) == 0.85)
    QualitySetting.write(0.2, to: d)
    #expect(d.double(forKey: QualitySetting.key) == 0.5)
}
