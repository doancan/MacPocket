import MacPocketTestSupport
import XCTest

final class TemporaryDefaultsTests: XCTestCase {
    func testStoreLivesOutsideUserPreferencesAndIsDeletedOnRemove() throws {
        let store = try TemporaryDefaults()
        store.defaults.set(42, forKey: "value")
        XCTAssertTrue(store.defaults.synchronize())
        let preferences = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferences.appendingPathComponent(store.suiteName + ".plist").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.suiteName + ".plist"), "the plist sits in the store's own folder")
        XCTAssertEqual(try store.reopen().integer(forKey: "value"), 42)
        try store.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: (store.suiteName as NSString).deletingLastPathComponent))
    }

    func testEachStoreStartsEmpty() throws {
        let first = temporaryDefaults(), second = temporaryDefaults()
        first.set(true, forKey: "flag")
        XCTAssertNil(second.object(forKey: "flag"))
    }
}
