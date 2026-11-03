/// Shift/Ctrl trigger for one drag, seeded at mouse-down so a key already held never fires (D2).
/// An edge seen before the drag goes live stays pending and fires on the first live tick.
public struct DragTrigger {
    private var shift: ModifierEdge
    private var control: ModifierEdge
    private var pending = false

    public init(shift: Bool, control: Bool) {
        self.shift = ModifierEdge(initiallyDown: shift)
        self.control = ModifierEdge(initiallyDown: control)
    }

    /// Call once per poll tick; returns true when the wheel should open.
    public mutating func tick(shift: Bool, control: Bool, live: Bool) -> Bool {
        // Update both edges every tick; `||` would skip the second.
        let shiftEdge = self.shift.update(down: shift)
        let controlEdge = self.control.update(down: control)
        let edge = shiftEdge || controlEdge
        guard live else {
            if edge { pending = true }
            return false
        }
        defer { pending = false }
        return edge || pending
    }
}

/// Which modifier opens the wheel (setting `triggerKeys`); `both` is the default.
public enum TriggerKeys: String, CaseIterable, Sendable {
    case shift, control, both

    /// The stored value, cleaned: only an exact raw string counts, anything else is `both`.
    public init(raw: Any?) {
        self = (raw as? String).flatMap(TriggerKeys.init(rawValue:)) ?? .both
    }

    /// Keys as DragTrigger should see them: a disabled key reads up.
    public func drag(shift: Bool, control: Bool) -> (shift: Bool, control: Bool) {
        (shift && self != .control, control && self != .shift)
    }

    /// Keys as TapDetector should see them: a disabled key that is down counts as `other`, so it never taps.
    public func tap(shift: Bool, control: Bool, other: Bool) -> (shift: Bool, control: Bool, other: Bool) {
        let (s, c) = drag(shift: shift, control: control)
        return (s, c, other || (shift && !s) || (control && !c))
    }
}
