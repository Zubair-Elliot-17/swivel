import AppKit
import SwiftUI
import SwivelCore

/// Whether the welcome window was shown; only a real Bool true counts (junk reads as not seen).
enum WelcomeSetting {
    static let key = "welcomeSeen"

    static func read(_ defaults: UserDefaults) -> Bool { defaults.object(forKey: key) as? Bool == true }
    static func write(_ seen: Bool, to defaults: UserDefaults) { defaults.set(seen, forKey: key) }
}

enum Launch {
    /// Gatekeeper runs a quarantined app opened in place from a random read-only path.
    static func isTranslocated(_ bundlePath: String) -> Bool { bundlePath.contains("/AppTranslocation/") }

    /// Show at launch the first time, or every time while translocated (seen is then not recorded).
    /// QA runs never read or write the flag.
    static func welcomeAtLaunch(_ defaults: UserDefaults, qa: Bool, translocated: Bool) -> Bool {
        guard !qa else { return false }
        if translocated { return true }
        guard !WelcomeSetting.read(defaults) else { return false }
        WelcomeSetting.write(true, to: defaults)
        return true
    }
}

/// Live state the welcome view shows; the app delegate feeds the tap line and wires the actions.
@MainActor
final class WelcomeModel: ObservableObject {
    let translocated: Bool
    let loginDisabled: Bool
    @Published var tapLine = TapStatus.needsAccess.menuLine
    @Published var loginOn = false
    var enableTap: () -> Void = {}
    var toggleLogin: () -> Bool = { false }  // returns the new state
    var refreshLogin: () -> Void = {}  // re-reads the login item, which then sets loginOn
    var close: () -> Void = {}

    init(translocated: Bool, loginDisabled: Bool) {
        self.translocated = translocated
        self.loginDisabled = loginDisabled
    }
}

/// Esc closes it like Done; Cmd-W comes from the main menu's Close.
private final class WelcomeNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

/// The one welcome window; repeat opens bring it forward.
@MainActor
final class WelcomeWindow {
    private let defaults: UserDefaults
    let model: WelcomeModel
    private var keyObserver: NSObjectProtocol?

    init(defaults: UserDefaults, model: WelcomeModel) {
        self.defaults = defaults
        self.model = model
    }

    lazy var window: NSWindow = {
        let window = WelcomeNSWindow(contentViewController: NSHostingController(rootView: WelcomeView(model: model, defaults: defaults)))
        window.title = "Welcome to Swivel"
        window.styleMask.remove([.resizable, .miniaturizable])
        window.isReleasedWhenClosed = false
        window.center()
        model.close = { [weak window] in window?.close() }
        // Open at Login may have changed in System Settings while the window sat in the background.
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
            [model] _ in MainActor.assumeIsolated { model.refreshLogin() }
        }
        return window
    }()

    func show(loginOn: Bool) {
        model.loginOn = loginOn
        if !window.isVisible {  // fresh trigger key from the store
            window.contentViewController = NSHostingController(rootView: WelcomeView(model: model, defaults: defaults))
        }
        // An accessory app isn't active, so the window would open behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The checkbox follows every refresh of the login item: menu open, either toggle, the window becoming key.
    func bindLogin(_ login: LoginItem) {
        model.toggleLogin = {
            login.toggle()
            return login.isOn
        }
        model.refreshLogin = { login.refresh() }
        login.onChange = { [weak model] in model?.loginOn = $0 }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    let defaults: UserDefaults

    static func steps(_ keys: TriggerKeys) -> [String] {
        ["Drag a file.", "While dragging, tap \(TriggerSetting.label(keys)).", "Drop it on a format."]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.translocated {
                Text("Move Swivel to Applications, then open it again.")
                    .font(.headline)
            }
            Text("Convert a file in three steps:")
            ForEach(Array(Self.steps(TriggerSetting.read(defaults)).enumerated()), id: \.offset) { i, step in
                Text("\(i + 1). \(step)")
            }
            HStack(spacing: 4) {
                Text("Swivel lives in the menu bar:")
                Image(systemName: "circle.circle")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Swivel lives in the menu bar, as a circle icon.")
            Divider()
            Text("Or select files in Finder and tap the key. This needs Finder access.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Enable tap in Finder…") { model.enableTap() }
                Text(model.tapLine).foregroundStyle(.secondary)
            }
            Toggle("Open at Login", isOn: Binding(get: { model.loginOn }, set: { _ in model.loginOn = model.toggleLogin() }))
                .disabled(model.loginDisabled)
            HStack {
                Spacer()
                Button("Done") { model.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
