import Foundation
import XCTest
@testable import MacPocketNetworkPolicy

final class NetworkPolicyTests: XCTestCase {
    func testPolicyMatchesSigningIdentityInsteadOfNameOrAnotherTeam() {
        let app = AppNetworkIdentity(identifier: "com.example.App", teamIdentifier: "TEAM1")
        let policy = AppNetworkPolicy(rules: [.init(identity: app, name: "Example")])
        XCTAssertEqual(policy.action(for: app), .deny)
        XCTAssertEqual(policy.action(for: .init(identifier: app.identifier, teamIdentifier: "TEAM2")), .allow)
        XCTAssertEqual(policy.action(for: .init(identifier: "com.example.Other", teamIdentifier: "TEAM1")), .allow)
        XCTAssertEqual(policy.action(for: nil), .allow)
    }
    func testAdHocIdentityRequiresMatchingCodeHash() {
        let identity = AppNetworkIdentity(identifier: "example", teamIdentifier: nil, codeHash: "abc")
        let policy = AppNetworkPolicy(rules: [.init(identity: identity, name: "Example")])
        XCTAssertEqual(policy.action(for: identity), .deny)
        XCTAssertEqual(policy.action(for: .init(identifier: "example", teamIdentifier: nil, codeHash: "def")), .allow)
        XCTAssertEqual(policy.action(for: .init(identifier: "example", teamIdentifier: nil)), .allow)
    }
    func testDisabledRuleDoesNotBlockAndDenyWinsDuplicates() throws {
        let app = AppNetworkIdentity(identifier: "example", teamIdentifier: "TEAM")
        var deny = AppNetworkRule(identity: app, name: "Example"); deny.enabled = false
        XCTAssertEqual(AppNetworkPolicy(rules: [deny]).action(for: app), .allow)
        deny.enabled = true
        let policy = AppNetworkPolicy(rules: [.init(identity: app, name: "Example", action: .allow), deny])
        XCTAssertEqual(policy.action(for: app), .deny)
        XCTAssertThrowsError(try AppNetworkPolicy.decode(JSONEncoder().encode(policy)))
        let single = AppNetworkPolicy(rules: [deny])
        XCTAssertEqual(try AppNetworkPolicy.decode(JSONEncoder().encode(single)), single)
    }
    func testInvalidPolicyCannotBecomeAnEmptySuccessfulConfiguration() throws {
        XCTAssertThrowsError(try AppNetworkPolicy.decode(Data(repeating: 0, count: 262145)))
        let invalid = AppNetworkPolicy(rules: [.init(identity: .init(identifier: "", teamIdentifier: nil), name: "Invalid")])
        XCTAssertThrowsError(try AppNetworkPolicy.decode(JSONEncoder().encode(invalid)))
    }
    func testIdentityIsReadFromActualSignedExecutable() throws {
        let identity = try XCTUnwrap(ApplicationSigningIdentity.read(at: URL(fileURLWithPath: "/usr/bin/true")))
        XCTAssertFalse(identity.identifier.isEmpty)
        XCTAssertTrue(identity.teamIdentifier?.isEmpty == false || identity.codeHash?.isEmpty == false)
        XCTAssertNil(ApplicationSigningIdentity.read(at: URL(fileURLWithPath: "/does/not/exist")))
        XCTAssertNil(ApplicationSigningIdentity.read(auditToken: Data(repeating: 0, count: 1)))
    }
    func testSignedApplicationUpdateKeepsRuleIdentity() {
        let old = AppNetworkIdentity(identifier: "app", teamIdentifier: "TEAM", codeHash: "old")
        let updated = AppNetworkIdentity(identifier: "app", teamIdentifier: "TEAM", codeHash: "new")
        XCTAssertEqual(old, updated)
        XCTAssertEqual(AppNetworkPolicy(rules: [.init(identity: old, name: "App")]).action(for: updated), .deny)
    }

}
