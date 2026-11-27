import Foundation
import Testing
@testable import SSHConfigKit

struct SystemLinkerTests {
    private struct Setup {
        let tmp: TempDir
        let home: URL
        let cloudConfig: URL
        let cloudKnownHosts: URL
        let linker: SystemLinker
    }

    /// A clean Mac: empty home; the app's files live in a folder whose path has spaces, like iCloud Drive's.
    private func makeSetup(systemConfig: String? = nil, systemKnownHosts: String? = nil) throws -> Setup {
        let tmp = try TempDir()
        let home = tmp.url.appending(path: "home")
        try FileManager.default.createDirectory(at: home.appending(path: ".ssh"), withIntermediateDirectories: true)
        let cloud = "home/Library/Mobile Documents/com~apple~CloudDocs/SSH"
        let config = try tmp.file("\(cloud)/config", "Host web\n  HostName 10.0.0.1\n")
        let known = try tmp.file("\(cloud)/known_hosts", "a ssh-ed25519 AAAA1\n# comment\n\nb ssh-ed25519 AAAA2\na ssh-ed25519 AAAA1\n")
        if let systemConfig { try tmp.file("home/.ssh/config", systemConfig) }
        if let systemKnownHosts { try tmp.file("home/.ssh/known_hosts", systemKnownHosts) }
        let backups = BackupManager(rootDirectory: tmp.url.appending(path: "backups"))
        return Setup(tmp: tmp, home: home, cloudConfig: config, cloudKnownHosts: known,
                     linker: SystemLinker(home: home, backups: backups))
    }

    @Test func aCleanSystemGetsAQuotedIncludeAtTheTop() throws {
        let setup = try makeSetup()
        let plan = setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts)
        let change = try #require(plan.configChange)
        #expect(change.old.isEmpty)
        #expect(change.new.contains("Include \"~/Library/Mobile Documents/com~apple~CloudDocs/SSH/config\"\n"))
        // ssh must be able to read what we wrote.
        let document = ConfigDocument(parsing: change.new)
        #expect(document.includes.flatMap(\.paths) == ["~/Library/Mobile Documents/com~apple~CloudDocs/SSH/config"])
    }

    @Test func existingSystemConfigIsKeptBelowTheInclude() throws {
        let setup = try makeSetup(systemConfig: "Host *\n  ServerAliveInterval 30\n")
        let change = try #require(setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts).configChange)
        #expect(change.new.hasSuffix("\nHost *\n  ServerAliveInterval 30\n"))
        #expect(change.new.range(of: "Include")!.lowerBound < change.new.range(of: "Host *")!.lowerBound)
    }

    @Test func applyingTwiceChangesNothingTheSecondTime() throws {
        let setup = try makeSetup()
        let first = setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts)
        try setup.linker.apply(first)
        let second = setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts)
        #expect(second.isNoop)
        #expect(try setup.tmp.read("home/.ssh/config").components(separatedBy: "Include").count == 2)
    }

    @Test func theSystemSeesTheCloudHostThroughTheInclude() throws {
        let setup = try makeSetup()
        try setup.linker.apply(setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts))
        let resolver = IncludeResolver(homeDirectory: setup.home)
        let system = ConfigDocument(parsing: try setup.tmp.read("home/.ssh/config"))
        #expect(resolver.includedHosts(of: system, rootFile: setup.home.appending(path: ".ssh/config")).map(\.entry.alias) == ["web"])
    }

    @Test func knownHostsAreMergedWithoutDuplicatesComments() throws {
        let setup = try makeSetup(systemKnownHosts: "a ssh-ed25519 AAAA1\n")
        let plan = setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts)
        #expect(plan.knownHostsToAdd == ["b ssh-ed25519 AAAA2"])
        try setup.linker.apply(plan)
        #expect(try setup.tmp.read("home/.ssh/known_hosts") == "a ssh-ed25519 AAAA1\nb ssh-ed25519 AAAA2\n")
    }

    @Test func aKnownHostsFileWithoutTrailingNewlineIsNotGlued() throws {
        let setup = try makeSetup(systemKnownHosts: "z ssh-ed25519 AAAAz")
        try setup.linker.apply(setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts))
        #expect(try setup.tmp.read("home/.ssh/known_hosts").hasPrefix("z ssh-ed25519 AAAAz\na ssh-ed25519 AAAA1\n"))
    }

    @Test func existingFilesAreBackedUpBeforeTheyChange() throws {
        let setup = try makeSetup(systemConfig: "Host old\n  HostName o\n", systemKnownHosts: "z ssh-ed25519 AAAAz\n")
        try setup.linker.apply(setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts))
        let backups = BackupManager(rootDirectory: setup.tmp.url.appending(path: "backups"))
        #expect(try backups.contents(of: backups.list(kind: "system-config")[0]) == "Host old\n  HostName o\n")
        #expect(try backups.list(kind: "system-known-hosts").count == 1)
    }

    @Test func aSymlinkedSystemConfigIsFollowedAndTheLinkKept() throws {
        let setup = try makeSetup()
        let real = try setup.tmp.file("dotfiles/ssh_config", "Host dot\n")
        try FileManager.default.createSymbolicLink(at: setup.home.appending(path: ".ssh/config"), withDestinationURL: real)
        let plan = setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts)
        #expect(plan.notes.contains(.configIsSymlink(real.path)))
        try setup.linker.apply(plan)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: setup.home.appending(path: ".ssh/config").path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8).contains("Include"))
    }

    @Test func whenTheAppAlreadyUsesTheSystemFilesThereIsNothingToDo() throws {
        let setup = try makeSetup(systemConfig: "Host a\n", systemKnownHosts: "a ssh-ed25519 AAAA1\n")
        let plan = setup.linker.plan(config: setup.home.appending(path: ".ssh/config"), knownHosts: setup.home.appending(path: ".ssh/known_hosts"))
        #expect(plan.isNoop)
    }

    @Test func aConfigThroughASymlinkedSshDirectoryIsReported() throws {
        let tmp = try TempDir()
        let home = tmp.url.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let real = try tmp.file("elsewhere/.keep", "")
        try FileManager.default.createSymbolicLink(at: home.appending(path: ".ssh"), withDestinationURL: real.deletingLastPathComponent())
        let cloud = try tmp.file("cloud/config", "Host a\n")
        let plan = SystemLinker(home: home, backups: nil).plan(config: cloud, knownHosts: tmp.url.appending(path: "none"))
        #expect(plan.notes.contains(.sshDirectoryIsSymlink(real.deletingLastPathComponent().path)))
    }

    @Test func aConflictingEditBetweenPlanAndApplyIsRefused() throws {
        let setup = try makeSetup(systemConfig: "Host a\n")
        let plan = setup.linker.plan(config: setup.cloudConfig, knownHosts: setup.cloudKnownHosts)
        try setup.tmp.file("home/.ssh/config", "Host changed elsewhere\n")
        #expect(throws: SafeFileWriterError.conflict) { try setup.linker.apply(plan) }
        #expect(try setup.tmp.read("home/.ssh/config") == "Host changed elsewhere\n")
    }
}
