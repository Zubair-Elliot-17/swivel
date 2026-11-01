import AppKit
import Testing
import SwivelCore
@testable import Swivel

/// A throwaway suite holding `layouts`, removed after `body` (never the real dev.zubair.swivel domain).
@MainActor private func withLayouts(_ layouts: [FileKind: [String]], _ body: (UserDefaults) -> Void) {
    let name = "swivel.apptests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { suite.removePersistentDomain(forName: name) }
    for (kind, names) in layouts { suite.set(names, forKey: kind.key) }
    body(suite)
}

private func f(_ name: String) -> URL { URL(fileURLWithPath: "/nonexistent/swivel/\(name)") }

/// Drag info over a private pasteboard holding `urls`, at `location` in window coordinates.
@MainActor private final class FakeDrag: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    init(_ urls: [URL], at location: NSPoint = .zero) {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("swivel.tests.\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects(urls.map { $0 as NSURL })
        draggingLocation = location
    }
    deinit { MainActor.assumeIsolated { draggingPasteboard.releaseGlobally() } }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@MainActor private func labels(_ view: WheelView) -> [String] {
    (view.accessibilityChildren() ?? []).compactMap { ($0 as? NSAccessibilityElement)?.accessibilityLabel() }
}

private let user: [FileKind: [String]] = [.image: ["TIFF", "PNG"], .video: ["WAV", "MP4", "GIF"], .audio: ["WAV"]]

// OV3: all 4 sites that set the slices read the user's layout.
@MainActor @Test func initialWheelIsTheUserImageLayout() {
    withLayouts(user) { d in
        #expect(WheelPanel(defaults: d) { _, _ in }.view.slices == ["TIFF", "PNG"])
    }
}

@MainActor @Test func clickWheelOnAMovieIsTheUserVideoLayout() {
    withLayouts(user) { d in
        let wheel = WheelPanel(defaults: d) { _, _ in }
        wheel.showForClick(at: .zero, urls: [f("clip.mov")])
        defer { wheel.hide() }
        #expect(wheel.view.slices == ["WAV", "MP4", "GIF"])
        #expect(wheel.view.kind == .video)
    }
}

@MainActor @Test func hideResetsToTheUserImageLayout() {
    withLayouts(user) { d in
        let wheel = WheelPanel(defaults: d) { _, _ in }
        wheel.showForClick(at: .zero, urls: [f("a.m4a")])
        wheel.hide()
        #expect(wheel.view.slices == ["TIFF", "PNG"])
        #expect(wheel.view.kind == .image)
    }
}

@MainActor @Test func dragOfAnAudioFileIsTheUserAudioLayout() {
    withLayouts(user) { d in
        let wheel = WheelPanel(defaults: d) { _, _ in }
        _ = wheel.view.draggingEntered(FakeDrag([f("a.m4a")]))
        #expect(wheel.view.slices == ["WAV"])
        #expect(wheel.view.kind == .audio)
    }
}

// OV2: the video layout equals the audio list, yet VoiceOver must say "Extract audio" on the video wheel.
@MainActor @Test func voiceOverLabelsFollowTheKindEvenForEqualLists() {
    withLayouts([.video: ["M4A", "WAV"]]) { d in
        let wheel = WheelPanel(defaults: d) { _, _ in }
        defer { wheel.hide() }
        wheel.showForClick(at: .zero, urls: [f("voice.m4a")])
        #expect(labels(wheel.view) == ["Convert to M4A", "Convert to WAV"])
        wheel.showForClick(at: .zero, urls: [f("clip.mov")])
        #expect(labels(wheel.view) == ["Extract audio as M4A", "Extract audio as WAV"])
        // Straight from video to audio, with no image layout between.
        wheel.view.show(.audio)
        #expect(labels(wheel.view) == ["Convert to M4A", "Convert to WAV"])
    }
}

// Hidden slices are gone everywhere; drawn label i, hit-test i, pick(i), drop on i and AX element i name the same slice.
@MainActor @Test func everyPathNamesTheSameSliceInTheUserOrder() {
    withLayouts([.image: ["TIFF", "Text", "PNG"]]) { d in
        var dropped: [String] = []
        let wheel = WheelPanel(defaults: d) { name, _ in dropped.append(name) }
        defer { wheel.hide() }
        let view = wheel.view
        wheel.showForClick(at: .zero, urls: [f("a.jpg")])
        #expect(labels(view) == ["Convert to TIFF", "Extract text", "Convert to PNG"])
        // A pick converts and hides the wheel, so reopen it for each.
        for i in 0..<3 {
            wheel.showForClick(at: .zero, urls: [f("a.jpg")])
            view.pick(i)
        }
        for i in 0..<3 {
            wheel.showForClick(at: .zero, urls: [f("a.jpg")])
            _ = (view.accessibilityChildren()?[i] as? NSAccessibilityElement)?.accessibilityPerformPress()
        }
        for i in 0..<3 {
            let drag = FakeDrag([f("a.jpg")], at: view.labelCenter(i))
            #expect(view.draggingEntered(drag) == .copy)
            #expect(view.highlight == i)
            #expect(view.performDragOperation(drag))
        }
        let order = ["TIFF", "Text", "PNG"]
        #expect(dropped == order + order + order)
    }
}
