import AppKit
import SwiftUI
import Testing
import SwivelCore
@testable import Swivel

@MainActor private func withSuite(_ body: (UserDefaults) -> Void) {
    let name = "swivel.apptests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    body(suite)
}

@Test func rowsAreVisibleInOrderThenHiddenInDefaultOrder() {
    let rows = LayoutRows.rows(visible: ["WAV", "MP4"], kind: .video)
    #expect(rows.map(\.name) == ["WAV", "MP4", "HEVC", "MOV", "GIF", "M4A"])
    #expect(rows.map(\.isOn) == [true, true, false, false, false, false])
}

// The Settings List keys rows by value: Video and Audio both have M4A and WAV, and equal ids made
// a click on Audio's M4A change the Video wheel (z-test U8).
@Test func rowIdsAreUniqueAcrossKinds() {
    let all = FileKind.allCases.flatMap { LayoutRows.rows(visible: $0.known, kind: $0) }
    #expect(Set(all).count == all.count)
}

@Test func turningAHiddenRowOnAppendsIt() {
    #expect(LayoutRows.toggled(["WAV", "MP4"], "HEVC", on: true) == ["WAV", "MP4", "HEVC"])
    #expect(LayoutRows.toggled(["WAV", "MP4"], "MP4", on: true) == ["WAV", "MP4"])
}

@Test func turningARowOffRemovesItButNeverTheLast() {
    #expect(LayoutRows.toggled(["WAV", "MP4"], "WAV", on: false) == ["MP4"])
    #expect(LayoutRows.toggled(["MP4"], "MP4", on: false) == ["MP4"])
    #expect(LayoutRows.canHide(["MP4"]) == false)
    #expect(LayoutRows.canHide(["WAV", "MP4"]))
}

@Test func movingRowsReordersTheVisibleOnes() {
    let rows = LayoutRows.rows(visible: ["PNG", "JPEG", "HEIC"], kind: .image)
    // Drag HEIC (row 2) to the top; hidden rows stay hidden.
    #expect(LayoutRows.moved(rows, from: IndexSet(integer: 2), to: 0) == ["HEIC", "PNG", "JPEG"])
    // A hidden row dragged among the visible ones stays hidden.
    #expect(LayoutRows.moved(rows, from: IndexSet(integer: 5), to: 0) == ["PNG", "JPEG", "HEIC"])
}

@MainActor @Test func hostileStoredLayoutShowsTheDefaultsAndSavesOnlyCleanArrays() {
    withSuite { d in
        d.set("junk", forKey: FileKind.image.key)
        #expect(LayoutRows.rows(visible: Geometry.slices(for: .image, defaults: d), kind: .image).map(\.isOn) == Array(repeating: true, count: 7))
        LayoutRows.save(["JPEG", "BMP", "JPEG"], kind: .image, defaults: d)
        #expect(d.object(forKey: FileKind.image.key) as? [String] == ["JPEG"])
        LayoutRows.reset(.image, defaults: d)
        #expect(d.object(forKey: FileKind.image.key) == nil)
    }
}

@MainActor @Test func settingsWindowIsOneReusedInstance() {
    withSuite { d in
        d.set("junk", forKey: FileKind.image.key)
        d.set("abc", forKey: QualitySetting.key)
        let settings = SettingsWindow(defaults: d)
        settings.window.contentView?.layoutSubtreeIfNeeded()  // builds the SwiftUI body on hostile values
        #expect(settings.window === settings.window)
        #expect(settings.window.isReleasedWhenClosed == false)
        #expect(settings.window.contentViewController != nil)
    }
}

@MainActor @Test func qualitySliderShowsTheCleanedValueAndWritesTheSetting() {
    withSuite { d in
        d.set("abc", forKey: "quality")
        #expect(QualitySetting.read(d) == 0.85)
        QualitySetting.write(0.6, to: d)
        #expect(d.object(forKey: "quality") as? Double == 0.6)
        QualitySetting.write(7, to: d)
        #expect(d.object(forKey: "quality") as? Double == 1)
        #expect(QualitySetting.range == 0.5...1)
    }
}

// F1: the window outlives a close, so each open must re-read the store, or a toggle saves over newer values.
@MainActor @Test func reopenedSettingsShowTheCurrentStore() throws {
    withSuite { d in
        let settings = SettingsWindow(defaults: d)
        settings.reloadIfClosed()
        settings.window.contentView?.layoutSubtreeIfNeeded()
        d.set(["WAV", "MP4"], forKey: FileKind.video.key)
        d.set(0.6, forKey: QualitySetting.key)
        settings.reloadIfClosed()
        let view = (settings.window.contentViewController as? NSHostingController<SettingsView>)?.rootView
        #expect(view?.layouts[.video] == ["WAV", "MP4"])
        #expect(view?.quality == 0.6)
    }
}

// Choosing Settings while it is already open only brings it forward (scroll and focus stay).
@MainActor @Test func openSettingsAreNotRebuilt() {
    withSuite { d in
        let settings = SettingsWindow(defaults: d)
        settings.window.orderFrontRegardless()
        defer { settings.window.close() }
        let shown = settings.window.contentViewController
        settings.reloadIfClosed()
        #expect(settings.window.contentViewController === shown)
    }
}

// MARK: General: trash toggle and trigger keys (M6)

/// Fresh suite per row; nil leaves the key absent.
@MainActor private func stored(_ key: String, _ value: Any?, _ body: (UserDefaults) -> Void) {
    withSuite { d in
        if let value { d.set(value, forKey: key) }
        body(d)
    }
}

@MainActor @Test(arguments: [nil, "YES", "true", "1", 2, -1, 0.5, [true], Data([1]), ["on": true], false, 0] as [(any Sendable)?])
func trashOriginalJunkReadsOff(_ value: (any Sendable)?) {
    stored(TrashSetting.key, value) { #expect(TrashSetting.read($0) == false) }
}

// NSNumber 1 bridges `as? Bool` to true; pinned here so a change in bridging shows up.
@MainActor @Test(arguments: [true, NSNumber(value: 1)] as [any Sendable])
func trashOriginalTrueReadsOn(_ value: any Sendable) {
    stored(TrashSetting.key, value) { #expect(TrashSetting.read($0)) }
}

@MainActor @Test(arguments: [nil, "", "SHIFT", "Shift", " shift", "ctrl", "none", 1, true, ["shift"], Data([1])] as [(any Sendable)?])
func triggerKeysJunkReadsBoth(_ value: (any Sendable)?) {
    stored(TriggerSetting.key, value) { #expect(TriggerSetting.read($0) == .both) }
}

@MainActor @Test(arguments: TriggerKeys.allCases)
func triggerKeysRoundTrip(_ keys: TriggerKeys) {
    withSuite { d in
        TriggerSetting.write(keys, to: d)
        #expect(d.object(forKey: "triggerKeys") as? String == keys.rawValue)
        #expect(TriggerSetting.read(d) == keys)
    }
}

@MainActor @Test func trashToggleRoundTripsAsABool() {
    withSuite { d in
        TrashSetting.write(true, to: d)
        #expect(d.object(forKey: "trashOriginal") as? Bool == true)
        #expect(TrashSetting.read(d))
        TrashSetting.write(false, to: d)
        #expect(d.object(forKey: "trashOriginal") as? Bool == false)
        #expect(TrashSetting.read(d) == false)
    }
}

@MainActor @Test func hostileGeneralValuesShowTheCleanedDefaults() {
    withSuite { d in
        d.set("YES", forKey: TrashSetting.key)
        d.set("junk", forKey: TriggerSetting.key)
        let settings = SettingsWindow(defaults: d)
        settings.window.contentView?.layoutSubtreeIfNeeded()  // builds the body on hostile values
        let view = (settings.window.contentViewController as? NSHostingController<SettingsView>)?.rootView
        #expect(view?.trash == false)
        #expect(view?.trigger == .both)
        // Nothing was written back while showing them.
        #expect(d.object(forKey: TrashSetting.key) as? String == "YES")
    }
}

@Test func triggerPickerNamesEveryChoice() {
    #expect(TriggerKeys.allCases.map(TriggerSetting.label) == ["Shift", "Control", "Shift or Control"])
}

// M7 AC 12: each slice toggle names its wheel. In-process AX of NSHostingView exposes no labels (probed), so U8 checks the tree.
@Test(arguments: [(FileKind.image, "PNG", "Show PNG on the Images wheel"), (.video, "MP4", "Show MP4 on the Video wheel"),
                  (.audio, "WAV", "Show WAV on the Audio wheel")])
func sliceToggleLabelNamesTheWheel(kind: FileKind, name: String, label: String) {
    #expect(SettingsView.toggleLabel(name, kind: kind) == label)
}
