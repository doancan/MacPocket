import XCTest
@testable import MacPocketApp
import MacPocketNetworkPolicy

@MainActor final class ProductExpansionModelTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "MacPocket.ProductExpansionModelTests." + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
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
    func testRepositoryEditsAreValidatedAndIsolatedFromOtherModels() {
        let first = IndependentUpdateCenterModel(defaults: defaults()), second = IndependentUpdateCenterModel(defaults: defaults())
        XCTAssertTrue(first.saveRepository(for: "org.example.App", value: "owner/app"))
        XCTAssertFalse(first.saveRepository(for: "org.example.App", value: "https://example.com/owner/app"))
        XCTAssertEqual(first.repositories["org.example.App"], "owner/app")
        XCTAssertTrue(second.repositories.isEmpty)
        XCTAssertTrue(first.saveRepository(for: "org.example.App", value: nil))
        XCTAssertTrue(first.repositories.isEmpty)
    }
}
