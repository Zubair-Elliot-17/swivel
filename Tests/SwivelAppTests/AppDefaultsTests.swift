import Testing
@testable import Swivel

// Q2: QA runs never read or write the user's dev.zubair.swivel settings.
@Test func qaModeUsesItsOwnSuite() {
    #expect(AppDefaults.suiteName(environment: ["SWIVEL_QA": "1"]) == "dev.zubair.swivel.qa")
    #expect(AppDefaults.suiteName(environment: [:]) == nil)
    #expect(AppDefaults.suiteName(environment: ["SWIVEL_QA": "0"]) == nil)
}
