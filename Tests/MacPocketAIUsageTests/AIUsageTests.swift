import Foundation
import XCTest
import UsageCore
@testable import MacPocketAIUsage

final class AIUsageAccountTests: XCTestCase {
    func testDuplicateSourcesAreRemovedWithoutMergingDifferentClaudeAccounts() {
        var settings = AIUsageSettings()
        let work = AIUsageAccount(name: "Work", source: .claudeKeychain(service: "Claude Code-credentials-work", account: "test"))
        let personal = AIUsageAccount(name: "Personal", source: .claudeKeychain(service: "Claude Code-credentials-personal", account: "test"))
        settings.accounts = [work, personal, AIUsageAccount(name: "Duplicate", source: work.source)]
        XCTAssertEqual(settings.normalized.accounts.map(\.id), [work.id, personal.id])
        XCTAssertNotEqual(work.source.identity, personal.source.identity)
    }
    func testSettingsPersistOnlyCredentialLocations() throws {
        var settings = AIUsageSettings()
        settings.accounts = [AIUsageAccount(name: "Work", source: .claudeProfile(directory: "/tmp/work", service: nil))]
        let text = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertFalse(text.contains("accessToken")); XCTAssertFalse(text.contains("refreshToken"))
        XCTAssertEqual(try JSONDecoder().decode(AIUsageSettings.self, from: Data(text.utf8)), settings)
    }
    func testOlderSettingsRetainAccountsWhenNewOptionsAreMissing() throws {
        let account = AIUsageAccount(name: "Work", source: .claudeProfile(directory: "/tmp/work", service: nil))
        let data = try JSONSerialization.data(withJSONObject: ["accounts": try JSONSerialization.jsonObject(with: JSONEncoder().encode([account]))])
        let settings = try JSONDecoder().decode(AIUsageSettings.self, from: data)
        XCTAssertEqual(settings.accounts, [account]); XCTAssertEqual(settings.warning, 65)
        XCTAssertFalse(settings.alertsEnabled)
    }
    func testClaudeCredentialFilesAreReadIndependently() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, token) in [("work", "fixture-work"), ("personal", "fixture-personal")] {
            let data = try JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": token, "expiresAt": 4_102_444_800_000] as [String: Any]])
            let url = root.appending(path: name)
            try data.write(to: url)
            let credential = try AIUsageCredentials.ClaudeFileReader(fileURL: url).readClaudeToken()
            XCTAssertEqual(credential.accessToken, token)
            XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 4_102_444_800))
        }
        let malformed = root.appending(path: "malformed")
        try Data("{}".utf8).write(to: malformed)
        XCTAssertThrowsError(try AIUsageCredentials.ClaudeFileReader(fileURL: malformed).readClaudeToken())
        XCTAssertThrowsError(try AIUsageCredentials.ClaudeFileReader(fileURL: root.appending(path: "missing")).readClaudeToken())
    }
    func testClaudeLoginKeepsQuotedProfileEvenWhenLoginShellOverridesEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeCLI = root.appending(path: "claude")
        try "#!/bin/zsh\nprint -rn -- \"$CLAUDE_CONFIG_DIR\" > \"$MACPOCKET_LOGIN_TEST_OUTPUT\"\n[[ \"$1 $2\" == 'auth login' ]]\n"
            .write(to: fakeCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCLI.path)
        let output = root.appending(path: "result")
        let profile = root.appending(path: "Work's $(echo WRONG) Profile").path
        let zprofile = "export CLAUDE_CONFIG_DIR=/wrong-profile\nexport PATH='" + root.path + "':/usr/bin:/bin\n"
        try zprofile.write(to: root.appending(path: ".zprofile"), atomically: true, encoding: .utf8)
        let script = root.appending(path: "login.command")
        try ClaudeProfileLogin.script(directory: profile).write(to: script, atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = [script.path]
        process.environment = ["ZDOTDIR": root.path, "MACPOCKET_LOGIN_TEST_OUTPUT": output.path, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), profile)
    }
    func testHTTPClientRejectsUnexpectedOriginsBeforeSendingCredentials() async {
        do {
            _ = try await AIUsageHTTPClient().get(URL(string: "https://example.invalid/usage")!, headers: ["Authorization": "Bearer fixture"])
            XCTFail("Unexpected origin must not receive credentials")
        } catch let error as URLError { XCTAssertEqual(error.code, .unsupportedURL) }
        catch { XCTFail("Unexpected error: \(error)") }
    }
    func testDisplayModeClampsWithoutInventingNegativeRemainingQuota() {
        XCTAssertEqual(AIUsageDisplayMode.remaining.percent(82), 18)
        XCTAssertEqual(AIUsageDisplayMode.remaining.percent(112), 0)
        XCTAssertEqual(AIUsageDisplayMode.used.percent(-2), 0)
    }
    func testSourcePathsMustBeAbsoluteAndFreeOfControlCharacters() {
        XCTAssertFalse(AIUsageSource.claudeProfile(directory: "relative", service: nil).isValid)
        XCTAssertFalse(AIUsageSource.codexFile(path: "/tmp/a\nauth.json").isValid)
        XCTAssertTrue(AIUsageSource.claudeProfile(directory: "/tmp/Work Account", service: nil).isValid)
    }
}

private final class UsageFixtureProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .claude
    let percent: Double
    var status: FetchStatus
    let delay: Duration
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.withLock { calls } }
    init(_ percent: Double, status: FetchStatus = .ok, delay: Duration = .zero) {
        self.percent = percent; self.status = status; self.delay = delay
    }
    func fetch() async throws -> FetchOutcome {
        lock.withLock { calls += 1 }
        if delay != .zero { try await Task.sleep(for: delay) }
        let limits = status == .ok ? [UsageLimit(id: "session", label: "Session", percentUsed: percent,
            resetsAt: Date().addingTimeInterval(3600), severity: .normal)] : []
        return FetchOutcome(snapshot: .init(provider: .claude, fetchedAt: .now, limits: limits, status: status), requestSent: true)
    }
}

@MainActor
final class AIUsageServiceTests: XCTestCase {
    private var suite: String = ""
    private var defaults: UserDefaults!
    override func setUp() async throws {
        suite = "MacPocket.AIUsageTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }
    private func account(_ name: String) -> AIUsageAccount {
        .init(name: name, source: .claudeKeychain(service: "Claude Code-credentials-" + name, account: "test"))
    }
    func testTwoClaudeAccountsKeepSeparateSnapshotsAndThrottles() async {
        let work = account("Work"), personal = account("Personal")
        let w = UsageFixtureProvider(82), p = UsageFixtureProvider(25)
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { account, _, _ in account.id == work.id ? w : p }
        XCTAssertTrue(service.add(work)); XCTAssertTrue(service.add(personal))
        service.setEnabled(true)
        await service.refresh()
        XCTAssertEqual(service.snapshot(for: work)?.headlineLimit?.percentUsed, 82)
        XCTAssertEqual(service.snapshot(for: personal)?.headlineLimit?.percentUsed, 25)
        await service.refresh(manual: true)
        XCTAssertEqual(w.count, 1); XCTAssertEqual(p.count, 1)
        XCTAssertTrue(service.menuBarReading.lines[0].contains("18%"))
        XCTAssertTrue(service.menuBarReading.lines[0].contains("75%"))
        service.stop()
    }
    func testDisabledServiceAndAccountsMakeNoRequests() async {
        let provider = UsageFixtureProvider(20)
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { _, _, _ in provider }
        var entry = account("Work"); entry.enabled = false
        XCTAssertTrue(service.add(entry))
        await service.refresh(manual: true)
        service.setEnabled(true)
        await service.refresh(manual: true)
        XCTAssertEqual(provider.count, 0)
        service.stop()
    }
    func testRemovingOneAccountDoesNotClearAnotherAccount() async {
        let w = account("Work"), p = account("Personal"), provider = UsageFixtureProvider(20)
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { _, _, _ in provider }
        _ = service.add(w); _ = service.add(p); service.setEnabled(true); await service.refresh()
        service.remove(w.id)
        XCTAssertNil(service.snapshot(for: w)); XCTAssertNotNil(service.snapshot(for: p))
        service.stop()
    }
    func testLateResponseCannotRestoreRemovedAccount() async {
        let entry = account("Work"), provider = UsageFixtureProvider(20, delay: .milliseconds(80))
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { _, _, _ in provider }
        _ = service.add(entry); service.setEnabled(true)
        let task = Task { await service.refresh() }
        await Task.yield(); service.remove(entry.id); await task.value
        XCTAssertNil(service.snapshot(for: entry)); XCTAssertTrue(service.refreshing.isEmpty)
        service.stop()
    }
    func testAlertsAreIndependentForTwoAccounts() async {
        let w = account("Work"), p = account("Personal"), provider = UsageFixtureProvider(90)
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { _, _, _ in provider }
        _ = service.add(w); _ = service.add(p)
        var settings = service.settings; settings.alertsEnabled = true; service.setSettings(settings)
        var received: [AIUsageNotice] = []; service.onAlerts = { received += $0 }
        service.setEnabled(true); await service.refresh()
        XCTAssertEqual(Set(received.map(\.accountID)), Set([w.id, p.id]))
        XCTAssertEqual(received.count, 2)
        XCTAssertTrue(received.allSatisfy { $0.level == .critical })
        service.stop()
    }
    func testRenamingAndDisplayChangesDoNotCancelInFlightReadings() async {
        var entry = account("Work")
        let provider = UsageFixtureProvider(42, delay: .milliseconds(30))
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { _, _, _ in provider }
        _ = service.add(entry); service.setEnabled(true)
        let request = Task { await service.refresh() }
        for _ in 0..<100 where provider.count == 0 { await Task.yield() }
        entry.name = "Renamed"; service.update(entry)
        var settings = service.settings; settings.mode = .used; settings.floatingPanel = true; service.setSettings(settings)
        await request.value
        XCTAssertEqual(service.snapshot(for: entry)?.headlineLimit?.percentUsed, 42)
        XCTAssertEqual(provider.count, 1); XCTAssertTrue(service.menuBarReading.lines[0].contains("42%"))
        entry.name = ""; service.update(entry)
        XCTAssertEqual(service.settings.accounts.count, 1, "Editing a name must never delete an account")
        service.stop()
    }
    func testCacheDoesNotReuseDataAfterProfileCredentialBindingChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appending(path: "quota.json")
        var entry = AIUsageAccount(name: "Work", source: .claudeProfile(directory: root.appending(path: "profile").path, service: "Claude Code-credentials-work"))
        let provider = UsageFixtureProvider(20)
        let service = AIUsageService(defaults: defaults, cacheURL: cache) { _, _, _ in provider }
        _ = service.add(entry); service.setEnabled(true); await service.refresh(); service.stop()
        let restored = AIUsageService(defaults: defaults, cacheURL: cache) { _, _, _ in provider }
        XCTAssertEqual(restored.snapshot(for: entry)?.headlineLimit?.percentUsed, 20)
        entry.source = .claudeProfile(directory: root.appending(path: "profile").path, service: "Claude Code-credentials-other")
        var settings = service.settings; settings.accounts = [entry]; settings.save(to: defaults)
        let changed = AIUsageService(defaults: defaults, cacheURL: cache) { _, _, _ in provider }
        XCTAssertNil(changed.snapshot(for: entry))
        let attributes = try FileManager.default.attributesOfItem(atPath: cache.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testLateResponseCannotRestoreDisabledService() async {
        let entry = account("Work"), provider = UsageFixtureProvider(20, delay: .milliseconds(30))
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { _, _, _ in provider }
        _ = service.add(entry); service.setEnabled(true)
        let request = Task { await service.refresh() }
        for _ in 0..<100 where provider.count == 0 { await Task.yield() }
        service.stop(); await request.value
        XCTAssertFalse(service.active); XCTAssertTrue(service.refreshing.isEmpty)
        XCTAssertNil(service.snapshot(for: entry))
    }
    func testRateLimitDoesNotBlockOtherClaudeAccount() async {
        let w = account("Work"), p = account("Personal")
        let limited = UsageFixtureProvider(0, status: .rateLimited(until: .now.addingTimeInterval(600), wait: 600))
        let healthy = UsageFixtureProvider(20)
        let service = AIUsageService(defaults: defaults, cacheURL: nil) { a, _, _ in a.id == w.id ? limited : healthy }
        _ = service.add(w); _ = service.add(p); service.setEnabled(true); await service.refresh()
        XCTAssertNotNil(service.snapshot(for: p)?.headlineLimit)
        XCTAssertTrue(service.nextRefresh(for: w, manual: true) > service.nextRefresh(for: p, manual: true))
        service.stop()
    }
}
