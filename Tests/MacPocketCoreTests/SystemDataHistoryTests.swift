import Foundation
import Testing
@testable import MacPocketCore

@Suite struct SystemDataHistoryTests {
    private static let gb: Int64 = 1_000_000_000
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(day: Int, groupGB: [SystemDataGroup: Int64], id: (SystemDataGroup) -> String = { "item-\($0.rawValue)" }) -> SystemDataReport {
        let items = groupGB.map { group, size in
            SystemDataItem(id: id(group), group: group, title: id(group), detail: "", safety: .safe, regeneration: .rebuildsLocally,
                           paths: ["/x"], sizeBytes: size * Self.gb, action: .removeFolder)
        }
        return SystemDataReport(scannedAt: start.addingTimeInterval(Double(day) * 86_400), items: items,
                                totalBytes: 0, freeBytes: 0, purgeableBytes: 0, complete: true)
    }

    private func history(_ sizes: [Int64], group: SystemDataGroup = .xcode) -> SystemDataHistory {
        var history = SystemDataHistory()
        for (day, size) in sizes.enumerated() { history.record(report(day: day, groupGB: [group: size])) }
        return history
    }

    @Test func growthNeedsFiftyPercentAndTwoGigabytesOverTheMedian() {
        let history = history([10, 10, 10, 10, 10, 16])
        let alerts = history.growthAlerts()
        #expect(alerts.count == 1)
        #expect(alerts.first?.group == .xcode)
        #expect(alerts.first?.growthBytes == 6 * Self.gb)
    }

    @Test func smallOrSlowGrowthStaysQuiet() {
        #expect(history([10, 10, 10, 10, 10, 11]).growthAlerts().isEmpty)
        #expect(history([1, 1, 1, 1, 1, 2]).growthAlerts().isEmpty)
        #expect(history([100, 100, 100, 100, 100, 130]).growthAlerts().isEmpty)
    }

    @Test func tooFewScansNeverAlert() {
        #expect(history([10, 10, 30]).growthAlerts().isEmpty)
    }

    @Test func aGroupSpeaksAgainOnlyAfterAnotherTwoGigabytes() throws {
        var history = history([10, 10, 10, 10, 10, 16])
        history.markAlerted(try #require(history.growthAlerts().first))
        history.record(report(day: 6, groupGB: [.xcode: 17]))
        #expect(history.growthAlerts().isEmpty)
        history.record(report(day: 7, groupGB: [.xcode: 19]))
        #expect(history.growthAlerts().count == 1)
    }

    @Test func trendReturnsTheLastSizesOldestFirst() {
        let history = history([1, 2, 3, 4])
        #expect(history.trend(forItem: "item-xcode", limit: 3) == [2, 3, 4].map { $0 * Self.gb })
        #expect(history.trend(forItem: "unknown").isEmpty)
    }

    @Test func changeComparesWithTheNewestScanOldEnough() {
        let history = history([1, 2, 3, 4, 5, 6, 7, 8, 9])
        let now = start.addingTimeInterval(8 * 86_400)
        #expect(history.change(forItem: "item-xcode", currentBytes: 9 * Self.gb, overDays: 7, now: now) == 7 * Self.gb)
        #expect(history.change(forItem: "item-xcode", currentBytes: 9 * Self.gb, overDays: 30, now: now) == nil)
    }

    @Test func deletedItemsThatRegrowAreReported() {
        var history = SystemDataHistory()
        history.recordDeletion(.init(date: start, itemID: "item-xcode", title: "DerivedData", bytes: 12 * Self.gb, paths: ["/x"]))
        history.recordDeletion(.init(date: start, itemID: "item-logs", title: "Logs", bytes: 12 * Self.gb, paths: ["/y"]))
        let now = report(day: 5, groupGB: [.xcode: 9, .logs: 1])
        let returned = history.returnedItems(current: now.items, now: now.scannedAt)
        #expect(returned.map(\.itemID) == ["item-xcode"])
    }

    @Test func oldRecordsAreDroppedAndTheCountIsBounded() {
        var history = SystemDataHistory()
        history.record(report(day: 0, groupGB: [.xcode: 1]))
        history.record(report(day: 400, groupGB: [.xcode: 1]))
        #expect(history.scans.count == 1)
        for day in 401..<(401 + SystemDataHistory.maximumScans + 20) { history.record(report(day: day, groupGB: [.xcode: 1])) }
        #expect(history.scans.count <= SystemDataHistory.maximumScans)
    }

    @Test func medianHandlesEvenAndOddCounts() {
        #expect(SystemDataHistory.median([3, 1, 2]) == 2)
        #expect(SystemDataHistory.median([4, 1, 2, 3]) == 2)
        #expect(SystemDataHistory.median([]) == 0)
    }

    @Test func storePersistsAndEraseRemovesTheFile() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sysdata-\(UUID().uuidString)/history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SystemDataHistoryStore(url: url)
        let saved = report(day: 0, groupGB: [.xcode: 3])
        _ = try await store.update { $0.record(saved) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(await SystemDataHistoryStore(url: url).load().scans.count == 1)
        try await store.erase()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await store.load().scans.isEmpty)
    }

    @Test func aDamagedFileStartsAnEmptyHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sysdata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.json")
        try Data("{broken".utf8).write(to: url)
        #expect(await SystemDataHistoryStore(url: url).load().scans.isEmpty)
    }
}

@Suite struct SystemDataSummaryTests {
    private let summary = SystemDataSummary(date: Date(timeIntervalSince1970: 1_800_000_000), systemDataBytes: 41_000_000_000,
                                            safeBytes: 3_000_000_000, freeBytes: 167_000_000_000, purgeableBytes: 7_000_000_000)

    @Test func theMenuBarStyleDecidesWhatIsShownBesideTheIcon() {
        #expect(SystemDataMenuBarStyle.off.title(for: summary) == nil && !SystemDataMenuBarStyle.off.showsItem)
        #expect(SystemDataMenuBarStyle.icon.title(for: summary) == nil && SystemDataMenuBarStyle.icon.showsItem)
        #expect(SystemDataMenuBarStyle.systemData.title(for: summary) == 41_000_000_000.formatted(.byteCount(style: .file, spellsOutZero: false)))
        #expect(SystemDataMenuBarStyle.freeSpace.title(for: summary) == Int64(167_000_000_000).formatted(.byteCount(style: .file, spellsOutZero: false)))
        #expect(SystemDataMenuBarStyle.systemData.title(for: nil) == nil, "nothing is shown before the first scan")
    }

    @Test func theSummaryPersistsAndTheStyleDefaultsToOff() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        #expect(SystemDataSummary.load(from: defaults) == nil)
        #expect(SystemDataMenuBarStyle.load(from: defaults) == .off)
        summary.save(to: defaults)
        #expect(SystemDataSummary.load(from: defaults) == summary)
        defaults.set("systemData", forKey: SystemDataMenuBarStyle.key)
        #expect(SystemDataMenuBarStyle.load(from: defaults) == .systemData)
        defaults.set("garbage", forKey: SystemDataMenuBarStyle.key)
        #expect(SystemDataMenuBarStyle.load(from: defaults) == .off)
    }
}
