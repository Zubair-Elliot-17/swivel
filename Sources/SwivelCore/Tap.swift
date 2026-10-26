/// A bare Shift or Ctrl press and release; `held` is in seconds.
public struct Tap: Equatable, Sendable {
    public let held: Double

    public init(held: Double) {
        self.held = held
    }
}

/// Turns flagsChanged samples into taps: from no modifiers to exactly Shift or Ctrl and back.
/// `other` is any non-trigger modifier (Cmd, Option, Fn); Caps Lock is not one.
public struct TapDetector {
    private var empty = true
    private var pressStart: Double?
    private var pressShift = false

    public init() {}

    public mutating func update(shift: Bool, control: Bool, other: Bool, time: Double) -> Tap? {
        defer { empty = !shift && !control && !other }
        if !shift && !control && !other {
            defer { pressStart = nil }
            return pressStart.map { Tap(held: time - $0) }
        }
        if empty && !other && shift != control {
            pressStart = time
            pressShift = shift
        } else if pressStart != nil && (other || shift == control || shift != pressShift) {
            pressStart = nil  // tainted: another modifier joined the press
        }
        return nil
    }
}

/// Decides whether a Tap was a deliberate bare tap and not part of typing, a click or a drag.
public enum TapRule {
    public static let maxHeld = 0.7
    public static let quietBeforeKey = 0.5

    /// nil when the tap counts; otherwise the first failing rule, for the log.
    public static func rejection(held: Double, sinceKeyDown: Double, sinceLeftDown: Double, sinceRightDown: Double,
                                 buttonsDown: Int, dragLive: Bool, finderFrontmost: Bool) -> String? {
        if held > maxHeld { return "held too long" }
        if sinceKeyDown <= held + quietBeforeKey { return "key typed" }
        if sinceLeftDown <= held || sinceRightDown <= held { return "mouse clicked" }
        if buttonsDown != 0 { return "button down" }
        if dragLive { return "drag live" }
        if !finderFrontmost { return "Finder not frontmost" }
        return nil
    }

    /// After the slow selection read, `elapsed` s after the tap: nil if the wheel may still open, else why not.
    public static func lateRejection(elapsed: Double, sinceKeyDown: Double, sinceLeftDown: Double, sinceRightDown: Double,
                                     buttonsDown: Int, finderFrontmost: Bool) -> String? {
        if keyTyped(sinceKeyDown: sinceKeyDown, elapsed: elapsed) { return "key typed" }
        if sinceLeftDown < elapsed || sinceRightDown < elapsed { return "mouse clicked" }
        if buttonsDown != 0 { return "button down" }
        if !finderFrontmost { return "Finder not frontmost" }
        return nil
    }

    /// Whether a key went down within the last `elapsed` seconds (since a tap or the wheel opening).
    public static func keyTyped(sinceKeyDown: Double, elapsed: Double) -> Bool {
        sinceKeyDown < elapsed
    }
}

/// Finder Automation state behind the "Shift-tap:" menu line.
public enum TapStatus: Equatable, Sendable {
    case ready, needsAccess, denied, nothingSelected

    /// From an AEDeterminePermissionToAutomateTarget result: noErr, -1743 denied, else not yet allowed.
    public init(permission: Int32) {
        switch permission {
        case 0: self = .ready
        case -1743: self = .denied
        default: self = .needsAccess
        }
    }

    public var menuLine: String {
        switch self {
        case .ready: "Shift-tap: ready"
        case .needsAccess: "Shift-tap: allow Finder access"
        case .denied: "Shift-tap: denied, see System Settings > Automation"
        case .nothingSelected: "Shift-tap: nothing selected"
        }
    }
}
