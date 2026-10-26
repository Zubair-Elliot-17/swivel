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
