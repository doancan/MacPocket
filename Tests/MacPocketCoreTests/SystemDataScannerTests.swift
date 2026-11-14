import Foundation
import Testing
@testable import MacPocketCore

@Suite struct SystemDataScannerTests {
    private func makeHome() throws -> URL {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let url = URL(fileURLWithPath: base).appending(path: "sysdata-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ relative: String, in home: URL, megabytes: Int = 0, bytes: Int = 4_096, age days: Int = 0) throws {
        let file = home.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: megabytes > 0 ? megabytes * 1_000_000 : bytes).write(to: file)
        if days > 0 {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(days) * 86_400)], ofItemAtPath: file.path)
        }
    }

    private func scan(home: URL, run: @escaping SystemDataEnvironment.CommandRunner = { _, _ in nil },
                      appName: @escaping @Sendable (String) -> String? = { _ in nil }) async -> SystemDataReport {
        let temp = home.appending(path: "tmp", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let environment = SystemDataEnvironment(home: home, temporaryDirectory: temp, run: run, installedAppName: appName, capacity: { nil })
        var report: SystemDataReport?
        for await event in SystemDataScanner(environment: environment, maximumDuration: 60).scan() {
            if case .finished(let finished) = event { report = finished }
        }
        return report ?? SystemDataReport(scannedAt: Date(), items: [], totalBytes: 0, freeBytes: 0, purgeableBytes: 0, complete: false)
    }

    @Test func catalogLocationsAreMeasuredAndMissingOnesAreSkipped() async throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write("Library/Developer/Xcode/DerivedData/App-abc/Build/out.bin", in: home, megabytes: 5)
        try write("Library/Caches/Homebrew/downloads/pkg.tar", in: home, megabytes: 2)
        let report = await scan(home: home)
        let derived = try #require(report.items.first { $0.id == "xcode.derivedData" })
        #expect(derived.sizeBytes >= 5_000_000)
        #expect(derived.safety == .safe && derived.action == .removeContents)
        #expect(report.items.contains { $0.id == "pkg.homebrew" })
        #expect(!report.items.contains { $0.id == "xcode.archives" })
    }

    @Test func hiddenItemsStayOutOfFutureScans() async throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write("Library/Caches/Homebrew/a.bin", in: home, megabytes: 1)
        let temp = home.appending(path: "tmp")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let environment = SystemDataEnvironment(home: home, temporaryDirectory: temp, run: { _, _ in nil }, capacity: { nil })
        var ids: [String] = []
        for await event in SystemDataScanner(environment: environment).scan(hidden: ["pkg.homebrew"]) {
            if case .finished(let report) = event { ids = report.items.map(\.id) }
        }
        #expect(!ids.contains("pkg.homebrew"))
    }

    @Test func temporaryFilesCountOnlyWhatIsOlderThanThreeDays() async throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write("tmp/old.bin", in: home, megabytes: 3, age: 10)
        try write("tmp/fresh.bin", in: home, megabytes: 7)
        let report = await scan(home: home)
        let item = try #require(report.items.first { $0.id == "temp.user" })
        #expect(item.sizeBytes >= 3_000_000 && item.sizeBytes < 6_000_000)
        #expect(item.action == .removeContentsOlderThan(days: 3))
    }

    @Test func projectBuildFoldersAreFoundNextToTheirMarkerAndDatedByProjectFiles() async throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write("Developer/web/package.json", in: home, age: 400)
        try write("Developer/web/package-lock.json", in: home)
        try write("Developer/web/node_modules/dep/index.js", in: home, megabytes: 25)
        try write("Developer/notaproject/node_modules/dep/index.js", in: home, megabytes: 25)
        try write("Developer/tiny/package.json", in: home)
        try write("Developer/tiny/node_modules/x.js", in: home, bytes: 100)
        let report = await scan(home: home)
        let projects = report.items.filter { $0.group == .projects }
        #expect(projects.count == 1)
        let item = try #require(projects.first)
        #expect(item.title.hasSuffix("web") && item.projectPath?.hasSuffix("Developer/web") == true)
        #expect((item.idleDays() ?? 0) >= 399)   // the fresh lockfile does not make it look active
        #expect(item.action == .removeFolder && item.safety == .review)
    }

    @Test func simulatorRuntimesSnapshotsAndUnavailableDevicesComeFromToolOutput() async throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        let runtimeJSON = #"{"55C87D17-CC93-4CBF-BD1A-E576F74DFC6B":{"identifier":"55C87D17-CC93-4CBF-BD1A-E576F74DFC6B","deletable":true,"platformIdentifier":"com.apple.platform.iphonesimulator","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","sizeBytes":8000000000,"state":"Ready","version":"27.0","build":"1"}}"#
        let deviceJSON = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"AC3F48EB-2EDE-4471-8EAE-538698A57971","name":"Old","dataPath":"/x","dataPathSize":3000000000,"isAvailable":false,"state":"Shutdown"}]}}"#
        let report = await scan(home: home, run: { executable, arguments in
            if executable.hasSuffix("tmutil") { return "Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-01-120000.local\n" }
            if arguments.starts(with: ["simctl", "runtime"]) { return runtimeJSON }
            if arguments.starts(with: ["simctl", "list"]) { return deviceJSON }
            return nil
        })
        let runtime = try #require(report.items.first { $0.id.hasPrefix("simulator.runtime.") })
        #expect(runtime.sizeBytes == 8_000_000_000)
        #expect(runtime.action == .run(SystemDataCommand("/usr/bin/xcrun", ["simctl", "runtime", "delete", "55C87D17-CC93-4CBF-BD1A-E576F74DFC6B"])))
        let unavailable = try #require(report.items.first { $0.id == "simulator.unavailable" })
        #expect(unavailable.safety == .safe && unavailable.sizeBytes == 3_000_000_000)
        let snapshot = try #require(report.items.first { $0.id == "snapshot.2026-11-01-120000" })
        #expect(!snapshot.sizeKnown && snapshot.sizeBytes == 0)
        #expect(snapshot.action == .run(SystemDataCommand("/usr/bin/tmutil", ["deletelocalsnapshots", "2026-11-01-120000"], administratorFallback: true)))
        #expect(report.systemDataBytes >= 11_000_000_000)
    }

    @Test func unexplainedLargeFoldersGetAnOwnerFromTheirName() async throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write("Library/Containers/com.gone.app/Data/blob.bin", in: home, megabytes: 220)
        try write("Library/Containers/com.here.app/Data/blob.bin", in: home, megabytes: 220)
        try write("Library/Application Support/Small/x.bin", in: home, megabytes: 1)
        let report = await scan(home: home, appName: { $0 == "com.here.app" ? "Here" : nil })
        let others = report.items.filter { $0.group == .other }
        let gone = try #require(others.first { $0.title == "com.gone.app" })
        let here = try #require(others.first { $0.title == "com.here.app" })
        #expect(gone.regeneration == .notNeededAgain && gone.detail.contains("com.gone.app"))
        #expect(here.regeneration == .doesNotReturn && here.detail.contains("Here"))
        #expect(!others.contains { $0.title == "Small" })
    }

    @Test func foldersExplainedByAProbeAreNotReportedTwice() async throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write("Library/Caches/Homebrew/big.bin", in: home, megabytes: 150)
        let report = await scan(home: home)
        #expect(report.items.filter { $0.paths.contains { $0.contains("Homebrew") } }.count == 1)
    }

    @Test func resolveHandlesGlobsSymlinksAndNesting() throws {
        let home = try makeHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write("Library/Caches/Google/AndroidStudio2025.1/x.bin", in: home)
        try write("Library/Caches/Google/AndroidStudio2026.1/x.bin", in: home)
        let outside = try makeHome(); defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: home.appending(path: "linked"), withDestinationURL: outside)
        let globbed = SystemDataCatalog.resolve(["Library/Caches/Google/AndroidStudio*"], home: home)
        #expect(globbed.count == 2)
        let nested = SystemDataCatalog.resolve(["Library/Caches", "Library/Caches/Google"], home: home)
        #expect(nested.count == 1 && nested[0].hasSuffix("Library/Caches"))
        #expect(SystemDataCatalog.resolve(["missing"], home: home).isEmpty)
    }

    @Test func catalogIsSaneAndNeverTouchesProtectedRoots() {
        let probes = SystemDataCatalog.probes()
        #expect(Set(probes.map(\.id)).count == probes.count)
        let forbidden: Set<String> = ["", "/", "Library", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies", "Applications", "/System", "/usr", "/Library", "/Users"]
        for probe in probes {
            #expect(!probe.locations.isEmpty && !probe.title.isEmpty && !probe.detail.isEmpty, "\(probe.id)")
            for location in probe.locations {
                #expect(!forbidden.contains(location), "\(probe.id): \(location)")
                #expect(!location.contains(".."), "\(probe.id)")
                #expect(!location.hasPrefix("~"), "\(probe.id): \(location)")
            }
            if case .manual = probe.action { #expect(probe.safety != .safe, "\(probe.id)") }
            if probe.safety == .manual { if case .manual = probe.action {} else { Issue.record("manual probe \(probe.id) must carry a hint") } }
        }
    }
}

@Suite struct SystemDataAutoCleanTests {
    private func item(_ id: String, safety: SystemDataSafety = .safe, group: SystemDataGroup = .packages, path: String = "/Users/me/Library/Caches/x",
                      busy: [String] = [], sizeKnown: Bool = true, bytes: Int64 = 100, action: SystemDataAction = .removeContents) -> SystemDataItem {
        SystemDataItem(id: id, group: group, title: id, detail: "", safety: safety, regeneration: .rebuildsLocally, paths: [path],
                       sizeBytes: bytes, action: action, busyBundleIDs: busy, sizeKnown: sizeKnown)
    }

    @Test func onlySafePasswordFreeItemsOfIdleAppsAreEligible() {
        let items = [item("ok"), item("review", safety: .review), item("admin", path: "/Library/Caches"),
                     item("busy", busy: ["com.x"]), item("trash", group: .trash), item("unknown", sizeKnown: false, bytes: 0),
                     item("command", action: .run(SystemDataCommand("/usr/bin/true", asAdministrator: true))),
                     item("manual", action: .manual(hint: "x"))]
        let eligible = SystemDataAutoClean.eligible(items, runningBundleIDs: ["com.x"], home: URL(fileURLWithPath: "/Users/me"))
        #expect(eligible.map(\.id) == ["ok"])
    }

    @Test func weeklyCleanIsDueAfterSevenDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SystemDataAutoClean.isDue(lastRun: nil, now: now))
        #expect(!SystemDataAutoClean.isDue(lastRun: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(SystemDataAutoClean.isDue(lastRun: now.addingTimeInterval(-7 * 86_400), now: now))
    }
}

@Suite struct SystemDataBreakdownTests {
    @Test func returnsTheLargestChildrenFirstAndSkipsSymlinks() async throws {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-breakdown-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, megabytes) in [("small.bin", 1), ("big/inner.bin", 6), ("medium.bin", 3)] {
            let file = root.appending(path: name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: megabytes * 1_000_000).write(to: file)
        }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: root.appending(path: "big"))
        let top = await SystemDataBreakdown.topEntries(of: [root.path], limit: 2)
        #expect(top.map(\.name) == ["big", "medium.bin"])
        #expect(await SystemDataBreakdown.topEntries(of: ["/nonexistent/path"], limit: 5).isEmpty)
    }
}

@Suite struct SystemDataIsolationTests {
    @Test func absoluteLocationsResolveUnderTheSystemRootAndNeverTouchTheRealSystem() async throws {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-iso-\(UUID().uuidString)", directoryHint: .isDirectory)
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        let system = root.appending(path: "system", directoryHint: .isDirectory)
        for directory in [home.appending(path: "tmp"), system.appending(path: "Library/Logs/DiagnosticReports")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(count: 3_000_000).write(to: system.appending(path: "Library/Logs/DiagnosticReports/crash.ips"))

        let environment = SystemDataEnvironment(home: home, systemRoot: system, temporaryDirectory: home.appending(path: "tmp"),
                                                run: { _, _ in nil }, capacity: { nil })
        var report: SystemDataReport?
        for await event in SystemDataScanner(environment: environment).scan() { if case .finished(let done) = event { report = done } }
        let items = try #require(report).items
        let diagnostic = try #require(items.first { $0.id == "log.diagnosticsSystem" })
        #expect(diagnostic.paths.allSatisfy { $0.hasPrefix(root.path + "/") })
        #expect(items.allSatisfy { $0.paths.allSatisfy { $0.hasPrefix(root.path + "/") } },
                "an isolated scan must not report anything outside its fixture")
    }
}

@Suite struct SystemDataExternalVolumeTests {
    private func volume(_ path: String = "/Volumes/Work", local: Bool = true, internal isInternal: Bool = false, readOnly: Bool = false,
                        root: Bool = false, timeMachine: Bool = false) -> SystemDataExternalVolumes.Volume {
        .init(url: URL(fileURLWithPath: path), isLocal: local, isInternal: isInternal, isReadOnly: readOnly, isRootFileSystem: root,
              isTimeMachineDestination: timeMachine)
    }

    @Test func onlyPluggedInWritableLocalDrivesQualify() {
        #expect(SystemDataExternalVolumes.isEligible(volume()))
        #expect(!SystemDataExternalVolumes.isEligible(volume(local: false)), "network share")
        #expect(!SystemDataExternalVolumes.isEligible(volume(internal: true)), "the Mac's own disk")
        #expect(!SystemDataExternalVolumes.isEligible(volume(readOnly: true)))
        #expect(!SystemDataExternalVolumes.isEligible(volume("/", root: true)))
        #expect(!SystemDataExternalVolumes.isEligible(volume(timeMachine: true)))
        #expect(!SystemDataExternalVolumes.isEligible(volume("/System/Volumes/Data")))
        #expect(!SystemDataExternalVolumes.isEligible(volume("/Volumes/")))
    }

    @Test func offByDefault() {
        #expect(!SystemDataExternalVolumes.isEnabled(UserDefaults(suiteName: UUID().uuidString)!))
    }

    @Test func projectsOnAnExternalDriveAreFoundOnlyWhenSwitchedOnAndOnlyInProjectFolders() async throws {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-ext-\(UUID().uuidString)", directoryHint: .isDirectory)
        let home = root.appending(path: "home"), drive = root.appending(path: "drive")
        try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ relative: String, megabytes: Int) throws {
            let file = drive.appending(path: relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: megabytes * 1_000_000 + 1).write(to: file)
        }
        try write("Projects/app/package.json", megabytes: 0)
        try write("Projects/app/node_modules/x/index.js", megabytes: 30)
        try write("Photos/other/package.json", megabytes: 0)
        try write("Photos/other/node_modules/x/index.js", megabytes: 30)

        func scan(include: Bool) async -> [SystemDataItem] {
            let environment = SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system"), temporaryDirectory: home.appending(path: "tmp"),
                                                    externalVolumes: { [drive] in [drive] }, includeExternalProjects: include,
                                                    run: { _, _ in nil }, capacity: { nil })
            var items: [SystemDataItem] = []
            for await event in SystemDataScanner(environment: environment).scan() { if case .finished(let report) = event { items = report.items } }
            return items.filter { $0.group == .projects }
        }
        #expect(await scan(include: false).isEmpty)
        let found = await scan(include: true)
        #expect(found.count == 1)
        #expect(found.first?.projectPath?.hasSuffix("Projects/app") == true)
    }
}
