import Foundation
import Testing
@testable import SSHConfigKit

struct SSHImporterTests {
    private static let privateKey = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmU=\n-----END OPENSSH PRIVATE KEY-----\n"
    private static let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPfUPYg1znbIXwm8qtmbk2fUgbpCS0X0aPBTqX90D7ND old-mac\n"

    /// A new Mac (`home/.ssh`) and a folder copied from the old one (`iCloud/ssh`).
    private func makeSetup(config: String, keys: [String] = ["id_ed25519"]) throws -> (tmp: TempDir, importer: SSHImporter, source: URL, destination: URL) {
        let tmp = try TempDir()
        let destination = tmp.url.appending(path: "home/.ssh")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try tmp.file("iCloud/ssh/config", config)
        for name in keys {
            try tmp.file("iCloud/ssh/\(name)", Self.privateKey)
            try tmp.file("iCloud/ssh/\(name).pub", Self.publicKey, permissions: 0o644)
        }
        let importer = SSHImporter(home: tmp.url.appending(path: "home"), destination: destination)
        return (tmp, importer, tmp.url.appending(path: "iCloud/ssh"), destination)
    }

    private func permissions(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    @Test func importsHostsKeysAndGroupsFromAFolder() throws {
        let setup = try makeSetup(config: """
            # group: Work
            Host web
              HostName 10.0.0.1
              User deploy
              IdentityFile ~/.ssh/id_ed25519
            Host *
              ServerAliveInterval 30

            """)
        var document = ConfigDocument(parsing: "")
        let plan = setup.importer.plan(source: setup.source, into: document)
        // A first run on a new Mac has no ~/.ssh yet; the importer must create it private.
        try FileManager.default.removeItem(at: setup.destination)
        #expect(plan.hosts.map(\.id) == ["web"])
        #expect(plan.hosts.first?.group == "Work")
        #expect(plan.keys.map(\.name) == ["id_ed25519"])
        #expect(plan.keys.first?.disposition == .copy)

        let copied = try setup.importer.copyKeys(of: plan)
        #expect(copied == ["id_ed25519"])
        try SSHImporter.addHosts(of: plan, to: &document)
        #expect(document.render().contains("# group: Work"))
        #expect(document.render().contains("HostName 10.0.0.1"))
        #expect(!document.render().contains("ServerAliveInterval"), "wildcard blocks are not imported")
        #expect(try permissions(setup.destination.appending(path: "id_ed25519")) == 0o600)
        #expect(try permissions(setup.destination.appending(path: "id_ed25519.pub")) == 0o644)
        #expect(try permissions(setup.destination) == 0o700)
    }

    @Test func acceptsTheConfigFileItselfAndFindsKeysBesideIt() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a.example\n")
        let plan = setup.importer.plan(source: setup.source.appending(path: "config"), into: .empty)
        #expect(plan.hosts.map(\.id) == ["a"])
        #expect(plan.keys.map(\.name) == ["id_ed25519"])
    }

    @Test func followsIncludesRelativeToTheSourceFolderAndFlattensThem() throws {
        let setup = try makeSetup(config: "Include conf.d/*\nHost main\n  HostName m.example\n", keys: [])
        try setup.tmp.file("iCloud/ssh/conf.d/extra", "Host extra\n  HostName e.example\n")
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        #expect(plan.hosts.map(\.id) == ["main", "extra"])
        #expect(plan.hosts.last?.origin?.lastPathComponent == "extra")
        var document = ConfigDocument(parsing: "")
        try SSHImporter.addHosts(of: plan, to: &document)
        #expect(!document.render().contains("Include"), "imported hosts are written into the config itself")
        #expect(document.hosts.map(\.alias) == ["main", "extra"])
    }

    @Test func skipsAliasesTheConfigurationAlreadyHas() throws {
        let setup = try makeSetup(config: "Host web\n  HostName new.example\nHost db\n  HostName db.example\n", keys: [])
        let existing = ConfigDocument(parsing: "Host web\n  HostName mine.example\n")
        let plan = setup.importer.plan(source: setup.source, into: existing, existingAliases: ["db"])
        #expect(plan.hosts.isEmpty)
        #expect(plan.skippedHosts == ["web", "db"])
    }

    @Test func aKeyIdenticalToTheOneInstalledIsNotCopiedAgain() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n  IdentityFile ~/.ssh/id_ed25519\n")
        try Data(Self.privateKey.utf8).write(to: setup.destination.appending(path: "id_ed25519"))
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        #expect(plan.keys.first?.disposition == .alreadyPresent)
        #expect(try setup.importer.copyKeys(of: plan).isEmpty)
    }

    @Test func aDifferentKeyWithTheSameNameIsRenamedAndHostsFollow() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n  IdentityFile ~/.ssh/id_ed25519\n")
        let other = "-----BEGIN OPENSSH PRIVATE KEY-----\ndifferent\n-----END OPENSSH PRIVATE KEY-----\n"
        try Data(other.utf8).write(to: setup.destination.appending(path: "id_ed25519"))
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        #expect(plan.keys.first?.disposition == .renamed(to: "id_ed25519_2"))
        #expect(try setup.importer.copyKeys(of: plan) == ["id_ed25519_2"])
        // The installed key is untouched.
        #expect(try String(contentsOf: setup.destination.appending(path: "id_ed25519"), encoding: .utf8) == other)
        var document = ConfigDocument(parsing: "")
        try SSHImporter.addHosts(of: plan, to: &document)
        #expect(document.hosts.first?.value(for: "IdentityFile") == "~/.ssh/id_ed25519_2")
    }

    @Test func rewritesAbsoluteIdentityFilesFromTheOldMachine() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n  IdentityFile /Users/old/.ssh/id_ed25519\n")
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        var document = ConfigDocument(parsing: "")
        try SSHImporter.addHosts(of: plan, to: &document)
        #expect(document.hosts.first?.value(for: "IdentityFile") == "~/.ssh/id_ed25519")
    }

    @Test func warnsAboutAKeyNothingProvides() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n  IdentityFile ~/.ssh/ghost\n", keys: [])
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        #expect(plan.warnings.contains(.missingKey(host: "a", path: "~/.ssh/ghost")))
        #expect(plan.hosts.first?.draft.directives.first { $0.key == "IdentityFile" }?.value == "~/.ssh/ghost")
    }

    @Test func reportsFilesICloudHasNotDownloadedYet() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n", keys: [])
        try setup.tmp.file("iCloud/ssh/.id_work.icloud", "")
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        #expect(plan.warnings.contains(.notDownloaded("id_work")))
    }

    @Test func reportsAFolderWithNothingToImport() throws {
        let tmp = try TempDir()
        try FileManager.default.createDirectory(at: tmp.url.appending(path: "empty"), withIntermediateDirectories: true)
        let importer = SSHImporter(home: tmp.url, destination: tmp.url.appending(path: ".ssh"))
        let plan = importer.plan(source: tmp.url.appending(path: "empty"), into: .empty)
        #expect(plan.isEmpty)
        #expect(plan.warnings.contains(.noConfigFound))
    }

    @Test func doesNotTreatNonKeyFilesAsKeys() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n", keys: [])
        try setup.tmp.file("iCloud/ssh/known_hosts", "a ssh-ed25519 AAAA\n")
        try setup.tmp.file("iCloud/ssh/notes.txt", "hello\n")
        #expect(setup.importer.plan(source: setup.source, into: .empty).keys.isEmpty)
    }

    @Test func neverOverwritesAnExistingPublicKey() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n")
        let existing = "ssh-ed25519 AAAAexisting mine\n"
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        try Data(existing.utf8).write(to: setup.destination.appending(path: "id_ed25519.pub"))
        _ = try setup.importer.copyKeys(of: plan)
        #expect(try String(contentsOf: setup.destination.appending(path: "id_ed25519.pub"), encoding: .utf8) == existing)
    }

    @Test func aRaceForTheTargetNameFailsInsteadOfOverwriting() throws {
        let setup = try makeSetup(config: "Host a\n  HostName a\n")
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        // The name is taken after planning.
        try Data("precious".utf8).write(to: setup.destination.appending(path: "id_ed25519"))
        #expect(throws: (any Error).self) { try setup.importer.copyKeys(of: plan) }
        #expect(try String(contentsOf: setup.destination.appending(path: "id_ed25519"), encoding: .utf8) == "precious")
    }

    @Test func reportsMatchBlocksItDoesNotImport() throws {
        let setup = try makeSetup(config: "Match host x\n  User y\nHost a\n  HostName a\n", keys: [])
        #expect(setup.importer.plan(source: setup.source, into: .empty).warnings.contains(.matchBlocksSkipped(1)))
    }

    @Test func aNonUTF8ConfigIsReportedNotCrashed() throws {
        let setup = try makeSetup(config: "", keys: [])
        try Data([0xFF, 0xFE, 0x00]).write(to: setup.source.appending(path: "config"))
        let plan = setup.importer.plan(source: setup.source, into: .empty)
        #expect(plan.warnings.contains(.notUTF8(setup.source.appending(path: "config").path)))
    }
}
