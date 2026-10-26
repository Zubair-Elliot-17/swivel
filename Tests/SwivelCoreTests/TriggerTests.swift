import Testing
import SwivelCore

/// One drag: keys at mouse-down, then poll ticks of (shift, control, live), and the ticks that should fire.
struct DragCase: CustomTestStringConvertible, Sendable {
    let name: String
    let start: (shift: Bool, control: Bool)
    let ticks: [(Bool, Bool, Bool)]
    let fires: [Int]
    var testDescription: String { name }
}

let dragCases: [DragCase] = [
    DragCase(name: "held at mouse-down and kept", start: (true, false),
             ticks: [(true, false, false), (true, false, true), (true, false, true)], fires: []),
    DragCase(name: "edge before live fires once at go-live", start: (false, false),
             ticks: [(true, false, false), (true, false, false), (true, false, true), (true, false, true)], fires: [2]),
    DragCase(name: "edge after live", start: (false, false),
             ticks: [(false, false, true), (true, false, true), (true, false, true)], fires: [1]),
    DragCase(name: "press and release before live fires at go-live", start: (false, false),
             ticks: [(true, false, false), (false, false, false), (false, false, true), (false, false, true)], fires: [2]),
    DragCase(name: "never live", start: (false, false),
             ticks: [(true, false, false), (false, false, false), (true, false, false)], fires: []),
    DragCase(name: "second edge after release fires again", start: (false, false),
             ticks: [(true, false, true), (false, false, true), (true, false, true)], fires: [0, 2]),
    DragCase(name: "held at mouse-down, released, pressed fires", start: (true, false),
             ticks: [(false, false, true), (true, false, true)], fires: [1]),
    DragCase(name: "ctrl held at mouse-down and kept", start: (false, true),
             ticks: [(false, true, true), (false, true, true)], fires: []),
    DragCase(name: "ctrl edge before live", start: (false, false),
             ticks: [(false, true, false), (false, true, true)], fires: [1]),
    DragCase(name: "ctrl edge after live", start: (false, false),
             ticks: [(false, false, true), (false, true, true)], fires: [1]),
    DragCase(name: "ctrl second edge fires again", start: (false, false),
             ticks: [(false, true, true), (false, false, true), (false, true, true)], fires: [0, 2]),
]

@Test(arguments: dragCases)
func dragTriggerFires(_ c: DragCase) {
    var trigger = DragTrigger(shift: c.start.shift, control: c.start.control)
    let fired = c.ticks.enumerated().filter { trigger.tick(shift: $1.0, control: $1.1, live: $1.2) }.map(\.offset)
    #expect(fired == c.fires)
}
