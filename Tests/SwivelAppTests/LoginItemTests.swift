import ServiceManagement
import Testing
@testable import Swivel

// Pure mapping only: tests never register or unregister a real login item.
@Test(arguments: [
    (SMAppService.Status.enabled, true, LoginItem.Action.unregister),
    (.notRegistered, false, .register),
    (.notFound, false, .register),  // a fresh bundle (OV4)
    (.requiresApproval, false, .openLoginItems),
])
func loginItemStatusMapsToCheckAndClick(status: SMAppService.Status, checked: Bool, action: LoginItem.Action) {
    #expect(LoginItem.isChecked(status) == checked)
    #expect(LoginItem.action(for: status) == action)
}

private struct Refused: Error {}

// M7 AC 12: a thrown register/unregister shows one short alert, then the check mark is re-read.
@MainActor @Test(arguments: [(SMAppService.Status.enabled, LoginItem.Action.unregister), (.notRegistered, .register)])
func failedToggleAlertsOnceAndRefreshes(status: SMAppService.Status, expected: LoginItem.Action) {
    var ran: [LoginItem.Action] = [], alerts: [String] = []
    let item = LoginItem(status: { status }, run: { ran.append($0); throw Refused() }, alert: { alerts.append($0) })
    item.menuItem.state = status == .enabled ? .off : .on  // stale, so only a refresh fixes it
    item.toggle()
    #expect(ran == [expected])
    #expect(alerts == ["Couldn't change Open at Login."])
    #expect(item.menuItem.state == (status == .enabled ? .on : .off))
}

@MainActor @Test func successfulToggleShowsNoAlert() {
    var alerts: [String] = []
    var status = SMAppService.Status.notRegistered
    let item = LoginItem(status: { status }, run: { _ in status = .enabled }, alert: { alerts.append($0) })
    item.toggle()
    #expect(alerts.isEmpty)
    #expect(item.menuItem.state == .on)
    #expect(item.isOn)
}

// AC 11: translocated, the item is disabled and never registers.
@MainActor @Test func disabledLoginItemNeverRuns() {
    var ran = 0
    let item = LoginItem(status: { .notRegistered }, run: { _ in ran += 1 }, alert: { _ in })
    item.disabled = true
    item.toggle()
    #expect(ran == 0)
    #expect(item.menuItem.isEnabled == false)
}
