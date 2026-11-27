import Foundation
import XCTest
@testable import MacPocketAIUsage

final class ClaudeProfileDiscoveryTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClaudeDiscovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func directory(_ root: URL, _ path: String, marker: Bool = false) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Deliberately invalid credential data: discovery must inspect only the name, never parse it.
        if marker { try Data("not credentials".utf8).write(to: url.appending(path: ".credentials.json")) }
        return url
    }
    func testFindsDefaultEnvironmentAndNamedProfilesWithoutReadingCredentials() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let standard = try directory(home, ".claude")
        let work = try directory(home, ".claude-work", marker: true)
        let custom = try directory(home, "config/agency")
        let nested = try directory(home, ".claude-profiles/personal", marker: true)
        _ = try directory(home, ".claude-unrelated")
        _ = try directory(home, "unrelated/project/.claude", marker: true)
        let result = ClaudeProfileDiscovery.find(home: home, environment: ["CLAUDE_CONFIG_DIR": custom.path])
        XCTAssertEqual(Set(result.folders.map(\.directory.path)), Set([standard.path, work.path, custom.path, nested.path]))
        XCTAssertEqual(result.folders.first?.directory.path, standard.path)
        XCTAssertFalse(result.incomplete)
    }
    func testKnownProfilesRetainNamesAndSymlinkAliasesDoNotDuplicateAccounts() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = try directory(home, "Library/Application Support/MacPocket/AIUsage/ClaudeProfiles/profile-id")
        let alias = home.appending(path: ".claude-work")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: profile)
        let account = AIUsageAccount(name: "Agency", source: .claudeProfile(directory: profile.path, service: nil))
        let result = ClaudeProfileDiscovery.find(home: home, environment: [:], accounts: [account])
        XCTAssertEqual(result.folders.count, 1)
        XCTAssertEqual(result.folders.first?.name, "Agency")
    }
    func testPastedTildePathsAndMissingFolders() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertEqual(ClaudeProfileDiscovery.folderURL("  ~/.claude-work  ", home: home)?.path, home.appending(path: ".claude-work").path)
        XCTAssertNil(ClaudeProfileDiscovery.folderURL("relative/path", home: home))
        XCTAssertNil(ClaudeProfileDiscovery.folderURL("/tmp/line\nbreak", home: home))
        let result = ClaudeProfileDiscovery.find(home: home, environment: ["CLAUDE_CONFIG_DIR": home.appending(path: "missing").path])
        XCTAssertTrue(result.folders.isEmpty)
        XCTAssertFalse(result.incomplete)
    }
    func testDefaultUsesBaseKeychainButCustomProfileNeverBorrowsIt() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let standard = try directory(home, ".claude"), custom = try directory(home, ".claude-work", marker: true)
        let entry = ClaudeKeychainEntry(service: "Claude Code-credentials", account: "test")
        XCTAssertEqual(ClaudeProfileDiscovery.source(for: standard, home: home, entries: [entry], username: "test"),
            .claudeKeychain(service: entry.service, account: "test"))
        XCTAssertEqual(ClaudeProfileDiscovery.source(for: custom, home: home, entries: [entry], username: "test"),
            .claudeProfile(directory: custom.path, service: nil))
        let scoped = ClaudeKeychainEntry(service: AIUsageCredentials.claudeServiceCandidate(directory: custom.path), account: "test")
        XCTAssertEqual(ClaudeProfileDiscovery.source(for: custom, home: home, entries: [entry, scoped], username: "test"),
            .claudeProfile(directory: custom.path, service: scoped.service))
    }
    func testSearchBoundsLargeProfileLists() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        for i in 0..<70 { _ = try directory(home, "Library/Application Support/MacPocket/AIUsage/ClaudeProfiles/\(i)") }
        let result = ClaudeProfileDiscovery.find(home: home, environment: [:])
        XCTAssertEqual(result.folders.count, 64)
        XCTAssertTrue(result.incomplete)
    }
}
