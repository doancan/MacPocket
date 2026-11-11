import XCTest
@testable import MacPocketApp

@MainActor final class BluetoothMenuBarMigrationTests: XCTestCase {
    func testLegacyStandaloneItemFlagIsRead() throws {
        let suite = "MacPocket.BluetoothMigration." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(BluetoothBatteryService.legacyMenuBarItemRequested(defaults))
        let key = BluetoothBatteryService.Settings.storageKey
        defaults.set(try JSONSerialization.data(withJSONObject: ["lowBatteryAlerts": true, "threshold": 20, "showInMenuBar": true]), forKey: key)
        XCTAssertTrue(BluetoothBatteryService.legacyMenuBarItemRequested(defaults))
        defaults.set(try JSONSerialization.data(withJSONObject: ["lowBatteryAlerts": true, "threshold": 20, "showInMenuBar": false]), forKey: key)
        XCTAssertFalse(BluetoothBatteryService.legacyMenuBarItemRequested(defaults))
        // The settings struct still decodes the old payload (the dropped field is ignored).
        let decoded = try JSONDecoder().decode(BluetoothBatteryService.Settings.self, from: defaults.data(forKey: key)!)
        XCTAssertEqual(decoded.threshold, 20)
    }
}
