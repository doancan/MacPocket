import Darwin
import Foundation
import Testing
@testable import MacPocketCore

@Suite(.serialized) struct SystemDataShrinkerTests {
    private func makeRoot() throws -> URL {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-shrink-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func text(_ megabytes: Double, _ seed: String = "func shrink() { return compress(value) }\n") -> Data {
        Data(String(repeating: seed, count: Int(megabytes * 1_000_000) / seed.utf8.count).utf8)
    }

    private func isCompressed(_ path: String) -> Bool { var info = stat(); return lstat(path, &info) == 0 && info.st_flags & UInt32(UF_COMPRESSED) != 0 }
    private func inode(_ path: String) -> UInt64 { var info = stat(); return lstat(path, &info) == 0 ? UInt64(info.st_ino) : 0 }
    private func blocks(_ path: String) -> Int64 { var info = stat(); return lstat(path, &info) == 0 ? Int64(info.st_blocks) * 512 : -1 }

    /// A shrinker whose clock is two hours ahead, so freshly written fixture files count as old (the real quiet period is ten minutes).
    private func shrinker(available: Int64? = 1_000_000_000_000, busy: [String] = [], concurrency: Int = 3,
                          run: SystemDataShrinker.CommandRunner? = nil) -> SystemDataShrinker {
        SystemDataShrinker(run: run ?? SystemDataShrinker.liveRunner, availableBytes: { _ in available }, busyTools: { _ in busy },
                           now: { Date().addingTimeInterval(7_200) }, concurrency: concurrency)
    }

    private func leftovers(_ root: URL) -> [String] {
        var found: [String] = []
        let walker = FileManager.default.enumerator(atPath: root.path)
        while let path = walker?.nextObject() as? String { if path.contains(SystemDataShrinker.temporaryMarker) { found.append(path) } }
        return found
    }

    @Test func compressesInPlaceAndKeepsContentPermissionsLinksAndDates() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "deps/inner"), withIntermediateDirectories: true)
        let big = text(8), mid = text(2, "mid file with repeated source text\n")
        try big.write(to: folder.appending(path: "deps/big.rlib"))
        try mid.write(to: folder.appending(path: "deps/inner/mid.rmeta"))
        try text(3).write(to: folder.appending(path: "deps/pair-a.o"))
        try FileManager.default.linkItem(at: folder.appending(path: "deps/pair-a.o"), to: folder.appending(path: "deps/inner/pair-b.o"))
        try Data("#!/bin/sh\necho ok\n".utf8).write(to: folder.appending(path: "run.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "run.sh").path)
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "link").path, withDestinationPath: "run.sh")
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.appending(path: "deps/big.rlib").path)
        let canonical = try #require(existingCanonicalPath(folder))
        let before = blocks(folder.appending(path: "deps/big.rlib").path)

        let result = try await shrinker().shrink(folder: canonical)

        #expect(result.filesCompressed == 3, "big, mid and the hard-linked pair (one inode)")
        #expect(result.savedBytes > 8_000_000, "text compresses by far more than that")
        #expect(isCompressed(folder.appending(path: "deps/big.rlib").path))
        #expect(blocks(folder.appending(path: "deps/big.rlib").path) < before / 3)
        #expect(try Data(contentsOf: folder.appending(path: "deps/big.rlib")) == big)
        #expect(try Data(contentsOf: folder.appending(path: "deps/inner/mid.rmeta")) == mid)
        let a = folder.appending(path: "deps/pair-a.o").path, b = folder.appending(path: "deps/inner/pair-b.o").path
        #expect(inode(a) == inode(b), "the hard link inside the folder survives, now pointing at the one compressed copy")
        #expect(isCompressed(a) && isCompressed(b))
        var info = stat(); lstat(a, &info); #expect(info.st_nlink == 2)
        #expect(try FileManager.default.attributesOfItem(atPath: folder.appending(path: "run.sh").path)[.posixPermissions] as? Int == 0o755)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: folder.appending(path: "link").path) == "run.sh")
        let modified = try #require(try FileManager.default.attributesOfItem(atPath: folder.appending(path: "deps/big.rlib").path)[.modificationDate] as? Date)
        #expect(Int(modified.timeIntervalSince1970) == 1_700_000_000, "dates survive")
        #expect(leftovers(root).isEmpty)
    }

    @Test func filesSharedWithTheOutsideClonesSmallFreshAndAlreadyCompressedAreLeftAlone() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(4).write(to: folder.appending(path: "ok.bin"))
        try text(4).write(to: folder.appending(path: "external.bin"))
        try FileManager.default.linkItem(at: folder.appending(path: "external.bin"), to: root.appending(path: "outside-link.bin"))
        try text(4).write(to: root.appending(path: "clone-source.bin"))
        try FileManager.default.copyItem(at: root.appending(path: "clone-source.bin"), to: folder.appending(path: "clone.bin"))   // APFS clone
        try Data(count: 1_000).write(to: folder.appending(path: "tiny.bin"))
        try text(4).write(to: folder.appending(path: "fresh.bin"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(7_300)], ofItemAtPath: folder.appending(path: "fresh.bin").path)
        try text(4).write(to: folder.appending(path: "already.bin"))
        _ = try await shrinker().shrink(folder: try #require(existingCanonicalPath(folder)))
        let already = blocks(folder.appending(path: "already.bin").path)
        let inodes = ["external.bin", "clone.bin", "tiny.bin", "fresh.bin"].map { inode(folder.appending(path: $0).path) }

        #expect(["external.bin", "clone.bin", "tiny.bin", "fresh.bin"].map { inode(folder.appending(path: $0).path) } == inodes)
        for name in ["external.bin", "clone.bin", "tiny.bin", "fresh.bin"] { #expect(!isCompressed(folder.appending(path: name).path), "\(name)") }
        #expect(isCompressed(folder.appending(path: "ok.bin").path))
        #expect(blocks(folder.appending(path: "already.bin").path) == already)
        #expect(try Data(contentsOf: root.appending(path: "outside-link.bin")) == text(4), "the outside link still reads fine")
    }

    @Test func aSecondRunHasNothingLeftToDo() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(4).write(to: folder.appending(path: "a.bin"))
        let canonical = try #require(existingCanonicalPath(folder))
        _ = try await shrinker().shrink(folder: canonical)
        await #expect(throws: SystemDataShrinkError.nothingToShrink) { try await shrinker().shrink(folder: canonical) }
    }

    @Test func incompressibleDataIsLeftExactlyAsItWas() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: 3_000_000)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        try Data(bytes).write(to: folder.appending(path: "random.bin"))
        let before = inode(folder.appending(path: "random.bin").path)
        let result = try await shrinker().shrink(folder: try #require(existingCanonicalPath(folder)))
        #expect(result.filesCompressed == 0 && result.savedBytes == 0)
        #expect(inode(folder.appending(path: "random.bin").path) == before)
        #expect(leftovers(root).isEmpty)
    }

    @Test func aRunningBuildToolBlocksEverythingBeforeAnyFileIsTouched() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(4).write(to: folder.appending(path: "a.bin"))
        await #expect(throws: SystemDataShrinkError.busy(["cargo"])) { try await shrinker(busy: ["cargo"]).shrink(folder: try #require(existingCanonicalPath(folder))) }
        #expect(!isCompressed(folder.appending(path: "a.bin").path))
    }

    @Test func tooLittleSpaceForEvenOneCopyIsRefused() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(4).write(to: folder.appending(path: "a.bin"))
        await #expect(throws: SystemDataShrinkError.notEnoughSpace) { try await shrinker(available: 1_000).shrink(folder: try #require(existingCanonicalPath(folder))) }
    }

    @Test func aCorruptCopyStopsTheRunAndLeavesTheOriginalUntouched() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let content = text(4)
        try content.write(to: folder.appending(path: "a.bin"))
        let original = inode(folder.appending(path: "a.bin").path)
        let source = folder.appending(path: "a.bin")
        let service = shrinker(concurrency: 1, run: { executable, arguments in
            let result = await SystemDataShrinker.liveRunner(executable, arguments)
            // A failing disk: the copy no longer matches the original, same size and dates.
            let mtime = (try? FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate]) as? Date
            if let handle = try? FileHandle(forWritingTo: source) {
                try? handle.seek(toOffset: 2_000_000); try? handle.write(contentsOf: Data([0x00])); try? handle.close()
            }
            if let mtime { try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: source.path) }
            return result
        })
        await #expect { try await service.shrink(folder: try #require(existingCanonicalPath(folder))) } throws: { error in
            if case SystemDataShrinkError.verificationFailed = error { return true }; return false
        }
        #expect(inode(folder.appending(path: "a.bin").path) == original)
        #expect(!isCompressed(source.path), "the original stays, uncompressed")
        #expect(leftovers(root).isEmpty)
        _ = content
    }

    @Test func aFileThatChangesWhileItIsBeingCompressedIsKept() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(4).write(to: folder.appending(path: "a.bin"))
        let source = folder.appending(path: "a.bin")
        let service = shrinker(concurrency: 1, run: { executable, arguments in
            let result = await SystemDataShrinker.liveRunner(executable, arguments)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: source.path)   // a build touches it
            return result
        })
        let result = try await service.shrink(folder: try #require(existingCanonicalPath(folder)))
        #expect(result.filesCompressed == 0)
        #expect(!isCompressed(source.path))
        #expect(leftovers(root).isEmpty)
    }

    @Test func estimateTellsTheSavingFromARealSampleWithoutChangingAnything() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<12 { try text(2, "line \(index) of repetitive compile output\n").write(to: folder.appending(path: "f\(index).rlib")) }
        let canonical = try #require(existingCanonicalPath(folder))
        let inodes = (0..<12).map { inode(folder.appending(path: "f\($0).rlib").path) }
        let estimate = try await shrinker().estimate(folder: canonical)
        #expect(estimate.candidateFiles == 12)
        #expect(estimate.sampleRatio > 0.5)
        #expect(estimate.estimatedSavedBytes > estimate.candidateBytes / 2)
        #expect(estimate.estimatedSeconds >= 0)
        #expect((0..<12).map { inode(folder.appending(path: "f\($0).rlib").path) } == inodes)
        #expect((0..<12).allSatisfy { !isCompressed(folder.appending(path: "f\($0).rlib").path) }, "estimating compresses nothing in the folder")
        let actual = try await shrinker().shrink(folder: canonical)
        let ratio = Double(estimate.estimatedSavedBytes) / Double(max(1, actual.savedBytes))
        #expect(ratio > 0.8 && ratio < 1.25, "the estimate (\(estimate.estimatedSavedBytes)) is close to what happened (\(actual.savedBytes))")
    }

    @Test func progressNeverGoesBackwardsAndEndsComplete() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<9 { try text(1, "progress \(index)\n").write(to: folder.appending(path: "f\(index).bin")) }
        let seen = Locked<[SystemDataShrinkProgress]>([])
        _ = try await shrinker().shrink(folder: try #require(existingCanonicalPath(folder)), progress: { reading in seen.mutate { $0.append(reading) } })
        let readings = seen.value
        #expect(readings.count == 9)
        #expect(readings.map(\.filesDone) == Array(1...9))
        #expect(readings.map(\.savedBytes) == readings.map(\.savedBytes).sorted())
        #expect(readings.last?.fraction == 1)
    }

    @Test func cancellingMidwayLeavesEveryFileEitherWholeOrCompressedAndNoTemporaries() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var contents: [String: Data] = [:]
        for index in 0..<40 { let data = text(1, "cancel \(index)\n"); contents["f\(index).bin"] = data; try data.write(to: folder.appending(path: "f\(index).bin")) }
        let canonical = try #require(existingCanonicalPath(folder))
        let task = Task { try await shrinker(concurrency: 2).shrink(folder: canonical) }
        try await Task.sleep(for: .milliseconds(120))
        task.cancel()
        _ = try? await task.value
        for (name, data) in contents { #expect(try Data(contentsOf: folder.appending(path: name)) == data, "\(name)") }
        #expect(leftovers(root).isEmpty)
    }

    @Test func staleTemporaryFilesFromACrashedRunAreCleanedUp() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(4).write(to: folder.appending(path: "a.bin"))
        let stale = folder.appending(path: ".a.bin\(SystemDataShrinker.temporaryMarker)deadbeef")
        try Data(count: 5_000).write(to: stale)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400)], ofItemAtPath: stale.path)
        _ = try await shrinker().shrink(folder: try #require(existingCanonicalPath(folder)))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func turkishAndEmojiNamesAreHandled() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Proje Çalışması 📦", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "ığüşöç İĞÜŞÖÇ"), withIntermediateDirectories: true)
        let data = text(3, "çok tekrarlı içerik ığüşöç 📦\n")
        try data.write(to: folder.appending(path: "ığüşöç İĞÜŞÖÇ/büyük dosya 'tırnaklı'.txt"))
        let result = try await shrinker().shrink(folder: try #require(existingCanonicalPath(folder)))
        #expect(result.filesCompressed == 1)
        #expect(try Data(contentsOf: folder.appending(path: "ığüşöç İĞÜŞÖÇ/büyük dosya 'tırnaklı'.txt")) == data)
    }

    @Test func nonFoldersAndSymlinksAreRefused() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(1).write(to: folder.appending(path: "a.bin"))
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        await #expect(throws: SystemDataShrinkError.notAFolder) { try await shrinker().shrink(folder: link.path) }
        await #expect(throws: SystemDataShrinkError.notAFolder) { try await shrinker().shrink(folder: folder.appending(path: "a.bin").path) }
    }

    @Test func aFailingToolIsReportedAndLeavesNothingBehind() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text(4).write(to: folder.appending(path: "a.bin"))
        await #expect(throws: SystemDataShrinkError.toolFailed("boom")) { try await shrinker(run: { _, _ in (1, "boom") }).shrink(folder: try #require(existingCanonicalPath(folder))) }
        #expect(leftovers(root).isEmpty)
    }

    @Test func largeFilesAreComparedByWindowsAcrossTheirWholeLength() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let size = 150_000_000   // above the full-compare limit
        var bytes = Data(count: size)
        for index in stride(from: 0, to: size, by: 4_096) { bytes[index] = UInt8(truncatingIfNeeded: index / 4_096) }
        let a = root.appending(path: "a"), b = root.appending(path: "b"), c = root.appending(path: "c")
        try bytes.write(to: a); try bytes.write(to: b)
        var damaged = bytes; damaged[size - 10] ^= 0xFF
        try damaged.write(to: c)
        #expect(SystemDataShrinker.contentsMatch(a.path, b.path, size: Int64(size)))
        #expect(!SystemDataShrinker.contentsMatch(a.path, c.path, size: Int64(size)), "tail damage is caught")
    }
}

@Suite struct BuildActivityTests {
    @Test func aBuildToolRunningInsideAFolderIsFoundAndOneElsewhereIsNot() throws {
        let base = try #require(existingCanonicalPath(FileManager.default.temporaryDirectory))
        let root = URL(fileURLWithPath: base).appending(path: "sysdata-busy-\(UUID().uuidString)", directoryHint: .isDirectory)
        let project = root.appending(path: "project/target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A copy of sleep that calls itself "cargo", started inside the project, stands in for a running build.
        let fake = root.appending(path: "cargo")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: fake)
        let signer = Process()   // a copied system binary only runs once it is signed again
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); signer.arguments = ["--force", "-s", "-", fake.path]
        signer.standardError = FileHandle.nullDevice
        try signer.run(); signer.waitUntilExit()
        let process = Process()
        process.executableURL = fake; process.arguments = ["30"]; process.currentDirectoryURL = project.deletingLastPathComponent()
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        usleep(300_000)
        #expect(BuildActivity.runningTools(under: project.deletingLastPathComponent().path) == ["cargo"])
        #expect(BuildActivity.runningTools(under: project.path).isEmpty, "its working directory is the project, not the target below it")
        #expect(BuildActivity.runningTools(under: root.appending(path: "somewhere-else").path).isEmpty)
        #expect(BuildActivity.runningTools(under: root.path) == ["cargo"], "a parent folder covers it")
    }
}
