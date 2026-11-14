import Foundation
import Testing
@testable import MacPocketCore

@Suite struct SystemDataArchiverTests {
    private func makeRoot() throws -> URL {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-arc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFolder(in root: URL, named name: String = "node_modules") throws -> URL {
        let folder = root.appending(path: "project/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "dep/bin"), withIntermediateDirectories: true)
        let text = String(repeating: "const value = require('module');\n", count: 60_000)   // compresses well
        try Data(text.utf8).write(to: folder.appending(path: "dep/index.js"))
        try Data("#!/bin/sh\necho ok\n".utf8).write(to: folder.appending(path: "dep/bin/run.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "dep/bin/run.sh").path)
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "dep/link").path, withDestinationPath: "bin/run.sh")
        return folder
    }

    private func archiver(_ root: URL, available: Int64? = 1_000_000_000_000, run: SystemDataArchiver.CommandRunner? = nil) -> SystemDataArchiver {
        SystemDataArchiver(manifest: root.appending(path: "archives.json"), run: run ?? SystemDataArchiver.liveRunner,
                           availableBytes: { _ in available })
    }

    @Test func archiveThenRestoreGivesBackTheSameFilesSymlinksAndPermissions() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeFolder(in: root)
        let original = try Data(contentsOf: folder.appending(path: "dep/index.js"))
        let service = archiver(root)

        let record = try await service.archive(folder: folder.path, title: "node_modules — project")
        #expect(!FileManager.default.fileExists(atPath: folder.path), "the folder is gone once the archive is verified")
        #expect(FileManager.default.fileExists(atPath: record.archivePath))
        #expect(record.archiveBytes < record.originalBytes, "text must compress")
        #expect(await service.records().map(\.id) == [record.id])

        try await service.restore(record)
        #expect(try Data(contentsOf: folder.appending(path: "dep/index.js")) == original)
        let mode = try FileManager.default.attributesOfItem(atPath: folder.appending(path: "dep/bin/run.sh").path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: folder.appending(path: "dep/link").path) == "bin/run.sh")
        #expect(!FileManager.default.fileExists(atPath: record.archivePath))
        #expect(await service.records().isEmpty)
    }

    @Test func aFailedPackingLeavesTheFolderAndNoPartialFile() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeFolder(in: root)
        let service = archiver(root, run: { _, _ in (1, "disk on fire") })
        await #expect(throws: SystemDataArchiveError.toolFailed("disk on fire")) { try await service.archive(folder: folder.path, title: "x") }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "dep/index.js").path))
        let archives = root.appending(path: "project/\(SystemDataArchiver.folderName)")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: archives.path)) ?? []).isEmpty)
    }

    @Test func anArchiveThatFailsVerificationNeverRemovesTheFolder() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeFolder(in: root)
        let service = archiver(root, run: { executable, arguments in
            executable.hasSuffix("unzip") ? (1, "bad CRC") : await SystemDataArchiver.liveRunner(executable, arguments)
        })
        await #expect(throws: SystemDataArchiveError.verificationFailed("bad CRC")) { try await service.archive(folder: folder.path, title: "x") }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "dep/index.js").path))
    }

    @Test func aFolderThatChangesWhileBeingPackedIsKept() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeFolder(in: root)
        let service = archiver(root, run: { executable, arguments in
            let result = await SystemDataArchiver.liveRunner(executable, arguments)
            if executable.hasSuffix("unzip") { try? Data("new".utf8).write(to: folder.appending(path: "dep/added.js")) }   // a build starts meanwhile
            return result
        })
        await #expect(throws: SystemDataArchiveError.changedWhileArchiving) { try await service.archive(folder: folder.path, title: "x") }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "dep/added.js").path))
    }

    @Test func hardLinkedFoldersAndTooLittleSpaceAreRefused() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeFolder(in: root)
        try FileManager.default.linkItem(at: folder.appending(path: "dep/index.js"), to: root.appending(path: "store-copy.js"))
        await #expect(throws: SystemDataArchiveError.sharedFiles) { try await archiver(root).archive(folder: folder.path, title: "x") }
        try FileManager.default.removeItem(at: root.appending(path: "store-copy.js"))
        await #expect(throws: SystemDataArchiveError.notEnoughSpace) { try await archiver(root, available: 1_000).archive(folder: folder.path, title: "x") }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "dep/index.js").path))
    }

    @Test func notAFolderOrASymlinkIsRefused() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeFolder(in: root)
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        await #expect(throws: SystemDataArchiveError.notAFolder) { try await archiver(root).archive(folder: link.path, title: "x") }
        await #expect(throws: SystemDataArchiveError.notAFolder) { try await archiver(root).archive(folder: folder.appending(path: "dep/index.js").path, title: "x") }
    }

    @Test func restoreRefusesToOverwriteAndDeleteGivesTheSpaceUp() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeFolder(in: root)
        let service = archiver(root)
        let record = try await service.archive(folder: folder.path, title: "x")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await #expect(throws: SystemDataArchiveError.targetExists) { try await service.restore(record) }
        try await service.deleteArchive(record)
        #expect(!FileManager.default.fileExists(atPath: record.archivePath))
        #expect(await service.records().isEmpty)
    }
}
