import XCTest
@testable import MacPocketCore

final class CleanupExpansionTests: StorageFixtureCase {
    private func scan(_ home: URL, now: Date = Date()) async throws -> CleanupReport {
        try await CleanupScanner().scan(CleanupCatalog.targets(home: home), now: now, control: control())
    }

    private func report(_ report: CleanupReport, _ id: CleanupTargetID) throws -> CleanupTargetReport {
        try XCTUnwrap(report.targets.first { $0.id == id })
    }

    private func forged(_ url: URL, root: URL, target id: CleanupTargetID) throws -> CleanupItem {
        CleanupItem(targetID: id, url: url, root: root, identity: try FileIdentity.read(url), measurement: StorageMeasurement(),
                    safety: .safe, preselected: true, warning: nil, isPackage: false, lastUsed: Date())
    }

    func testAppCachesAreListedByNameWithTheAppInTheLabel() async throws {
        let home = try fixture()
        try write(home.appendingPathComponent("Library/Application Support/Slack/Cache/data_0"), bytes: 50_000)
        try write(home.appendingPathComponent("Library/Application Support/Slack/Local Storage/leveldb/000003.log"), bytes: 9_000)
        try write(home.appendingPathComponent("Library/Application Support/discord/GPUCache/index"), bytes: 20_000)
        let chat = try report(try await scan(home), .communicationCaches)
        XCTAssertEqual(Set(chat.items.compactMap(\.label)), ["Slack › Cache", "discord › GPUCache"],
                       "Only cache folders, never the app's own data such as Local Storage")
    }

    func testSeparatelyManagedDataIsListedButNeverSelectedOrRemovable() async throws {
        let home = try fixture()
        let backups = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let backup = try write(backups.appendingPathComponent("00008030-ABC/Manifest.db"), bytes: 400_000)
        let full = try await scan(home)
        let separate = try report(full, .phoneBackups)
        XCTAssertEqual(separate.target.group, .separate)
        XCTAssertEqual(separate.items.count, 1)
        XCTAssertTrue(separate.items.allSatisfy { !$0.preselected })
        XCTAssertEqual(full.bytes, full.targets.filter { $0.target.group != .separate }.reduce(0) { $0 + $1.bytes },
                       "The cleanup total excludes separately managed data")
        let item = try forged(backup.deletingLastPathComponent(), root: backups, target: .phoneBackups)
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(item, targets: CleanupCatalog.targets(home: home))) {
            XCTAssertEqual($0 as? CleanupError, .managedSeparately)
        }
    }

    func testInstallersListOnlyInstallerFilesAndEachItemIsCountedOnce() async throws {
        let home = try fixture()
        let downloads = home.appendingPathComponent("Downloads")
        for name in ["Tool.dmg", "Tool.PKG", "notes.txt"] { try write(downloads.appendingPathComponent(name), bytes: 80_000) }

        let recent = try await scan(home)
        XCTAssertEqual(Set(try report(recent, .installers).items.map(\.name)), ["Tool.dmg", "Tool.PKG"], "Extension match ignores case")
        XCTAssertTrue(try report(recent, .oldDownloads).items.isEmpty, "Nothing is old yet")

        // 200 days later every file is also an old download; the first listed target (old downloads) owns them.
        let later = try await scan(home, now: Date().addingTimeInterval(200 * 86_400))
        XCTAssertEqual(Set(try report(later, .oldDownloads).items.map(\.name)), ["Tool.dmg", "Tool.PKG", "notes.txt"])
        XCTAssertTrue(try report(later, .installers).items.isEmpty)
        XCTAssertEqual(later.itemCount, 3, "No double counting in the total")

        let targets = CleanupCatalog.targets(home: home)
        let text = try forged(downloads.appendingPathComponent("notes.txt"), root: downloads, target: .installers)
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(text, targets: targets)) {
            XCTAssertEqual($0 as? CleanupError, .excluded)
        }
    }

    func testProtectedItemsAreRefusedByThePolicyAndTheService() async throws {
        let home = try fixture()
        let cache = try write(home.appendingPathComponent("Library/Caches/com.example.Keep/data"), bytes: 10_000)
        let root = home.appendingPathComponent("Library/Caches")
        let item = try forged(cache.deletingLastPathComponent(), root: root, target: .userCaches)
        let targets = CleanupCatalog.targets(home: home)
        XCTAssertNoThrow(try CleanupRemovalPolicy.validate(item, targets: targets))
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(item, targets: targets, protectedPaths: [item.url.path])) {
            XCTAssertEqual($0 as? CleanupError, .protected)
        }
        let results = await CleanupService().moveToTrash([item], targets: targets, protectedPaths: [item.url.path])
        XCTAssertNil(results.first?.trashURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path), "A protected item is never moved")
    }

    func testProtectionSurvivesRelaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CleanupProtectionTests-\(UUID().uuidString)"))
        var protection = CleanupProtection.load(from: defaults)
        XCTAssertTrue(protection.paths.isEmpty)
        protection.toggle("/Users/a/Library/Caches/x")
        protection.save(to: defaults)
        XCTAssertTrue(CleanupProtection.load(from: defaults).contains("/Users/a/Library/Caches/x"))
        protection.toggle("/Users/a/Library/Caches/x")
        XCTAssertFalse(protection.contains("/Users/a/Library/Caches/x"))
    }
}
