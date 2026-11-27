import Darwin
import Foundation
import Testing
@testable import MacPocketCore

/// Hostile and unusual real-world conditions, run against real temporary folders.
@Suite(.serialized) struct SystemDataDeepTests {
    private func makeRoot() throws -> URL {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-deep-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Makes everything removable again (flags and permissions), then deletes the fixture.
    private func dispose(_ root: URL) {
        _ = try? run("/usr/bin/chflags", ["-R", "nouchg", root.path])
        _ = try? run("/bin/chmod", ["-R", "u+rwx", root.path])
        try? FileManager.default.removeItem(at: root)
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func item(_ id: String, paths: [String], action: SystemDataAction, group: SystemDataGroup = .packages,
                      safety: SystemDataSafety = .safe) -> SystemDataItem {
        SystemDataItem(id: id, group: group, title: id, detail: "", safety: safety, regeneration: .rebuildsLocally,
                       paths: paths, sizeBytes: 1_000, action: action)
    }

    private func environment(_ root: URL, files: Int = 0) throws -> SystemDataEnvironment {
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
        return SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system"), temporaryDirectory: home.appending(path: "tmp"),
                                     run: { _, _ in nil }, capacity: { nil })
    }

    private func scan(_ environment: SystemDataEnvironment) async -> SystemDataReport {
        var report: SystemDataReport?
        for await event in SystemDataScanner(environment: environment, maximumDuration: 60).scan() { if case .finished(let done) = event { report = done } }
        return report ?? SystemDataReport(scannedAt: Date(), items: [], totalBytes: 0, freeBytes: 0, purgeableBytes: 0, complete: false)
    }

    // MARK: Names

    private static let hardNames = [
        "Çalışma Klasörü ığüşöç İĞÜŞÖÇ", "emoji 📦 klasör 🧪", "tırnaklı 'tek' \"çift\" `ters` $dolar", "boşluk   üç   tane",
        "-başında-tire", "nokta.sonda.", "satır\nsonu", "Cafe\u{0301} (NFD)", "日本語フォルダ", "اختبار",
    ]

    @Test func removalAndPreviewHandleEveryAwkwardFolderName() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        var items: [SystemDataItem] = []
        for (index, name) in Self.hardNames.enumerated() {
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder.appending(path: "inner dir"), withIntermediateDirectories: true)
            try Data(count: 2_048).write(to: folder.appending(path: "inner dir/dosya \(name.prefix(3)).bin"))
            let canonical = try #require(existingCanonicalPath(folder), "\(name) must resolve")
            items.append(item("unicode-\(index)", paths: [canonical], action: index.isMultiple(of: 2) ? .removeFolder : .removeContents))
        }
        let preview = SystemDataRemovalPlanner.preview(items: items, mode: .deletePermanently, home: root, temporaryDirectory: root)
        #expect(preview.lines.count == items.count)
        for line in preview.lines {
            #expect(line.operations.allSatisfy { $0.hasPrefix("rm -rf -- ") }, "\(line.operations)")
        }
        // The dangerous names must be single-quoted so the shell sees one word.
        let quoted = preview.lines.flatMap(\.operations).first { $0.contains("tırnaklı") }
        #expect(quoted?.contains("'\\''") == true)

        let outcomes = await SystemDataRemover().remove(items, mode: .deletePermanently, administratorPrompt: nil)
        for outcome in outcomes { #expect(outcome.succeeded, "\(outcome.itemID): \(outcome.error ?? "")") }
        for (index, name) in Self.hardNames.enumerated() {
            let folder = root.appending(path: name)
            if index.isMultiple(of: 2) { #expect(!FileManager.default.fileExists(atPath: folder.path), "\(name) should be gone") }
            else { #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty, "\(name) should be emptied") }
        }
    }

    @Test func archiveAndShrinkRoundTripWithTurkishAndEmojiNames() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        for name in ["Proje Çalışması ığüşöç 📦", "Ünite İ–ı test"] {
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let text = Data(String(repeating: "çok tekrarlı içerik ığüşöç 📦\n", count: 400_000).utf8)
            try text.write(to: folder.appending(path: "büyük dosya.txt"))
            let canonical = try #require(existingCanonicalPath(folder))

            let shrunk = try await SystemDataShrinker(now: { Date().addingTimeInterval(7_200) }).shrink(folder: canonical)
            #expect(shrunk.savedBytes > 5_000_000, "\(name)")
            #expect(try Data(contentsOf: folder.appending(path: "büyük dosya.txt")) == text)

            let archiver = SystemDataArchiver(manifest: root.appending(path: "m-\(UUID().uuidString).json"))
            let record = try await archiver.archive(folder: canonical, title: name)
            #expect(!FileManager.default.fileExists(atPath: folder.path))
            try await archiver.restore(record)
            #expect(try Data(contentsOf: folder.appending(path: "büyük dosya.txt")) == text, "\(name) restored byte for byte")
        }
    }

    // MARK: Removal failures

    @Test func immutableAndReadOnlyContentIsReportedNotCrashedAndNeverTriggersAPasswordDialog() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache.appending(path: "ok"), withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: cache.appending(path: "ok/file.bin"))
        let locked = cache.appending(path: "locked.bin")
        try Data(count: 1_000).write(to: locked)
        #expect(try run("/usr/bin/chflags", ["uchg", locked.path]) == 0)
        let readonlyDirectory = cache.appending(path: "readonly", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: readonlyDirectory, withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: readonlyDirectory.appending(path: "inner.bin"))
        #expect(try run("/bin/chmod", ["555", readonlyDirectory.path]) == 0)

        let outcomes = await SystemDataRemover().remove([item("cache", paths: [cache.path], action: .removeContents)],
                                                        mode: .deletePermanently, administratorPrompt: nil)
        let outcome = try #require(outcomes.first)
        #expect(!outcome.succeeded, "some content could not be removed and must be reported")
        #expect(outcome.error?.isEmpty == false)
        #expect(!FileManager.default.fileExists(atPath: cache.appending(path: "ok").path), "removable content was still removed")
        #expect(FileManager.default.fileExists(atPath: locked.path), "the locked file survives")
    }

    @Test func twoRemovalsOfTheSameFolderAtOnceBothFinishWithoutCrashing() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        let folder = root.appending(path: "shared", directoryHint: .isDirectory)
        for index in 0..<200 {
            try FileManager.default.createDirectory(at: folder.appending(path: "d\(index)"), withIntermediateDirectories: true)
            try Data(count: 512).write(to: folder.appending(path: "d\(index)/f.bin"))
        }
        let target = item("shared", paths: [folder.path], action: .removeContents)
        async let first = SystemDataRemover().remove([target], mode: .deletePermanently, administratorPrompt: nil)
        async let second = SystemDataRemover().remove([target], mode: .deletePermanently, administratorPrompt: nil)
        let results = await (first, second)
        #expect(results.0.count == 1 && results.1.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func aFolderThatVanishedBeforeRemovalIsNotAnError() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        let gone = root.appending(path: "gone").path
        let outcomes = await SystemDataRemover().remove([item("gone", paths: [gone], action: .removeFolder)], mode: .deletePermanently, administratorPrompt: nil)
        #expect(outcomes.allSatisfy { $0.succeeded })
    }

    // MARK: Scanning

    @Test func anUnreadableFolderMakesTheReportIncompleteInsteadOfSilentlyShort() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        let environment = try environment(root)
        let caches = environment.home.appending(path: "Library/Caches/Homebrew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: caches.appending(path: "secret"), withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: caches.appending(path: "visible.bin"))
        try Data(count: 3_000_000).write(to: caches.appending(path: "secret/hidden.bin"))
        #expect(try run("/bin/chmod", ["000", caches.appending(path: "secret").path]) == 0)
        let report = await scan(environment)
        let homebrew = try #require(report.items.first { $0.id == "pkg.homebrew" })
        #expect(homebrew.sizeBytes >= 3_000_000 && homebrew.sizeBytes < 6_000_000, "only the readable part is counted")
        #expect(report.unreadablePlaces > 0 && report.isPartial, "the user must be told the list is short")
        #expect(report.complete, "an unreadable folder is not a cut-short scan, so background automation keeps working")
    }

    @Test func symlinkLoopsAndDanglingLinksAreNeitherFollowedNorCounted() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        let environment = try environment(root)
        let folder = environment.home.appending(path: "Library/Caches/Homebrew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "a/b"), withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: folder.appending(path: "a/real.bin"))
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "a/b/loop").path, withDestinationPath: folder.path)
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "dangling").path, withDestinationPath: "/nonexistent/target")
        let started = Date()
        let report = await scan(environment)
        #expect(Date().timeIntervalSince(started) < 20)
        let homebrew = try #require(report.items.first { $0.id == "pkg.homebrew" })
        #expect(homebrew.sizeBytes >= 2_000_000 && homebrew.sizeBytes < 3_000_000)
    }

    @Test func stoppingTheStreamEarlyCancelsTheScanAndALaterScanStillWorks() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        let environment = try environment(root)
        let folder = environment.home.appending(path: "Library/Caches/Homebrew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<4_000 { try Data(count: 64).write(to: folder.appending(path: "f\(index)")) }
        let started = Date()
        var seen = 0
        for await _ in SystemDataScanner(environment: environment).scan() { seen += 1; break }
        #expect(seen == 1)
        #expect(Date().timeIntervalSince(started) < 15, "breaking out does not hang")
        let report = await scan(environment)
        #expect(report.items.contains { $0.id == "pkg.homebrew" })
    }

    @Test func aTreeOfThirtyThousandFilesIsMeasuredQuicklyAndExactly() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        let environment = try environment(root)
        let folder = environment.home.appending(path: "Library/Caches/Homebrew", directoryHint: .isDirectory)
        for directory in 0..<30 {
            let sub = folder.appending(path: "d\(directory)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for file in 0..<1_000 { try Data(count: 10).write(to: sub.appending(path: "f\(file)")) }
        }
        let started = Date()
        let report = await scan(environment)
        let elapsed = Date().timeIntervalSince(started)
        let homebrew = try #require(report.items.first { $0.id == "pkg.homebrew" })
        // Every one of 30,000 files occupies at least one 4 KiB block.
        #expect(homebrew.sizeBytes >= 30_000 * 4_096)
        #expect(elapsed < 30, "took \(elapsed)s")
    }

    // MARK: Planner, history, parsers

    @Test func theFreeUpPlannerHandlesTwentyThousandItemsInWellUnderASecond() {
        let items = (0..<20_000).map { index in
            SystemDataItem(id: "i\(index)", group: SystemDataGroup.allCases[index % SystemDataGroup.allCases.count],
                           title: "t", detail: "", safety: index.isMultiple(of: 3) ? .safe : .review, regeneration: .rebuildsLocally,
                           paths: ["/x/\(index)"], sizeBytes: Int64(index % 997 + 1) * 1_000_000,
                           lastActivity: Date(timeIntervalSince1970: Double(1_700_000_000 + index)), action: .removeFolder)
        }
        let started = Date()
        let plan = FreeUpPlanner.plan(items: items, targetBytes: 50_000_000_000, now: Date())
        #expect(Date().timeIntervalSince(started) < 1)
        #expect(plan.reachesTarget && plan.selectedBytes >= 50_000_000_000)
        #expect(Set(plan.selectedIDs).count == plan.selectedIDs.count, "no item twice")
    }

    @Test func fourHundredScansOfThreeHundredItemsStayAReasonableSizeAndLoadFast() async throws {
        let root = try makeRoot()
        defer { dispose(root) }
        var history = SystemDataHistory()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for scan in 0..<400 {
            let items = (0..<300).map { index in
                SystemDataItem(id: "project./Users/someone/Projects/application-\(index)/node_modules", group: .projects, title: "t", detail: "",
                               safety: .review, regeneration: .downloadsAgain, paths: ["/x"], sizeBytes: Int64(index * 1_000_000 + scan),
                               action: .removeFolder)
            }
            history.record(SystemDataReport(scannedAt: start.addingTimeInterval(Double(scan) * 3_600), items: items, totalBytes: 0, freeBytes: 0, purgeableBytes: 0, complete: true))
        }
        let url = root.appending(path: "history.json")
        let store = SystemDataHistoryStore(url: url)
        let built = history
        _ = try await store.update { $0 = built }
        let bytes = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(bytes < 25_000_000, "history file is \(bytes) bytes")
        let started = Date()
        let loaded = await SystemDataHistoryStore(url: url).load()
        #expect(Date().timeIntervalSince(started) < 3)
        #expect(loaded.scans.count == history.scans.count)
        _ = loaded.growthAlerts()
    }

    @Test func garbageInputToEveryParserNeverCrashes() {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("{}[]\":,0123456789.- \n\tabcdefghijklmnopqrstuvwxyzÇŞĞİÖÜ📦GBMBKBTB%/\\".unicodeScalars)
        for _ in 0..<3_000 {
            let length = Int.random(in: 0...400, using: &generator)
            let text = String(String.UnicodeScalarView((0..<length).map { _ in alphabet.randomElement(using: &generator)! }))
            let data = Data(text.utf8)
            _ = SystemDataParsers.simulatorRuntimes(data)
            _ = SystemDataParsers.simulatorDevices(data)
            _ = SystemDataParsers.dockerUsage(text)
            _ = SystemDataParsers.ollamaModels(text)
            _ = SystemDataParsers.localSnapshotDates(text)
            _ = SystemDataParsers.bytes(fromHumanSize: text)
            _ = SystemDataParsers.ollamaManifestLayers(data)
            _ = SystemDataParsers.ollamaManifestPath(for: text)
            _ = SystemDataParsers.isUUID(text)
        }
        // Raw random bytes too, including invalid UTF-8.
        for _ in 0..<500 {
            let bytes = Data((0..<Int.random(in: 0...300, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator) })
            _ = SystemDataParsers.simulatorRuntimes(bytes)
            _ = SystemDataParsers.ollamaManifestLayers(bytes)
            _ = SystemDataParsers.dockerUsage(String(decoding: bytes, as: UTF8.self))
        }
    }

    @Test func humanSizesNeverOverflowOrGoNegative() {
        for text in ["9999999999999999999999 TB", "1e400 GB", "-5 GB", "nan GB", "inf MB", "0.0000001 GB", "1.7976931348623157e308 B", ".5 GB", "5. GB"] {
            if let value = SystemDataParsers.bytes(fromHumanSize: text) { #expect(value >= 0, "\(text)") }
        }
    }
}

@Suite struct SystemDataProgressTests {
    @Test func aSlowScanReportsMonotonicProgressByPhase() async throws {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-progress-\(UUID().uuidString)", directoryHint: .isDirectory)
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: "Library/Caches/Homebrew"), withIntermediateDirectories: true)
        try Data(count: 1_000_000).write(to: home.appending(path: "Library/Caches/Homebrew/a.bin"))
        defer { try? FileManager.default.removeItem(at: root) }
        // The fake tools take a while, as `docker` or `xcrun` do on a real Mac.
        let environment = SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system"), temporaryDirectory: home.appending(path: "tmp"),
                                                run: { _, _ in try? await Task.sleep(for: .milliseconds(700)); return nil }, capacity: { nil })
        var readings: [SystemDataScanProgress] = []
        var phases = 0
        for await event in SystemDataScanner(environment: environment).scan() {
            switch event {
            case .progress(let reading): readings.append(reading)
            case .phase: phases += 1
            case .finished: break
            case .item: break
            }
        }
        #expect(phases == SystemDataScanProgress.phaseCount, "every phase announces itself")
        #expect(readings.count >= 3, "progress arrives while the scan runs, not only at the end")
        #expect(readings.map(\.phaseIndex) == readings.map(\.phaseIndex).sorted(), "the phase never goes backwards")
        #expect(readings.allSatisfy { (0...1).contains($0.fraction) && $0.phaseIndex <= SystemDataScanProgress.phaseCount })
        #expect(readings.map(\.visitedEntries) == readings.map(\.visitedEntries).sorted())
    }
}
