import Foundation
import Testing
@testable import MacPocketCore

@Suite struct SystemDataRemovalTests {
    /// A fresh folder under the per-user temporary directory, the one scope the removal validator accepts for
    /// fixtures.
    private func fixture() throws -> URL {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let url = URL(fileURLWithPath: base).appending(path: "sysdata-removal-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, in directory: URL, bytes: Int = 1_024, age days: Int? = nil) throws {
        let file = directory.appending(path: name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: file)
        if let days {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(days) * 86_400)], ofItemAtPath: file.path)
        }
    }

    private func item(_ id: String, paths: [String], action: SystemDataAction, busy: [String] = []) -> SystemDataItem {
        SystemDataItem(id: id, group: .packages, title: id, detail: "", safety: .safe, regeneration: .rebuildsLocally,
                       paths: paths, sizeBytes: 1_024, action: action, busyBundleIDs: busy)
    }

    private func remover(runCommand: @escaping SystemDataRemover.CommandRunner = { _, _ in (0, "") },
                         running: @escaping @Sendable (String) -> String? = { _ in nil }) -> SystemDataRemover {
        SystemDataRemover(runCommand: runCommand, runningAppName: running)
    }

    @Test func removeContentsDeletesChildrenButKeepsTheFolder() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a/file.bin", in: root)
        try write("b.bin", in: root)
        let result = await remover().remove([item("cache", paths: [root.path], action: .removeContents)], mode: .deletePermanently, administratorPrompt: "x")
        #expect(result.allSatisfy { $0.succeeded })
        #expect(FileManager.default.fileExists(atPath: root.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func removeFolderDeletesTheFolderItself() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "DerivedData")
        try write("x.bin", in: target)
        let result = await remover().remove([item("d", paths: [target.path], action: .removeFolder)], mode: .deletePermanently, administratorPrompt: "x")
        #expect(result.allSatisfy { $0.succeeded })
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func symlinkedChildrenAreLeftAloneAndTheirTargetsSurvive() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: outside) }
        try write("precious.bin", in: outside)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        try write("real.bin", in: cache)
        try FileManager.default.createSymbolicLink(at: cache.appending(path: "link"), withDestinationURL: outside)
        _ = await remover().remove([item("c", paths: [cache.path], action: .removeContents)], mode: .deletePermanently, administratorPrompt: "x")
        #expect(FileManager.default.fileExists(atPath: outside.appending(path: "precious.bin").path))
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "link").path))
        #expect(!FileManager.default.fileExists(atPath: cache.appending(path: "real.bin").path))
    }

    @Test func olderThanKeepsFreshChildrenAndFoldersWithFreshFiles() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("old.bin", in: root, age: 10)
        try write("fresh.bin", in: root, age: 0)
        try write("mixed/old.bin", in: root, age: 10)
        try write("mixed/fresh.bin", in: root, age: 0)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 86_400)], ofItemAtPath: root.appending(path: "mixed").path)
        _ = await remover().remove([item("t", paths: [root.path], action: .removeContentsOlderThan(days: 3))], mode: .deletePermanently, administratorPrompt: "x")
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
        #expect(left == ["fresh.bin", "mixed"])
    }

    @Test func aRunningAppBlocksOnlyItsOwnItem() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appending(path: "blocked"), free = root.appending(path: "free")
        try write("x.bin", in: blocked)
        try write("y.bin", in: free)
        let items = [item("blocked", paths: [blocked.path], action: .removeContents, busy: ["com.example.app"]),
                     item("free", paths: [free.path], action: .removeContents)]
        let result = await remover(running: { $0 == "com.example.app" ? "Example" : nil }).remove(items, mode: .deletePermanently, administratorPrompt: "x")
        #expect(result.map(\.succeeded) == [false, true])
        #expect(FileManager.default.fileExists(atPath: blocked.appending(path: "x.bin").path))
        #expect(!FileManager.default.fileExists(atPath: free.appending(path: "y.bin").path))
    }

    @Test func commandItemsRunTheirCommandAndReportFailure() async {
        let command = SystemDataCommand("/usr/bin/true", ["a b"])
        let ran = Locked<[SystemDataCommand]>([])
        let outcomes = await remover(runCommand: { cmd, _ in
            ran.mutate { $0.append(cmd) }
            return cmd.arguments.first == "a b" ? (0, "") : (2, "boom")
        }).remove([item("ok", paths: [], action: .run(command)),
                   item("bad", paths: [], action: .run(SystemDataCommand("/usr/bin/false", ["x"])))],
                  mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcomes.map(\.succeeded) == [true, false])
        #expect(ran.value.count == 2)
        #expect(outcomes[1].error?.contains("boom") == true)
    }

    @Test func aCommandWithAdministratorFallbackAsksForAPasswordOnlyWhenTheUserRunFails() async {
        let calls = Locked<[Bool]>([])
        let command = SystemDataCommand("/usr/bin/tmutil", ["deletelocalsnapshots", "2026-11-01-120000"], administratorFallback: true)
        let it = item("snap", paths: [], action: .run(command))
        let failingFirst = await remover(runCommand: { cmd, _ in calls.mutate { $0.append(cmd.asAdministrator) }; return cmd.asAdministrator ? (0, "") : (1, "Operation not permitted") })
            .remove([it], mode: .deletePermanently, administratorPrompt: "x")
        #expect(failingFirst.allSatisfy { $0.succeeded })
        #expect(calls.value == [false, true])

        let ok = Locked<[Bool]>([])
        _ = await remover(runCommand: { cmd, _ in ok.mutate { $0.append(cmd.asAdministrator) }; return (0, "") }).remove([it], mode: .deletePermanently, administratorPrompt: "x")
        #expect(ok.value == [false], "no password prompt when the plain run works")

        let plain = Locked<Int>(0)
        let strict = item("strict", paths: [], action: .run(SystemDataCommand("/usr/bin/true")))
        let outcome = await remover(runCommand: { _, _ in plain.mutate { $0 += 1 }; return (1, "no") }).remove([strict], mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcome.allSatisfy { !$0.succeeded } && plain.value == 1, "no fallback unless the command asks for it")
    }

    @Test func theAdministratorScriptQuotesEveryWordAndCannotBeBrokenOutOf() {
        let hostile = SystemDataCommand("/usr/bin/tmutil", ["deletelocalsnapshots", "x'; rm -rf ~ #", "a b", "quote\"\\"], asAdministrator: true)
        let script = SystemDataRemover.administratorScript(for: hostile, prompt: "MacPocket \"needs\" permission")
        #expect(script.hasPrefix("do shell script \""))
        #expect(script.hasSuffix(" with administrator privileges"))
        // The hostile word appears only inside shell single quotes, with the embedded quote closed and
        // reopened.
        #expect(script.contains("'x'\\\\''; rm -rf ~ #'"))
        #expect(script.contains("with prompt \"MacPocket \\\"needs\\\" permission\""))
        #expect(!script.contains("; rm -rf ~ #\" with"))
    }

    @Test func aCancelledPasswordDialogIsReportedAsDeclinedNotAsAToolFailure() async {
        let command = SystemDataCommand("/usr/bin/tmutil", ["deletelocalsnapshots", "2026-11-01-120000"], administratorFallback: true)
        let outcome = await remover(runCommand: { cmd, _ in cmd.asAdministrator ? (1, "execution error: User canceled. (-128)") : (1, "Operation not permitted") })
            .remove([item("snap", paths: [], action: .run(command))], mode: .deletePermanently, administratorPrompt: "x")
        #expect(outcome.first?.succeeded == false)
        #expect(outcome.first?.error == FileRemovalError.administratorDeclined.localizedDescription)
    }

    @Test func manualItemsAreNeverRemoved() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("x.bin", in: root)
        let result = await remover().remove([item("m", paths: [root.path], action: .manual(hint: "by hand"))], mode: .deletePermanently, administratorPrompt: "x")
        #expect(result.first?.succeeded == false)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "x.bin").path))
    }

    @Test func previewShowsVerbatimOperationsAndFlagsAdministratorWork() {
        let home = URL(fileURLWithPath: "/Users/me")
        let items = [
            item("home", paths: ["/Users/me/Library/Caches/Homebrew"], action: .removeContents),
            item("sys", paths: ["/Library/Caches"], action: .removeContents),
            item("cmd", paths: [], action: .run(SystemDataCommand("/usr/bin/tmutil", ["deletelocalsnapshots", "2026-11-01-120000"], asAdministrator: true))),
            item("manual", paths: ["/x"], action: .manual(hint: "hand")),
        ]
        let preview = SystemDataRemovalPlanner.preview(items: items, mode: .deletePermanently, home: home,
                                                       temporaryDirectory: URL(fileURLWithPath: "/private/var/folders/xx/T"))
        #expect(preview.lines.count == 3)
        #expect(preview.lines[0].operations == ["rm -rf -- /Users/me/Library/Caches/Homebrew/*"])
        #expect(preview.lines[1].requiresAdministrator)
        #expect(preview.lines[2].operations.first?.contains("tmutil deletelocalsnapshots 2026-11-01-120000") == true)
        #expect(preview.administratorLineCount == 2)
        #expect(preview.copyText.contains("rm -rf --"))
    }

    @Test func previewQuotesPathsWithSpacesAndCountsNetworkBytes() {
        var network = item("n", paths: ["/Users/me/Library/Application Support/X Y"], action: .removeFolder)
        network = SystemDataItem(id: network.id, group: .packages, title: "n", detail: "", safety: .review, regeneration: .downloadsAgain,
                                 paths: network.paths, sizeBytes: 5_000, action: .removeFolder)
        let preview = SystemDataRemovalPlanner.preview(items: [network], mode: .deletePermanently, home: URL(fileURLWithPath: "/Users/me"))
        #expect(preview.lines[0].operations == ["rm -rf -- '/Users/me/Library/Application Support/X Y'"])
        #expect(preview.networkBytes == 5_000)
    }
}

/// Minimal lock-protected box so a `@Sendable` closure can record what it saw.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}

@Suite struct SystemDataUnattendedRemovalTests {
    @Test func withoutAPromptAnAdministratorCommandIsNeverStartedAndNoFallbackRuns() async {
        let started = Locked<Int>(0)
        let remover = SystemDataRemover(runCommand: { _, _ in started.mutate { $0 += 1 }; return (0, "") })
        func item(_ id: String, _ command: SystemDataCommand) -> SystemDataItem {
            SystemDataItem(id: id, group: .system, title: id, detail: "", safety: .review, regeneration: .rebuildsLocally,
                           paths: [], sizeBytes: 1, action: .run(command))
        }
        let outcomes = await remover.remove([item("admin", SystemDataCommand("/usr/bin/true", asAdministrator: true)),
                                             item("fallback", SystemDataCommand("/usr/bin/false", administratorFallback: true))],
                                            mode: .deletePermanently, administratorPrompt: nil)
        #expect(outcomes.map(\.succeeded) == [false, true], "the fallback item ran once as the user (the fake runner reports success)")
        #expect(started.value == 1, "the administrator command never started")
    }
}
