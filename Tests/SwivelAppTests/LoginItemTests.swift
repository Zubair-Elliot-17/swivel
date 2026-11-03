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
