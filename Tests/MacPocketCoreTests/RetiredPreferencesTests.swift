import MacPocketTestSupport
import XCTest
@testable import MacPocketCore

final class RetiredPreferencesTests: XCTestCase {
    func testDataOfRemovedFeaturesIsDeletedAndEverythingElseKept() {
        let defaults = temporaryDefaults()
        defaults.set(Data("layouts".utf8), forKey: "MacPocket.workspaces")
        defaults.set(true, forKey: "MacPocket.modules.workspaces.available")
        defaults.set(["org.example.App": "owner/app"], forKey: "MacPocket.updateCenter.repositories")
        defaults.set(true, forKey: PocketModule.clipboard.availabilityKey)
        RetiredPreferences.remove(from: defaults)
        XCTAssertNil(defaults.object(forKey: "MacPocket.workspaces"))
        XCTAssertNil(defaults.object(forKey: "MacPocket.modules.workspaces.available"))
        XCTAssertNil(defaults.object(forKey: "MacPocket.updateCenter.repositories"))
        XCTAssertEqual(defaults.object(forKey: PocketModule.clipboard.availabilityKey) as? Bool, true)
        RetiredPreferences.remove(from: defaults)
        XCTAssertEqual(defaults.object(forKey: PocketModule.clipboard.availabilityKey) as? Bool, true, "running again is harmless")
    }

    func testNoCurrentModuleUsesARetiredKey() {
        let current = Set(PocketModule.allCases.map(\.availabilityKey))
        XCTAssertTrue(current.isDisjoint(with: RetiredPreferences.keys))
    }
}
