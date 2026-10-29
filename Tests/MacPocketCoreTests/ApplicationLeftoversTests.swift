import XCTest
@testable import MacPocketCore

final class ApplicationLeftoversTests: XCTestCase {
    func testCandidatesExcludeInstalledAppleSharedAndSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for id in ["com.example.removed", "com.example.installed", "com.example.installed.Helper", "com.apple.system", "Shared Vendor"] {
            try FileManager.default.createDirectory(at: cache.appendingPathComponent(id), withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("com.example.alias"), withDestinationURL: cache.appendingPathComponent("com.example.removed"))
        let rows = try await ApplicationLeftoverScanner().scan(installedIDs: ["com.example.installed"], home: root)
        XCTAssertEqual(rows.map(\.bundleID), ["com.example.removed"])
        XCTAssertNoThrow(try rows[0].request.validate())
    }

    func testSymlinkedSourceFolderIsNotScanned() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("com.example.removed"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Library/Caches"), withDestinationURL: outside)
        let rows = try await ApplicationLeftoverScanner().scan(installedIDs: [], home: root)
        XCTAssertTrue(rows.isEmpty)
    }
    func testPreferencesRequiresPlistAndSavedStateRequiresSuffix() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = root.appendingPathComponent("Library/Preferences")
        let state = root.appendingPathComponent("Library/Saved Application State")
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: preferences.appendingPathComponent("com.example.backup.json"))
        try Data().write(to: preferences.appendingPathComponent("com.example.removed.plist"))
        try FileManager.default.createDirectory(at: state.appendingPathComponent("com.example.unrelated"), withIntermediateDirectories: true)
        let rows = try await ApplicationLeftoverScanner().scan(installedIDs: [], home: root)
        XCTAssertEqual(rows.map(\.bundleID), ["com.example.removed"])
    }
}
