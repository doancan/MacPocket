import AppIntents
import Foundation
import MacPocketCore
import XCTest
@testable import MacPocketApp

@MainActor
final class SystemDataIntentsTests: XCTestCase {
    private func fixture() throws -> (root: URL, environment: SystemDataEnvironment) {
        let base = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil).map { String(cString: $0) })
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-intent-\(UUID().uuidString)", directoryHint: .isDirectory)
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
        func write(_ relative: String, megabytes: Int) throws {
            let file = home.appending(path: relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: megabytes * 1_000_000).write(to: file)
        }
        try write("Library/Caches/Homebrew/pkg.tar", megabytes: 10)          // Safe
        try write(".cargo/registry/crate.bin", megabytes: 8)                  // Review
        let environment = SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system"),
                                                temporaryDirectory: home.appending(path: "tmp"), run: { _, _ in nil }, capacity: { nil })
        return (root, environment)
    }

    func testFreeSafeItemsRemovesOnlySafePasswordFreeItemsAndLeavesReviewItems() async throws {
        let (root, environment) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let result = await SystemDataIntentRunner.freeSafeItems(environment: environment, remover: SystemDataRemover(runCommand: { _, _ in (1, "unused") }),
                                                                 mode: .deletePermanently, runningBundleIDs: [])
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertGreaterThanOrEqual(result.freedBytes, 10_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.home.appending(path: "Library/Caches/Homebrew/pkg.tar").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: environment.home.appending(path: ".cargo/registry/crate.bin").path), "Review items are never touched")
    }

    func testFreeSafeItemsSkipsAnItemWhoseAppIsRunning() async throws {
        let (root, environment) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let browsers = environment.home.appending(path: "Library/Caches/Google/Chrome/Default/data.bin")
        try FileManager.default.createDirectory(at: browsers.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 6_000_000).write(to: browsers)
        let result = await SystemDataIntentRunner.freeSafeItems(environment: environment, remover: SystemDataRemover(runCommand: { _, _ in (1, "unused") }),
                                                                 mode: .deletePermanently, runningBundleIDs: ["com.google.Chrome"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: browsers.path), "Chrome is running, so its cache is left alone")
        XCTAssertEqual(result.removedCount, 1)
    }

    func testSizeIntentReportsTheScannedTotalOnThisMac() async throws {
        // Read-only: a real scan of this Mac through the actual intent.
        let outcome = try await SystemDataSizeIntent().perform()
        let bytes = try XCTUnwrap(outcome.value)
        XCTAssertGreaterThan(bytes, 0)
    }

    func testTheShortcutsProviderOffersBothActions() {
        XCTAssertEqual(SystemDataShortcuts.appShortcuts.count, 2)
    }
}

@MainActor
final class SystemDataMenuBarControllerTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "menubar-" + UUID().uuidString)! }

    func testTheItemAppearsWithTheLastScanAndDisappearsWhenSwitchedOff() throws {
        let store = defaults()
        let controller = SystemDataMenuBarController(statusBar: .system, defaults: store, openTool: {})
        defer { controller.remove() }
        controller.refresh()
        XCTAssertNil(controller.statusItem, "off by default")

        SystemDataSummary(date: Date(), systemDataBytes: 41_000_000_000, safeBytes: 3_000_000_000, freeBytes: 167_000_000_000, purgeableBytes: 0).save(to: store)
        store.set(SystemDataMenuBarStyle.systemData.rawValue, forKey: SystemDataMenuBarStyle.key)
        controller.refresh()
        let item = try XCTUnwrap(controller.statusItem)
        XCTAssertEqual(item.button?.title.trimmingCharacters(in: .whitespaces), 41_000_000_000.formatted(.byteCount(style: .file, spellsOutZero: false)))
        let tooltip = try XCTUnwrap(item.button?.toolTip)
        XCTAssertTrue(tooltip.contains("41") && tooltip.contains("167"), tooltip)
        XCTAssertFalse(tooltip.contains("\\"), "the numbers are interpolated, not printed as code: \(tooltip)")
        XCTAssertNotNil(item.menu)
        XCTAssertEqual(item.menu?.items.first?.title, String(localized: "Disk Röntgeni’ni Aç"))

        store.set(SystemDataMenuBarStyle.icon.rawValue, forKey: SystemDataMenuBarStyle.key)
        controller.refresh()
        XCTAssertEqual(controller.statusItem?.button?.title, "", "icon only")

        store.set(SystemDataMenuBarStyle.off.rawValue, forKey: SystemDataMenuBarStyle.key)
        controller.refresh()
        XCTAssertNil(controller.statusItem)
    }

    func testChoosingTheMenuItemOpensTheTool() throws {
        let store = defaults()
        let opened = Locked<Int>(0)
        let controller = SystemDataMenuBarController(statusBar: .system, defaults: store, openTool: { opened.mutate { $0 += 1 } })
        defer { controller.remove() }
        store.set(SystemDataMenuBarStyle.icon.rawValue, forKey: SystemDataMenuBarStyle.key)
        controller.refresh()
        let open = try XCTUnwrap(controller.statusItem?.menu?.items.first)
        _ = open.target?.perform(open.action, with: open)
        XCTAssertEqual(opened.value, 1)
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}

@MainActor
final class SystemDataExperienceTests: XCTestCase {
    private final class Capacity: @unchecked Sendable {
        private let lock = NSLock(); private var freeBytes: Int64
        init(_ value: Int64) { freeBytes = value }
        func set(_ value: Int64) { lock.withLock { freeBytes = value } }
        func read() -> VolumeCapacity { lock.withLock { VolumeCapacity(name: "Test", totalBytes: 500_000_000_000, availableBytes: freeBytes, importantAvailableBytes: freeBytes) } }
    }

    private func fixture(extraSafeMegabytes: Int = 10) throws -> (root: URL, environment: SystemDataEnvironment, capacity: Capacity) {
        let base = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil).map { String(cString: $0) })
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-ux-\(UUID().uuidString)", directoryHint: .isDirectory)
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
        if extraSafeMegabytes > 0 {
            let file = home.appending(path: "Library/Caches/Homebrew/pkg.tar")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: extraSafeMegabytes * 1_000_000).write(to: file)
        }
        let file = home.appending(path: ".cargo/registry/crate.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 8_000_000).write(to: file)
        let capacity = Capacity(100_000_000_000)
        let environment = SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system"), temporaryDirectory: home.appending(path: "tmp"),
                                                run: { _, _ in nil }, capacity: { capacity.read() })
        return (root, environment, capacity)
    }

    private func model(_ environment: SystemDataEnvironment, defaults: UserDefaults, root: URL) -> SystemDataViewModel {
        SystemDataViewModel(defaults: defaults, store: SystemDataHistoryStore(url: root.appending(path: "history.json")), environment: environment,
                            remover: SystemDataRemover(runCommand: { _, _ in (1, "unused") }), archiver: SystemDataArchiver(manifest: root.appending(path: "a.json")),
                            removalMode: { .deletePermanently }, summaryFile: nil)
    }

    private func scanned(_ model: SystemDataViewModel) async throws {
        model.startScan()
        for _ in 0..<400 { if model.report != nil, !model.isScanning { return }; try await Task.sleep(for: .milliseconds(50)) }
        XCTFail("the scan did not finish")
    }

    func testOneTapCleanSelectsOnlyCleanableSafeItemsShowsEveryCommandAndFreesSpaceAtOnce() async throws {
        let (root, environment, capacity) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "ux-" + UUID().uuidString)!
        let page = model(environment, defaults: defaults, root: root)
        try await scanned(page)
        XCTAssertEqual(page.cleanableNow.map(\.id), ["pkg.homebrew"], "the Review item is never offered to the one-tap button")

        page.cleanSafeNow()
        let preview = try XCTUnwrap(page.pendingPreview, "one tap leads straight to the confirmation")
        XCTAssertEqual(preview.lines.map(\.id), ["pkg.homebrew"])
        XCTAssertTrue(preview.lines[0].operations[0].hasPrefix("rm -rf -- "))
        XCTAssertTrue(FileManager.default.fileExists(atPath: environment.home.appending(path: "Library/Caches/Homebrew/pkg.tar").path), "nothing is deleted before the confirmation")

        let freeBefore = try XCTUnwrap(page.report?.freeBytes)
        capacity.set(freeBefore + 10_000_000)   // the disk now has what the removal gave back
        await page.confirmRemoval()
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.home.appending(path: "Library/Caches/Homebrew/pkg.tar").path))
        XCTAssertEqual(page.report?.freeBytes, freeBefore + 10_000_000, "free space updates without a rescan")
        XCTAssertTrue(page.cleanableNow.isEmpty)
        XCTAssertNotNil(page.statusMessage)
    }

    func testTheCleanButtonDoesNothingWhenNothingIsCleanable() async throws {
        let (root, environment, _) = try fixture(extraSafeMegabytes: 0); defer { try? FileManager.default.removeItem(at: root) }
        let page = model(environment, defaults: UserDefaults(suiteName: "ux-" + UUID().uuidString)!, root: root)
        try await scanned(page)
        XCTAssertTrue(page.cleanableNow.isEmpty)
        page.cleanSafeNow()
        XCTAssertNil(page.pendingPreview)
    }

    func testThePageRemembersTabSortAndOpenGroupsAcrossLaunches() async throws {
        let (root, environment, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "ux-" + UUID().uuidString)!
        let first = model(environment, defaults: defaults, root: root)
        XCTAssertEqual(first.tab, .items); XCTAssertEqual(first.sort, .size); XCTAssertTrue(first.expandedGroups.isEmpty, "a fresh page starts as a folded map")
        first.tab = .history; first.sort = .idle; first.expandedGroups = [.packages, .xcode]
        let second = model(environment, defaults: defaults, root: root)
        XCTAssertEqual(second.tab, .history); XCTAssertEqual(second.sort, .idle); XCTAssertEqual(second.expandedGroups, [.packages, .xcode])
        defaults.set(Data("garbage".utf8), forKey: SystemDataViewModel.uiStateKey)
        let third = model(environment, defaults: defaults, root: root)
        XCTAssertEqual(third.tab, .items, "damaged saved state falls back to the defaults")
    }

    func testAnEmptyScanProducesAReportWithNoItemsSoThePageCanSayAllIsClean() async throws {
        let (root, environment, _) = try fixture(extraSafeMegabytes: 0); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: environment.home.appending(path: ".cargo"))
        let page = model(environment, defaults: UserDefaults(suiteName: "ux-" + UUID().uuidString)!, root: root)
        try await scanned(page)
        XCTAssertNotNil(page.report)
        XCTAssertTrue(page.items.isEmpty)
    }

    func testSearchIgnoresCaseAndDiacriticsSoTurkishNamesAreFoundByPlainLetters() async throws {
        let (root, environment, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let page = model(environment, defaults: UserDefaults(suiteName: "ux-" + UUID().uuidString)!, root: root)
        try await scanned(page)
        page.filter = "HOMEBREW"
        XCTAssertEqual(page.visibleItems.map(\.id), ["pkg.homebrew"])
        page.filter = "cargo kayit"   // the title is "Cargo kayıt defteri"
        XCTAssertEqual(page.visibleItems.map(\.id), ["pkg.cargo"], "ı matches i")
        page.filter = "xyz-nothing"
        XCTAssertTrue(page.visibleItems.isEmpty)
    }
}

final class TileRowLayoutTests: XCTestCase {
    func testTheColumnCountSurvivesEveryWidthSwiftUIProbesWith() {
        let cases: [(CGFloat, Int)] = [(.infinity, 3), (.nan, 3), (0, 3), (-10, 3), (.greatestFiniteMagnitude, 3), (1, 1), (249, 1), (520, 2), (800, 3), (1_500, 3)]
        for (width, expected) in cases {
            XCTAssertEqual(TileRow.columnCount(width: width, count: 3, minimumWidth: 250, spacing: 12), expected, "width \(width)")
        }
        XCTAssertEqual(TileRow.columnCount(width: 900, count: 0, minimumWidth: 250, spacing: 12), 1)
        XCTAssertEqual(TileRow.columnCount(width: 900, count: 3, minimumWidth: .infinity, spacing: 12), 3)
        XCTAssertEqual(TileRow.columnCount(width: 900, count: 1, minimumWidth: 250, spacing: 12), 1, "never more columns than tiles, so no empty slot")
    }
}

@MainActor
final class SnapshotNoticeTests: XCTestCase {
    func testTheNoticeFiresOnlyWhenAPermanentRemovalGaveLittleBack() {
        typealias Page = SystemDataViewModel
        XCTAssertTrue(Page.spaceDidNotComeBack(mode: .deletePermanently, freedBytes: 5_000_000_000, freeBefore: 100_000_000_000, freeAfter: 100_200_000_000))
        XCTAssertFalse(Page.spaceDidNotComeBack(mode: .deletePermanently, freedBytes: 5_000_000_000, freeBefore: 100_000_000_000, freeAfter: 105_000_000_000), "all of it came back")
        XCTAssertFalse(Page.spaceDidNotComeBack(mode: .deletePermanently, freedBytes: 5_000_000_000, freeBefore: 100_000_000_000, freeAfter: 102_600_000_000), "just over half is fine")
        XCTAssertFalse(Page.spaceDidNotComeBack(mode: .moveToTrash, freedBytes: 5_000_000_000, freeBefore: 100_000_000_000, freeAfter: 100_000_000_000), "the Trash frees nothing by design")
        XCTAssertFalse(Page.spaceDidNotComeBack(mode: .deletePermanently, freedBytes: 50_000_000, freeBefore: 100_000_000_000, freeAfter: 100_000_000_000), "too small to judge")
        XCTAssertFalse(Page.spaceDidNotComeBack(mode: .deletePermanently, freedBytes: 5_000_000_000, freeBefore: nil, freeAfter: 1), "unknown capacity is never an accusation")
    }

    func testRemovingSnapshotsOpensTheNormalConfirmationWithTheirCommand() async throws {
        let base = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil).map { String(cString: $0) })
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-snap-\(UUID().uuidString)", directoryHint: .isDirectory)
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system"), temporaryDirectory: home.appending(path: "tmp"),
                                                run: { executable, _ in executable.hasSuffix("tmutil") ? "Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-01-120000.local\n" : nil },
                                                capacity: { nil })
        let page = SystemDataViewModel(defaults: UserDefaults(suiteName: "snap-" + UUID().uuidString)!, store: SystemDataHistoryStore(url: root.appending(path: "h.json")),
                                       environment: environment, remover: SystemDataRemover(runCommand: { _, _ in (0, "") }),
                                       archiver: SystemDataArchiver(manifest: root.appending(path: "a.json")), removalMode: { .deletePermanently }, summaryFile: nil)
        page.startScan()
        for _ in 0..<200 { if page.report != nil, !page.isScanning { break }; try await Task.sleep(for: .milliseconds(50)) }
        page.removeSnapshots()
        let preview = try XCTUnwrap(page.pendingPreview)
        XCTAssertEqual(preview.lines.map(\.id), ["snapshot.2026-11-01-120000"])
        XCTAssertTrue(preview.lines[0].operations[0].contains("tmutil deletelocalsnapshots 2026-11-01-120000"))
    }
}
