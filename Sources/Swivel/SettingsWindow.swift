import AppKit
import SwiftUI
import SwivelCore

/// The one Settings window; repeat opens bring the same instance forward.
@MainActor
final class SettingsWindow {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(defaults: defaults)))
        window.title = "Swivel Settings"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }()

    /// Fresh content from the store: the window outlives a close, and the store may have changed meanwhile.
    func reload() {
        window.contentViewController = NSHostingController(rootView: SettingsView(defaults: defaults))
    }

    func show() {
        reload()
        // An accessory app isn't active, so the window would open behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Row logic for one kind's slice list: visible in order, then hidden in default order (toggle off).
enum LayoutRows {
    struct Row: Hashable {
        let name: String
        let isOn: Bool
    }

    static func rows(visible: [String], kind: FileKind) -> [Row] {
        visible.map { Row(name: $0, isOn: true) } + kind.known.filter { !visible.contains($0) }.map { Row(name: $0, isOn: false) }
    }

    /// On appends a hidden slice; off removes one, except the last visible.
    static func toggled(_ visible: [String], _ name: String, on: Bool) -> [String] {
        if on { return visible.contains(name) ? visible : visible + [name] }
        return canHide(visible) ? visible.filter { $0 != name } : visible
    }

    static func canHide(_ visible: [String]) -> Bool { visible.count > 1 }

    /// The visible order after a list drag; a hidden row stays hidden wherever it lands.
    static func moved(_ rows: [Row], from source: IndexSet, to destination: Int) -> [String] {
        var rows = rows
        rows.move(fromOffsets: source, toOffset: destination)
        return rows.filter(\.isOn).map(\.name)
    }

    static func save(_ visible: [String], kind: FileKind, defaults: UserDefaults) {
        defaults.set(Geometry.clean(visible, known: kind.known), forKey: kind.key)
    }

    /// Back to the default layout: the key goes, so later default changes reach this user too.
    static func reset(_ kind: FileKind, defaults: UserDefaults) {
        defaults.removeObject(forKey: kind.key)
    }
}

/// The JPEG/HEIC quality setting, read and written cleaned (the stored value is untrusted).
enum QualitySetting {
    static let key = "quality"
    static let range = 0.5...1.0

    static func read(_ defaults: UserDefaults) -> Double { Converter.quality(defaults.object(forKey: key)) }
    static func write(_ value: Double, to defaults: UserDefaults) { defaults.set(Converter.quality(value), forKey: key) }
}

struct SettingsView: View {
    let defaults: UserDefaults
    @State var layouts: [FileKind: [String]]
    @State var quality: Double

    init(defaults: UserDefaults) {
        self.defaults = defaults
        _layouts = State(initialValue: Dictionary(uniqueKeysWithValues: FileKind.allCases.map { ($0, Geometry.slices(for: $0, defaults: defaults)) }))
        _quality = State(initialValue: QualitySetting.read(defaults))
    }

    var body: some View {
        List {
            ForEach(FileKind.allCases, id: \.self) { kind in
                Section {
                    let visible = layouts[kind] ?? kind.known
                    let rows = LayoutRows.rows(visible: visible, kind: kind)
                    ForEach(rows, id: \.self) { row in
                        Toggle(row.name, isOn: Binding(
                            get: { row.isOn },
                            set: { set(kind, LayoutRows.toggled(visible, row.name, on: $0)) }))
                            .disabled(row.isOn && !LayoutRows.canHide(visible))
                    }
                    .onMove { set(kind, LayoutRows.moved(rows, from: $0, to: $1)) }
                } header: {
                    HStack {
                        Text(title(kind))
                        Spacer()
                        Button("Reset") {
                            LayoutRows.reset(kind, defaults: defaults)
                            layouts[kind] = Geometry.slices(for: kind, defaults: defaults)
                        }
                        .accessibilityLabel("Reset \(title(kind))")
                    }
                }
            }
            Section("JPEG and HEIC quality") {
                Slider(value: Binding(get: { quality }, set: { quality = $0; QualitySetting.write($0, to: defaults) }),
                       in: QualitySetting.range) {
                    Text(quality, format: .percent.precision(.fractionLength(0)))
                }
            }
        }
        .frame(width: 340, height: 560)
    }

    private func set(_ kind: FileKind, _ visible: [String]) {
        LayoutRows.save(visible, kind: kind, defaults: defaults)
        layouts[kind] = Geometry.slices(for: kind, defaults: defaults)
    }

    private func title(_ kind: FileKind) -> String {
        switch kind {
        case .image: "Images"
        case .video: "Video"
        case .audio: "Audio"
        }
    }
}
