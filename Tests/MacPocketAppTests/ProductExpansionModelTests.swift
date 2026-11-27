import XCTest
@testable import MacPocketApp
import MacPocketNetworkPolicy
import MacPocketTestSupport

@MainActor final class ProductExpansionModelTests: XCTestCase {
    private func defaults() -> UserDefaults {
        temporaryDefaults()
    }
    func testUnreadableNetworkRulesArePreservedUntilExplicitReset() throws {
        let defaults = defaults(), corrupt = Data("invalid-policy".utf8)
        defaults.set(corrupt, forKey: "MacPocket.internetControl.policy")
        let model = InternetControlModel(defaults: defaults)
        XCTAssertFalse(model.policyReadable)
        XCTAssertEqual(defaults.data(forKey: "MacPocket.internetControl.policy"), corrupt)
        model.resetUnreadablePolicy()
        XCTAssertTrue(model.policyReadable)
        let repaired = try XCTUnwrap(defaults.data(forKey: "MacPocket.internetControl.policy"))
        XCTAssertTrue(try AppNetworkPolicy.decode(repaired).rules.isEmpty)
        XCTAssertFalse(model.policyApplied)
        defaults.set("invalid-type", forKey: "MacPocket.internetControl.policy")
        XCTAssertFalse(InternetControlModel(defaults: defaults).policyReadable)
        XCTAssertEqual(defaults.string(forKey: "MacPocket.internetControl.policy"), "invalid-type")
    }
}
