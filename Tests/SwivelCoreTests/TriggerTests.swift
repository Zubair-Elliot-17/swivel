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

/// flagsChanged samples (shift, control, other, time) and the Taps they should yield.
struct TapCase: CustomTestStringConvertible, Sendable {
    let name: String
    let events: [(Bool, Bool, Bool, Double)]
    let taps: [Tap]
    var testDescription: String { name }
}

let tapCases: [TapCase] = [
    TapCase(name: "shift tap", events: [(true, false, false, 1.0), (false, false, false, 1.25)], taps: [Tap(held: 0.25)]),
    TapCase(name: "ctrl tap", events: [(false, true, false, 2.0), (false, false, false, 2.5)], taps: [Tap(held: 0.5)]),
    TapCase(name: "shift then cmd", events: [(true, false, false, 1), (true, false, true, 1.1), (true, false, false, 1.2),
                                             (false, false, false, 1.3)], taps: []),
    TapCase(name: "cmd then shift", events: [(false, false, true, 1), (true, false, true, 1.1), (true, false, false, 1.2),
                                             (false, false, false, 1.3)], taps: []),
    TapCase(name: "cmd down, shift down, cmd up, shift up", events: [(false, false, true, 1), (true, false, true, 1.1),
                                                                     (true, false, false, 1.2), (false, false, false, 1.3)], taps: []),
    TapCase(name: "shift then ctrl together", events: [(true, false, false, 1), (true, true, false, 1.1), (false, true, false, 1.2),
                                                       (false, false, false, 1.3)], taps: []),
    TapCase(name: "option alone", events: [(false, false, true, 1), (false, false, false, 1.2)], taps: []),
    // Caps Lock toggles send flagsChanged with no trigger or other key change.
    TapCase(name: "caps lock then shift tap", events: [(false, false, false, 0.5), (true, false, false, 1), (false, false, false, 1.5)],
            taps: [Tap(held: 0.5)]),
    TapCase(name: "two taps", events: [(true, false, false, 1), (false, false, false, 1.25), (false, true, false, 2),
                                       (false, false, false, 2.5)], taps: [Tap(held: 0.25), Tap(held: 0.5)]),
    TapCase(name: "tainted press does not taint the next", events: [(true, false, true, 1), (false, false, false, 1.2),
                                                                    (true, false, false, 2), (false, false, false, 2.25)],
            taps: [Tap(held: 0.25)]),
    // Ctrl released first: the both-keys taint must stick once the set is back to one key.
    TapCase(name: "shift, ctrl, ctrl up, shift up", events: [(true, false, false, 1), (true, true, false, 1.1),
                                                             (true, false, false, 1.2), (false, false, false, 1.3)], taps: []),
    // Caps Lock after a tap must not replay the finished press.
    TapCase(name: "tap then caps lock", events: [(true, false, false, 1), (false, false, false, 1.25),
                                                 (false, false, false, 3)], taps: [Tap(held: 0.25)]),
]

@Test(arguments: tapCases)
func tapDetectorReportsBareTaps(_ c: TapCase) {
    var detector = TapDetector()
    let taps = c.events.compactMap { detector.update(shift: $0.0, control: $0.1, other: $0.2, time: $0.3) }
    #expect(taps == c.taps)
}

/// Inputs to TapRule, all passing; each case changes one field to its boundary.
struct RuleInput: Sendable {
    var held = 0.25, sinceKeyDown = 10.0, sinceLeftDown = 10.0, sinceRightDown = 10.0
    var buttonsDown = 0, dragLive = false, finderFrontmost = true
}

let ruleCases: [(String, RuleInput, String?)] = [
    ("all pass", RuleInput(), nil),
    ("held 0.7", RuleInput(held: 0.7), nil),
    ("held 0.701", RuleInput(held: 0.701), "held too long"),
    ("key just inside", RuleInput(sinceKeyDown: 0.751), nil),
    ("key at held + 0.5", RuleInput(sinceKeyDown: 0.75), "key typed"),
    ("left down just before press", RuleInput(sinceLeftDown: 0.251), nil),
    ("left down at press", RuleInput(sinceLeftDown: 0.25), "mouse clicked"),
    ("right down just before press", RuleInput(sinceRightDown: 0.251), nil),
    ("right down at press", RuleInput(sinceRightDown: 0.25), "mouse clicked"),
    ("right down during hold", RuleInput(sinceRightDown: 0.1), "mouse clicked"),
    ("button down", RuleInput(buttonsDown: 1), "button down"),
    ("drag live", RuleInput(dragLive: true), "drag live"),
    ("Finder not frontmost", RuleInput(finderFrontmost: false), "Finder not frontmost"),
]

@Test(arguments: ruleCases)
func tapRuleNamesTheFailingRule(_ name: String, _ i: RuleInput, _ expected: String?) {
    let rejection = TapRule.rejection(held: i.held, sinceKeyDown: i.sinceKeyDown, sinceLeftDown: i.sinceLeftDown,
                                      sinceRightDown: i.sinceRightDown, buttonsDown: i.buttonsDown,
                                      dragLive: i.dragLive, finderFrontmost: i.finderFrontmost)
    #expect(rejection == expected)
}

@Test(arguments: [
    (Int32(0), "Shift-tap: ready"),
    (-1744, "Shift-tap: allow Finder access"),
    (-1743, "Shift-tap: denied, see System Settings > Automation"),
    (-600, "Shift-tap: allow Finder access"),
])
func tapStatusFromPermission(_ code: Int32, _ line: String) {
    #expect(TapStatus(permission: code).menuLine == line)
}

@Test func nothingSelectedLine() {
    #expect(TapStatus.nothingSelected.menuLine == "Shift-tap: nothing selected")
}

/// Click wheel open for `elapsed` s: a keyDown since then means Finder took the keys, so the wheel hides.
@Test(arguments: [(0.5, 1.0, true), (1.0, 1.0, false), (1.001, 1.0, false), (0.0, 0.0, false)])
func keyTypedSinceOpen(_ sinceKeyDown: Double, _ elapsed: Double, _ typed: Bool) {
    #expect(TapRule.keyTyped(sinceKeyDown: sinceKeyDown, elapsed: elapsed) == typed)
}

/// Inputs to TapRule.lateRejection `elapsed` = 2 s after the tap, all passing; each case moves one field to its boundary.
struct LateInput: Sendable {
    var sinceKeyDown = 10.0, sinceLeftDown = 10.0, sinceRightDown = 10.0, buttonsDown = 0, finderFrontmost = true
}

let lateCases: [(String, LateInput, String?)] = [
    ("all pass", LateInput(), nil),
    ("key at tap", LateInput(sinceKeyDown: 2.0), nil),
    ("key after tap", LateInput(sinceKeyDown: 1.999), "key typed"),
    ("left down at tap", LateInput(sinceLeftDown: 2.0), nil),
    ("left down after tap", LateInput(sinceLeftDown: 1.999), "mouse clicked"),
    ("right down at tap", LateInput(sinceRightDown: 2.0), nil),
    ("right down after tap", LateInput(sinceRightDown: 1.999), "mouse clicked"),
    ("button down", LateInput(buttonsDown: 2), "button down"),
    ("Finder not frontmost", LateInput(finderFrontmost: false), "Finder not frontmost"),
]

@Test(arguments: lateCases)
func lateRuleNamesTheFailingRule(_ name: String, _ i: LateInput, _ expected: String?) {
    #expect(TapRule.lateRejection(elapsed: 2.0, sinceKeyDown: i.sinceKeyDown, sinceLeftDown: i.sinceLeftDown,
                                  sinceRightDown: i.sinceRightDown, buttonsDown: i.buttonsDown,
                                  finderFrontmost: i.finderFrontmost) == expected)
}
