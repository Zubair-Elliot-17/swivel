import Testing
import SwivelCore

@Test func heldBeforeDragAndKeptHeldNeverTriggers() {
    var edge = ModifierEdge(initiallyDown: true)
    #expect(edge.update(down: true) == false)
    #expect(edge.update(down: true) == false)
}

@Test func heldThenReleasedThenPressedTriggers() {
    var edge = ModifierEdge(initiallyDown: true)
    #expect(edge.update(down: false) == false)
    #expect(edge.update(down: true) == true)
}

@Test func tapTriggersOnce() {
    var edge = ModifierEdge(initiallyDown: false)
    #expect(edge.update(down: false) == false)
    #expect(edge.update(down: true) == true)
    #expect(edge.update(down: false) == false)
    #expect(edge.update(down: false) == false)
}

@Test func holdingDoesNotRepeat() {
    var edge = ModifierEdge(initiallyDown: false)
    #expect(edge.update(down: true) == true)
    #expect(edge.update(down: true) == false)
    #expect(edge.update(down: true) == false)
}

@Test func secondTapTriggersAgain() {
    var edge = ModifierEdge(initiallyDown: false)
    #expect(edge.update(down: true) == true)
    #expect(edge.update(down: false) == false)
    #expect(edge.update(down: true) == true)
}
