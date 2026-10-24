/// Rising-edge detector for one modifier key. Seed it with the state at drag go-live
/// so a key already held (e.g. Shift from a multi-select) never triggers.
public struct ModifierEdge {
    private var down: Bool

    public init(initiallyDown: Bool) {
        down = initiallyDown
    }

    /// Returns true only when the key goes from up to down.
    public mutating func update(down now: Bool) -> Bool {
        defer { down = now }
        return now && !down
    }
}
