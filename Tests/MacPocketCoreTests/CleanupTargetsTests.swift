import XCTest
@testable import MacPocketCore

final class CleanupTargetsTests: StorageFixtureCase {
    /// A fake home with every cleanup location populated.
    private func fakeHome() throws -> URL {
        let home = try fixture()
        try write(home.appendingPathComponent("Library/Caches/com.example.Editor/Cache.db"), bytes: 300_000)
        try write(home.appendingPathComponent("Library/Caches/com.example.Viewer/data"), bytes: 120_000)
        try write(home.appendingPathComponent("Library/Caches/com.apple.Safari/WebKit"), bytes: 90_000)
        try write(home.appendingPathComponent("Library/Caches/GeoServices/tiles"), bytes: 40_000)
        try write(home.appendingPathComponent("Library/Caches/Homebrew/downloads/abc--wget.bottle.tar.gz"), bytes: 500_000)
        try write(home.appendingPathComponent("Library/Caches/pip/http/cache"), bytes: 70_000)
        try write(home.appendingPathComponent("Library/Caches/.DS_Store"), bytes: 6_000)
        try write(home.appendingPathComponent("Library/Logs/DiagnosticReports/crash.ips"), bytes: 20_000)
        try write(home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-xyz/Build/obj.o"), bytes: 800_000)
        try write(home.appendingPathComponent("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist"), bytes: 30_000)
        try write(home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/18.0 (22A)/Symbols/dyld"), bytes: 600_000)
        try write(home.appendingPathComponent("Library/Developer/CoreSimulator/Caches/dyld/cache"), bytes: 200_000)
        try write(home.appendingPathComponent(".npm/_cacache/content-v2/sha512/aa"), bytes: 150_000)
        try write(home.appendingPathComponent(".npm/_logs/debug.log"), bytes: 5_000)
        try write(home.appendingPathComponent(".gradle/caches/modules-2/files"), bytes: 100_000)
        try write(home.appendingPathComponent(".Trash/old.zip"), bytes: 60_000)
        return home
    }

    private func scan(_ home: URL, running: [RunningApplicationInfo] = [], now: Date = Date(),
                      downloadsAge: Int = 90) async throws -> CleanupReport {
        try await CleanupScanner().scan(CleanupCatalog.targets(home: home, downloadsAgeDays: downloadsAge),
                                        running: running, now: now, control: control())
    }

    private func target(_ report: CleanupReport, _ id: CleanupTargetID) throws -> CleanupTargetReport {
        try XCTUnwrap(report.targets.first { $0.id == id })
    }

    func testCatalogRootsLiveInsideInjectedHome() throws {
        let home = try fixture()
        let targets = CleanupCatalog.targets(home: home)
        XCTAssertEqual(Set(targets.map(\.id)), Set(CleanupTargetID.allCases))
        for target in targets {
            for root in target.roots { XCTAssertTrue(root.path.hasPrefix(home.path + "/"), "\(root.path) escapes the home") }
        }
        XCTAssertFalse(targets.first { $0.id == .xcodeArchives }!.preselected)
        XCTAssertFalse(targets.first { $0.id == .oldDownloads }!.preselected)
        XCTAssertEqual(targets.first { $0.id == .oldDownloads }?.safety, .review)
    }

    func testDiscoversItemsPerTargetOnFakeHome() async throws {
        let home = try fakeHome()
        let report = try await scan(home)
        let caches = try target(report, .userCaches)
        XCTAssertEqual(Set(caches.items.map(\.name)), ["com.example.Editor", "com.example.Viewer", "com.apple.Safari", "GeoServices"],
                       "Package manager caches belong to their own targets and .DS_Store is ignored")
        XCTAssertEqual(caches.items.first?.name, "com.example.Editor", "Items are sorted by size")
        XCTAssertEqual(try target(report, .homebrew).items.map(\.name), ["downloads"])
        XCTAssertEqual(try target(report, .pip).items.map(\.name), ["http"])
        XCTAssertEqual(try target(report, .npm).items.map(\.name), ["_cacache"], "Only npm's cache, never its logs")
        XCTAssertEqual(try target(report, .gradle).items.map(\.name), ["modules-2"])
        XCTAssertEqual(try target(report, .derivedData).items.map(\.name), ["App-xyz"])
        XCTAssertEqual(try target(report, .deviceSupport).items.map(\.name), ["18.0 (22A)"])
        XCTAssertEqual(try target(report, .simulatorCaches).items.map(\.name), ["dyld"])
        XCTAssertEqual(try target(report, .trash).items.map(\.name), ["old.zip"])
        XCTAssertEqual(try target(report, .yarn).state, .missing)
        XCTAssertEqual(try target(report, .mailDownloads).state, .missing)

        let derived = try XCTUnwrap(try target(report, .derivedData).items.first)
        XCTAssertGreaterThanOrEqual(derived.bytes, 800_000)
        XCTAssertEqual(derived.measurement.fileCount, 1)
        XCTAssertTrue(derived.preselected)
        XCTAssertEqual(derived.root.path, home.appendingPathComponent("Library/Developer/Xcode/DerivedData").path)

        let archive = try XCTUnwrap(try target(report, .xcodeArchives).items.first)
        XCTAssertEqual(archive.safety, .review)
        XCTAssertFalse(archive.preselected, "Archives are shown but never preselected")
    }

    func testSystemCachesNeedReview() async throws {
        let report = try await scan(try fakeHome())
        let caches = try target(report, .userCaches)
        for name in ["com.apple.Safari", "GeoServices"] {
            let item = try XCTUnwrap(caches.items.first { $0.name == name })
            XCTAssertEqual(item.safety, .review)
            XCTAssertFalse(item.preselected)
            XCTAssertEqual(item.warning, CleanupRules.systemWarning)
        }
        let normal = try XCTUnwrap(caches.items.first { $0.name == "com.example.Viewer" })
        XCTAssertEqual(normal.safety, .safe)
        XCTAssertTrue(normal.preselected)
        XCTAssertNil(normal.warning)
    }

    func testRunningApplicationCachesAreWarnedAndNotPreselected() async throws {
        let running = [RunningApplicationInfo(bundleID: "com.example.editor", name: "Editor"),
                       RunningApplicationInfo(bundleID: "com.apple.dt.Xcode", name: "Xcode")]
        let report = try await scan(try fakeHome(), running: running)
        let editor = try XCTUnwrap(try target(report, .userCaches).items.first { $0.name == "com.example.Editor" })
        XCTAssertFalse(editor.preselected)
        XCTAssertEqual(editor.warning, CleanupRules.runningWarning)
        let viewer = try XCTUnwrap(try target(report, .userCaches).items.first { $0.name == "com.example.Viewer" })
        XCTAssertTrue(viewer.preselected)
        let derived = try XCTUnwrap(try target(report, .derivedData).items.first)
        XCTAssertFalse(derived.preselected, "Xcode is running")
        XCTAssertEqual(derived.warning, "Xcode açık. Temizlemeden önce kapatman önerilir.")
    }

    func testRunningOwnerMatching() {
        let apps = [RunningApplicationInfo(bundleID: "org.mozilla.firefox", name: "Firefox"),
                    RunningApplicationInfo(bundleID: nil, name: "Spotify")]
        XCTAssertNotNil(CleanupRules.runningOwner(of: "org.mozilla.firefox", running: apps))
        XCTAssertNotNil(CleanupRules.runningOwner(of: "org.mozilla.firefox.helper", running: apps))
        XCTAssertNotNil(CleanupRules.runningOwner(of: "Firefox", running: apps))
        XCTAssertNotNil(CleanupRules.runningOwner(of: "spotify", running: apps))
        XCTAssertNil(CleanupRules.runningOwner(of: "org.mozilla.firefoxdev", running: apps), "Prefix matches stop at a dot")
        XCTAssertNil(CleanupRules.runningOwner(of: "com.other", running: apps))
        XCTAssertNil(CleanupRules.runningOwner(of: "", running: [RunningApplicationInfo(bundleID: "", name: "")]))
    }

    func testOldDownloadsOnlyListsItemsPastTheAge() async throws {
        let home = try fixture()
        let now = Date().addingTimeInterval(200 * 86_400)  // Everything created now is 200 days old then.
        try write(home.appendingPathComponent("Downloads/old.dmg"), bytes: 50_000)
        let recent = try write(home.appendingPathComponent("Downloads/recent.pdf"), bytes: 50_000)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-86_400)], ofItemAtPath: recent.path)
        // A folder counts as recent when any file inside is recent.
        let nested = try write(home.appendingPathComponent("Downloads/project/inner/new.txt"), bytes: 10_000)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3_600)], ofItemAtPath: nested.path)
        let report = try await scan(home, now: now)
        let downloads = try target(report, .oldDownloads)
        XCTAssertEqual(downloads.items.map(\.name), ["old.dmg"])
        XCTAssertFalse(downloads.items[0].preselected)
        XCTAssertEqual(downloads.items[0].safety, .review)
    }

    func testSymlinksAreNeverFollowedOrOffered() async throws {
        let home = try fakeHome()
        let outside = try fixture()
        try write(outside.appendingPathComponent("precious"), bytes: 1_000_000)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/linked"), withDestinationURL: outside)
        // A symlinked target root is reported, not scanned.
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/Yarn"), withDestinationURL: outside)
        let report = try await scan(home)
        XCTAssertNil(try target(report, .userCaches).items.first { $0.name == "linked" })
        XCTAssertEqual(try target(report, .yarn).state, .symbolicLink)
        XCTAssertTrue(try target(report, .yarn).items.isEmpty)
    }

    func testUnreadableRootIsReported() async throws {
        let home = try fakeHome()
        let logs = home.appendingPathComponent("Library/Logs")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: logs.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: logs.path) }
        let report = try await scan(home)
        guard case .inaccessible = try target(report, .userLogs).state else { return XCTFail("Expected inaccessible state") }
    }

    // MARK: Removal policy

    private func fakeMove(into trash: URL) -> @Sendable (URL) throws -> URL {
        { url in
            let destination = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    func testPermanentCleanupFreesTheItemsAndRefusesTheSameInvalidOnes() async throws {
        let home = try fakeHome()
        let report = try await scan(home)
        let targets = report.targets.map(\.target)
        let viewer = try XCTUnwrap(try target(report, .userCaches).items.first { $0.name == "com.example.Viewer" })
        let derived = try XCTUnwrap(try target(report, .derivedData).items.first)
        let trashItem = try XCTUnwrap(try target(report, .trash).items.first)
        let service = CleanupService(move: { _ in XCTFail("permanent cleanup must not use the Trash"); throw FileServiceError.unreadable })
        let results = await service.remove([viewer, derived, trashItem], targets: targets, mode: .deletePermanently)
        XCTAssertEqual(results.map(\.succeeded), [true, true, false])
        XCTAssertEqual(results.prefix(2).map(\.mode), [.deletePermanently, .deletePermanently])
        XCTAssertNil(results[0].trashURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: viewer.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: derived.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashItem.url.path), "Trash items are only removed by emptying the Trash")
        XCTAssertEqual(results[2].error, CleanupError.trashItem.errorDescription)
        // A second scan proves the bytes are really gone, not merely hidden.
        let after = try await scan(home)
        XCTAssertNil(try target(after, .userCaches).items.first { $0.name == "com.example.Viewer" })
        XCTAssertTrue(try target(after, .derivedData).items.isEmpty)
    }

    func testValidItemsMoveAndInvalidAreRefused() async throws {
        let home = try fakeHome()
        let report = try await scan(home)
        let targets = report.targets.map(\.target)
        let viewer = try XCTUnwrap(try target(report, .userCaches).items.first { $0.name == "com.example.Viewer" })
        let derived = try XCTUnwrap(try target(report, .derivedData).items.first)
        let trashItem = try XCTUnwrap(try target(report, .trash).items.first)
        let fakeTrash = try fixture()
        let service = CleanupService(move: fakeMove(into: fakeTrash))
        let results = await service.moveToTrash([viewer, derived, trashItem], targets: targets)
        XCTAssertEqual(results.count, 3)
        XCTAssertNotNil(results[0].trashURL)
        XCTAssertNotNil(results[1].trashURL)
        XCTAssertNil(results[2].trashURL)
        XCTAssertEqual(results[2].error, CleanupError.trashItem.errorDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: viewer.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashItem.url.path))
    }

    func testRefusesChangedOutsideNestedAndSymlinkedItems() async throws {
        let home = try fakeHome()
        let report = try await scan(home)
        let targets = report.targets.map(\.target)
        let item = try XCTUnwrap(try target(report, .userCaches).items.first { $0.name == "com.example.Viewer" })

        // Identity changed after the scan.
        try write(item.url.appendingPathComponent("data"), bytes: 10)
        let replaced = item.url.deletingLastPathComponent().appendingPathComponent("tmp-swap")
        try FileManager.default.moveItem(at: item.url, to: replaced)
        try FileManager.default.createDirectory(at: item.url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(item, targets: targets)) {
            XCTAssertEqual($0 as? FileServiceError, .changed)
        }

        func forged(_ url: URL, root: URL, target id: CleanupTargetID = .userCaches) throws -> CleanupItem {
            CleanupItem(targetID: id, url: url, root: root, identity: try FileIdentity.read(url), measurement: StorageMeasurement(),
                        safety: .safe, preselected: true, warning: nil, isPackage: false, lastUsed: Date())
        }
        let cachesRoot = home.appendingPathComponent("Library/Caches")
        // Outside every target.
        let documents = try write(home.appendingPathComponent("Documents/thesis.pdf"), bytes: 10)
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(try forged(documents, root: documents.deletingLastPathComponent()), targets: targets)) {
            XCTAssertEqual($0 as? CleanupError, .unknownTarget)
        }
        // A claimed root that is not the target's root (e.g. a package interior).
        let packageInterior = try write(home.appendingPathComponent("Library/Caches/Tool.app/Contents/Info.plist"), bytes: 10)
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(try forged(packageInterior, root: packageInterior.deletingLastPathComponent()),
                                                               targets: targets)) {
            XCTAssertEqual($0 as? CleanupError, .unknownTarget)
        }
        // Nested deeper than a direct child.
        let nested = home.appendingPathComponent("Library/Caches/com.example.Editor/Cache.db")
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(try forged(nested, root: cachesRoot), targets: targets)) {
            XCTAssertEqual($0 as? CleanupError, .notDirectChild)
        }
        // Excluded names stay excluded even if forged.
        let homebrew = home.appendingPathComponent("Library/Caches/Homebrew")
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(try forged(homebrew, root: cachesRoot), targets: targets)) {
            XCTAssertEqual($0 as? CleanupError, .excluded)
        }
        let npmLogs = home.appendingPathComponent(".npm/_logs")
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(try forged(npmLogs, root: home.appendingPathComponent(".npm"), target: .npm),
                                                               targets: targets)) {
            XCTAssertEqual($0 as? CleanupError, .excluded)
        }
        // A symlink child.
        let outside = try fixture()
        let link = cachesRoot.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(try forged(link, root: cachesRoot), targets: targets)) {
            XCTAssertEqual($0 as? FileServiceError, .symbolicLink)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRootReplacedBySymlinkAfterScanIsRefused() async throws {
        let home = try fakeHome()
        let report = try await scan(home)
        let targets = report.targets.map(\.target)
        let item = try XCTUnwrap(try target(report, .derivedData).items.first)
        // Swap DerivedData for a symlink to a folder holding an identically named item.
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let elsewhere = try fixture()
        try FileManager.default.moveItem(at: derivedData, to: elsewhere.appendingPathComponent("DerivedData"))
        try FileManager.default.createSymbolicLink(at: derivedData, withDestinationURL: elsewhere.appendingPathComponent("DerivedData"))
        XCTAssertThrowsError(try CleanupRemovalPolicy.validate(item, targets: targets)) {
            XCTAssertEqual($0 as? FileServiceError, .symbolicLink)
        }
    }

    // MARK: Emptying the Trash

    func testTrashEmptierRemovesOnlyValidatedTrashChildren() async throws {
        let home = try fixture()
        let trash = try directory(home.appendingPathComponent(".Trash"))
        try write(trash.appendingPathComponent("file.zip"), bytes: 40_000)
        try write(trash.appendingPathComponent("folder/inner/a"), bytes: 40_000)
        let outside = try fixture()
        let precious = try write(outside.appendingPathComponent("precious"), bytes: 1_000)
        let preciousDir = try directory(outside.appendingPathComponent("dir"))
        try write(preciousDir.appendingPathComponent("keep"), bytes: 1_000)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("file-link"), withDestinationURL: precious)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("dir-link"), withDestinationURL: preciousDir)
        let report = try await scan(home)
        let items = try target(report, .trash).items
        XCTAssertEqual(Set(items.map(\.name)), ["file.zip", "folder"], "Symlinks in Trash are not listed")

        let emptier = TrashEmptier(home: home)
        let result = await emptier.empty(items)
        XCTAssertEqual(result.removed.count, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.appendingPathComponent("file.zip").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.appendingPathComponent("folder").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preciousDir.appendingPathComponent("keep").path))
        XCTAssertGreaterThan(result.removedBytes, 80_000)
    }

    func testTrashEmptierUnlinksSymlinkWithoutFollowing() throws {
        let home = try fixture()
        let trash = try directory(home.appendingPathComponent(".Trash"))
        let outside = try fixture()
        let precious = try directory(outside.appendingPathComponent("dir"))
        try write(precious.appendingPathComponent("keep"), bytes: 10)
        let link = trash.appendingPathComponent("dir-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: precious)
        let emptier = TrashEmptier(home: home)
        XCTAssertNoThrow(try emptier.validate(link, identity: try FileIdentity.read(link)))
        try FileManager.default.removeItem(at: link)
        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.appendingPathComponent("keep").path))
    }

    func testTrashEmptierRefusesEverythingOutsideTrash() async throws {
        let home = try fixture()
        let trash = try directory(home.appendingPathComponent(".Trash"))
        let nested = try write(trash.appendingPathComponent("folder/inner"), bytes: 10)
        let document = try write(home.appendingPathComponent("Documents/keep.txt"), bytes: 10)
        let changed = try write(trash.appendingPathComponent("changed"), bytes: 10)
        let staleIdentity = try FileIdentity.read(changed)
        try FileManager.default.removeItem(at: changed)
        try write(changed, bytes: 20)
        let removed = RemovalLog()
        let emptier = TrashEmptier(home: home) { removed.append($0) }
        XCTAssertThrowsError(try emptier.validate(nested, identity: try FileIdentity.read(nested))) {
            XCTAssertEqual($0 as? FileServiceError, .outsideScope)
        }
        XCTAssertThrowsError(try emptier.validate(document, identity: try FileIdentity.read(document))) {
            XCTAssertEqual($0 as? FileServiceError, .outsideScope)
        }
        XCTAssertThrowsError(try emptier.validate(changed, identity: staleIdentity)) {
            XCTAssertEqual($0 as? FileServiceError, .changed)
        }
        XCTAssertThrowsError(try emptier.validate(trash, identity: try FileIdentity.read(trash))) {
            XCTAssertEqual($0 as? FileServiceError, .outsideScope)
        }
        let dotDot = URL(fileURLWithPath: trash.path + "/..")
        XCTAssertThrowsError(try emptier.validate(dotDot, identity: try FileIdentity.read(home)))
        // A non-Trash item passed to empty() is refused before any removal.
        let forged = CleanupItem(targetID: .userCaches, url: document, root: document.deletingLastPathComponent(),
                                 identity: try FileIdentity.read(document), measurement: StorageMeasurement(), safety: .safe,
                                 preselected: true, warning: nil, isPackage: false, lastUsed: Date())
        let result = await emptier.empty([forged])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(removed.urls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.path))
    }

    func testTrashEmptierRefusesSymlinkedTrash() throws {
        let home = try fixture()
        let elsewhere = try fixture()
        let victim = try write(elsewhere.appendingPathComponent("victim"), bytes: 10)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".Trash"), withDestinationURL: elsewhere)
        let emptier = TrashEmptier(home: home) { _ in XCTFail("Nothing may be removed") }
        let viaLink = home.appendingPathComponent(".Trash/victim")
        XCTAssertThrowsError(try emptier.validate(viaLink, identity: try FileIdentity.read(victim))) {
            XCTAssertEqual($0 as? FileServiceError, .symbolicLink)
        }
    }
}

private final class RemovalLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
    var urls: [URL] { lock.withLock { storage } }
}
