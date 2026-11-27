import Foundation
import Testing
@testable import MacPocketCore
import MacPocketTestSupport

/// Runs the real process pipeline (`SystemDataEnvironment.liveRunner`, `SystemDataRemover.liveRunner`,
/// `BoundedProcess`) against small shell scripts that stand in for `docker` and `ollama`, and against the
/// real `simctl`.
@Suite struct SystemDataIntegrationTests {
    private func makeRoot() throws -> URL {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-int-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func script(_ name: String, in directory: URL, body: String) throws {
        let url = directory.appending(path: name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func isolatedEnvironment(root: URL, tools: URL) throws -> SystemDataEnvironment {
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home.appending(path: "tmp"), withIntermediateDirectories: true)
        return SystemDataEnvironment(home: home, systemRoot: root.appending(path: "system"), temporaryDirectory: home.appending(path: "tmp"),
                                     toolSearchPaths: [tools.path], capacity: { nil })
    }

    private func scan(_ environment: SystemDataEnvironment) async -> [SystemDataItem] {
        var items: [SystemDataItem] = []
        for await event in SystemDataScanner(environment: environment).scan() { if case .finished(let report) = event { items = report.items } }
        return items
    }

    @Test func dockerAndOllamaItemsComeFromRealProcessOutputAndRemovalRunsTheExactArguments() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let log = root.appending(path: "calls.log")
        try script("docker", in: tools, body: """
        if [ "$1" = "system" ] && [ "$2" = "df" ]; then
          echo '{"Reclaimable":"1.2GB (50%)","Size":"2.4GB","Type":"Images"}'
          echo '{"Reclaimable":"500MB","Size":"500MB","Type":"Build Cache"}'
          echo '{"Reclaimable":"3GB (100%)","Size":"3GB","Type":"Local Volumes"}'
          echo '{"Reclaimable":"0B (0%)","Size":"10MB","Type":"Containers"}'
        else echo "docker $*" >> '\(log.path)'; fi
        """)
        try script("ollama", in: tools, body: """
        if [ "$1" = "list" ]; then
          printf 'NAME  ID  SIZE  MODIFIED\\nllama3:latest  365c0bd3c000  4.7 GB  2 weeks ago\\n'
        else echo "ollama $*" >> '\(log.path)'; fi
        """)
        let items = await scan(try isolatedEnvironment(root: root, tools: tools))
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byID["docker.images"]?.sizeBytes == 1_200_000_000)
        #expect(byID["docker.buildCache"]?.safety == .safe)
        #expect(byID["docker.volumes"]?.warning != nil)
        #expect(byID["docker.containers"] == nil, "nothing reclaimable, so no row")
        #expect(byID["ollama.llama3:latest"]?.sizeBytes == 4_700_000_000)

        let chosen = ["docker.images", "docker.buildCache", "docker.volumes", "ollama.llama3:latest"].compactMap { byID[$0] }
        #expect(chosen.count == 4)
        let outcomes = await SystemDataRemover().remove(chosen, mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcomes.allSatisfy { $0.succeeded })
        let calls = Set(try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init))
        #expect(calls == ["docker image prune --all --force", "docker builder prune --all --force",
                          "docker volume prune --force", "ollama rm llama3:latest"])
    }

    @Test func aFailingToolIsReportedAndDoesNotStopTheOthers() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try script("docker", in: tools, body: "echo 'daemon not running' >&2; exit 1")
        let items = await scan(try isolatedEnvironment(root: root, tools: tools))
        #expect(!items.contains { $0.group == .docker }, "a docker CLI without a daemon contributes nothing")

        let failing = SystemDataItem(id: "bad", group: .docker, title: "bad", detail: "", safety: .review, regeneration: .doesNotReturn,
                                     paths: [], sizeBytes: 1, action: .run(SystemDataCommand(tools.appending(path: "docker").path, ["volume", "prune"])))
        let fine = SystemDataItem(id: "fine", group: .docker, title: "fine", detail: "", safety: .safe, regeneration: .rebuildsLocally,
                                  paths: [], sizeBytes: 1, action: .run(SystemDataCommand("/usr/bin/true")))
        let outcomes = await SystemDataRemover().remove([failing, fine], mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcomes.map(\.succeeded) == [false, true])
        #expect(outcomes[0].error?.contains("daemon not running") == true)
    }

    @Test func iOSBackupsShowTheDeviceNameAndAreRemovedAsAFolder() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let environment = try isolatedEnvironment(root: root, tools: tools)
        let backup = environment.home.appending(path: "Library/Application Support/MobileSync/Backup/00008110-AAAA", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data(count: 12_000_000).write(to: backup.appending(path: "Manifest.db"))
        let info: [String: Any] = ["Device Name": "Doğan’s iPhone", "Last Backup Date": Date(timeIntervalSince1970: 1_790_000_000)]
        try (info as NSDictionary).write(to: backup.appending(path: "Info.plist"))

        let items = await scan(environment)
        let item = try #require(items.first { $0.id == "backup.00008110-AAAA" })
        #expect(item.title.contains("Doğan’s iPhone"))
        #expect(item.sizeBytes >= 12_000_000 && item.safety == .review && item.action == .removeFolder)
        let outcomes = await SystemDataRemover().remove([item], mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcomes.allSatisfy { $0.succeeded })
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    /// Creates a throwaway simulator with the real `simctl`, then removes it through the same command path
    /// the page uses.
    @Test(.enabled(if: liveSystemTestsEnabled && FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")))
    func aRealSimulatorDeviceIsRemovedThroughTheCommandPath() async throws {
        let listing = try #require(await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "list", "-j", "devicetypes", "runtimes"]))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(listing.utf8)) as? [String: Any])
        let types = (json["devicetypes"] as? [[String: Any]])?.compactMap { $0["identifier"] as? String } ?? []
        let runtimes = (json["runtimes"] as? [[String: Any]])?.filter { ($0["isAvailable"] as? Bool) == true }.compactMap { $0["identifier"] as? String } ?? []
        guard let type = types.first(where: { $0.contains("iPhone") }), let runtime = runtimes.first(where: { $0.contains("iOS") }) else { return }
        let name = "MacPocketTest-\(UUID().uuidString.prefix(8))"
        let created = try #require(await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "create", name, type, runtime]))
        let udid = created.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(SystemDataParsers.isUUID(udid))
        func exists() async -> Bool {
            let devices = await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"]) ?? ""
            return SystemDataParsers.simulatorDevices(Data(devices.utf8)).contains { $0.udid == udid }
        }
        #expect(await exists())
        let item = SystemDataItem(id: "sim", group: .simulators, title: name, detail: "", safety: .review, regeneration: .doesNotReturn,
                                  paths: [], sizeBytes: 1, action: .run(SystemDataCommand("/usr/bin/xcrun", ["simctl", "delete", udid])))
        let outcomes = await SystemDataRemover().remove([item], mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcomes.allSatisfy { $0.succeeded })
        #expect(await !exists())
    }
}

/// Opens the real macOS administrator password dialog. Off unless `MACPOCKET_LIVE_ADMIN_PROMPT=1`, because
/// somebody has to press Cancel (the dialog is never authenticated, and the command is `/usr/bin/true`
/// anyway).
@Suite struct AdministratorPromptLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPOCKET_LIVE_ADMIN_PROMPT"] == "1"))
    func theRealPasswordDialogCanBeDeclinedAndIsReportedAsSuch() async {
        let item = SystemDataItem(id: "admin", group: .system, title: "admin", detail: "", safety: .review, regeneration: .rebuildsLocally,
                                  paths: [], sizeBytes: 1, action: .run(SystemDataCommand("/usr/bin/true", asAdministrator: true)))
        let outcome = await SystemDataRemover().remove([item], mode: .deletePermanently,
                                                       administratorPrompt: "MacPocket live test: please press Cancel")
        #expect(outcome.first?.succeeded == false)
        #expect(outcome.first?.error == FileRemovalError.administratorDeclined.localizedDescription)
    }
}

@Suite struct OllamaLiveTests {
    private static let ollama = "/opt/homebrew/bin/ollama"

    /// Uses the real `ollama` with the small model `all-minilm` when both are present (it is skipped
    /// otherwise): the scanner must report the manifest's exact byte count, and `ollama rm` through the
    /// remover must delete it.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ollama")))
    func aRealOllamaModelIsMeasuredExactlyAndRemovedWithOllamaRm() async throws {
        guard let listing = await SystemDataEnvironment.liveRunner(Self.ollama, ["list"]),
              SystemDataParsers.ollamaModels(listing).contains(where: { $0.name == "all-minilm:latest" }) else { return }
        let manifest = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ollama/models/manifests/registry.ollama.ai/library/all-minilm/latest")
        let layers = SystemDataParsers.ollamaManifestLayers(try Data(contentsOf: manifest))
        let expected = Dictionary(layers.map { ($0.digest, $0.size) }, uniquingKeysWith: { first, _ in first }).values.reduce(0, +)

        var items: [SystemDataItem] = []
        for await event in SystemDataScanner(environment: SystemDataEnvironment(toolSearchPaths: ["/opt/homebrew/bin"], capacity: { nil })).scan() {
            if case .finished(let report) = event { items = report.items }
        }
        let item = try #require(items.first { $0.id == "ollama.all-minilm:latest" })
        #expect(item.sizeBytes == expected, "exact manifest bytes, not the rounded 45 MB of `ollama list`")

        let outcomes = await SystemDataRemover().remove([item], mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcomes.allSatisfy { $0.succeeded })
        let after = await SystemDataEnvironment.liveRunner(Self.ollama, ["list"]) ?? ""
        #expect(!SystemDataParsers.ollamaModels(after).contains { $0.name == "all-minilm:latest" })
    }
}

@Suite struct DockerLiveTests {
    /// Uses the real `docker` when its daemon answers (read-only: `docker system df`); nothing is pruned.
    ///
    /// The scan takes about 30 seconds and asks the daemon on its own, so the daemon is read before and after
    /// it: unchanged, the scanner must report exactly what it says; changed in the meantime (a build, a pull,
    /// another app's containers), the scanner's figure must lie between the two real readings.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/docker")))
    func theScannerReportsWhatARealDockerDaemonSaysIsReclaimable() async throws {
        guard let before = await Self.reclaimable() else { return }   // daemon not running
        #expect(!before.isEmpty, "the real output must parse")
        var items: [SystemDataItem] = []
        for await event in SystemDataScanner(environment: SystemDataEnvironment(toolSearchPaths: ["/opt/homebrew/bin"], capacity: { nil })).scan() {
            if case .finished(let report) = event { items = report.items.filter { $0.group == .docker } }
        }
        let after = try #require(await Self.reclaimable(), "the daemon stopped answering during the scan")
        for id in Set(before.keys).union(after.keys) {
            let low = min(before[id] ?? 0, after[id] ?? 0), high = max(before[id] ?? 0, after[id] ?? 0)
            let reported = items.first { $0.id == id }?.sizeBytes ?? 0
            #expect((low...high).contains(reported), "\(id): scanner \(reported), daemon \(before[id] ?? 0) before and \(after[id] ?? 0) after")
        }
        // Every reported item is a kind the daemon had something reclaimable in, before or after.
        #expect(items.allSatisfy { (before[$0.id] ?? 0) > 0 || (after[$0.id] ?? 0) > 0 }, "\(items.map(\.id))")
    }

    /// Reclaimable bytes by scanner item id, as the daemon reports them now; nil when it does not answer.
    private static func reclaimable() async -> [String: Int64]? {
        guard let df = await SystemDataEnvironment.liveRunner("/opt/homebrew/bin/docker", ["system", "df", "--format", "{{json .}}"]) else {
            return nil
        }
        var bytes: [String: Int64] = [:]
        for entry in SystemDataParsers.dockerUsage(df) where entry.reclaimableBytes > 0 {
            let id = switch entry.kind {
            case .images: "docker.images"
            case .buildCache: "docker.buildCache"
            case .containers: "docker.containers"
            case .volumes: "docker.volumes"
            }
            bytes[id] = entry.reclaimableBytes
        }
        return bytes
    }
}

/// These touch the real machine (a real local snapshot, a real simulator boot), so they run only on request:
/// `MACPOCKET_LIVE_SYSTEM=1 swift test`. A CI virtual machine has neither.
private let liveSystemTestsEnabled = ProcessInfo.processInfo.environment["MACPOCKET_LIVE_SYSTEM"] == "1"

@Suite struct TimeMachineLiveTests {
    /// Creates a real local snapshot, finds it with the real scanner and removes it through the page's
    /// command path, without an administrator prompt (macOS lets a user delete the snapshots made for them).
    @Test(.enabled(if: liveSystemTestsEnabled && FileManager.default.isExecutableFile(atPath: "/usr/bin/tmutil")))
    func aRealLocalSnapshotIsFoundAndRemovedWithoutAPasswordPrompt() async throws {
        let created = try #require(await SystemDataEnvironment.liveRunner("/usr/bin/tmutil", ["localsnapshot"]))
        guard let stamp = SystemDataParsers.localSnapshotDates(created).first else { return }   // snapshots unavailable on this Mac
        let before = await SystemDataScanner.snapshotItems(env: SystemDataEnvironment(capacity: { nil }))
        let item = try #require(before.first { $0.id == "snapshot.\(stamp)" })
        #expect(!item.sizeKnown && item.safety == .review)
        let prompts = Locked<Int>(0)
        let remover = SystemDataRemover(runCommand: { command, prompt in
            if command.asAdministrator { prompts.mutate { $0 += 1 } }
            return await SystemDataRemover.liveRunner(command, prompt)
        })
        let outcomes = await remover.remove([item], mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcomes.allSatisfy { $0.succeeded })
        #expect(prompts.value == 0)
        let after = await SystemDataScanner.snapshotItems(env: SystemDataEnvironment(capacity: { nil }))
        #expect(!after.contains { $0.id == item.id })
    }
}

@Suite struct SimulatorShutdownTests {
    @Test func theSettingIsOnByDefaultAndCanBeTurnedOff() throws {
        let store = try TemporaryDefaults()
        defer { #expect(throws: Never.self) { try store.remove() } }
        let defaults = store.defaults
        #expect(SimulatorShutdown.isEnabled(defaults))
        defaults.set(false, forKey: SimulatorShutdown.defaultsKey)
        #expect(!SimulatorShutdown.isEnabled(defaults))
    }

    /// Boots a real throwaway simulator, then checks that `shutdownAll` leaves none booted.
    @Test(.enabled(if: liveSystemTestsEnabled && FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")))
    func shutdownAllTurnsARealBootedSimulatorOff() async throws {
        let listing = try #require(await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "list", "-j", "devicetypes", "runtimes"]))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(listing.utf8)) as? [String: Any])
        let types = (json["devicetypes"] as? [[String: Any]])?.compactMap { $0["identifier"] as? String } ?? []
        let runtimes = (json["runtimes"] as? [[String: Any]])?.filter { ($0["isAvailable"] as? Bool) == true }.compactMap { $0["identifier"] as? String } ?? []
        guard let type = types.first(where: { $0.contains("iPhone") }), let runtime = runtimes.first(where: { $0.contains("iOS") }),
              SimulatorShutdown.bootedCount() == 0 else { return }   // never touch a simulator someone is using
        let udid = try #require(await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "create", "MacPocketShutdownTest", type, runtime]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        defer { Task { _ = await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "delete", udid]) } }
        _ = await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "boot", udid])
        _ = await SystemDataEnvironment.liveRunner("/usr/bin/xcrun", ["simctl", "bootstatus", udid])
        #expect(SimulatorShutdown.bootedCount() == 1)
        let started = Date()
        #expect(SimulatorShutdown.shutdownAll() == 1)
        #expect(SimulatorShutdown.bootedCount() == 0)
        #expect(Date().timeIntervalSince(started) < 20)
    }
}
