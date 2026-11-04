import XCTest
import Darwin
@testable import MacPocketCore

final class USBEjectTests: XCTestCase {
    private actor EjectCalls {
        var ids: [String] = []
        func add(_ id: String) { ids.append(id) }
    }
    private struct Fixture: Sendable {
        let external: String
        let all: String
        let root: String
        let info: String
        var execute: USBEject.Execute { { _, arguments, _ in
            let text: String
            switch arguments {
            case ["list", "-plist", "external", "physical"]: text = external
            case ["list", "-plist"]: text = all
            case ["info", "-plist", "/"]: text = root
            case ["info", "-plist", "disk4"]: text = info
            default: throw USBEjectError.invalidResponse
            }
            return .init(status: 0, output: text, errorOutput: "")
        } }
    }

    private func plist(_ object: [String: Any]) throws -> String {
        String(decoding: try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0), as: UTF8.self)
    }

    private func fixture(internalDisk: Bool = false, bootStore: String = "disk0s2", bootWhole: String = "disk3", uuid: String = "original", mediaID: String = "first-attachment", multiStore: Bool = false) throws -> Fixture {
        let physical: [String: Any] = ["DeviceIdentifier": "disk4", "Size": 1_000_000_000, "Partitions": [
            ["DeviceIdentifier": "disk4s1", "VolumeName": "Shared", "DiskUUID": uuid, "MountPoint": "/Volumes/Shared"],
            ["DeviceIdentifier": "disk4s2", "DiskUUID": "apfs-partition"],
        ]]
        let stores = multiStore ? [["DeviceIdentifier": "disk4s2"], ["DeviceIdentifier": "disk8s2"]] : [["DeviceIdentifier": "disk4s2"]]
        let apfs: [String: Any] = ["DeviceIdentifier": "disk9", "APFSPhysicalStores": stores, "APFSVolumes": [
            ["DeviceIdentifier": "disk9s1", "VolumeName": "Work Drive", "VolumeUUID": "work", "MountPoint": "/Volumes/Work Drive"],
            ["DeviceIdentifier": "disk9s2", "VolumeName": "Locked Backup", "VolumeUUID": "backup"],
        ]]
        return try Fixture(external: plist(["AllDisksAndPartitions": [physical]]),
                           all: plist(["AllDisksAndPartitions": [physical, apfs]]),
                           root: plist(["DeviceIdentifier": bootWhole + "s1s1", "ParentWholeDisk": bootWhole, "APFSPhysicalStores": [["APFSPhysicalStore": bootStore]]]),
                           info: plist(["DeviceIdentifier": "disk4", "Internal": internalDisk, "WholeDisk": true,
                                        "VirtualOrPhysical": "Physical", "MediaName": "External SSD", "BusProtocol": "USB", "TotalSize": 1_000_000_000,
                                        "MacPocketMediaIdentity": mediaID]))
    }

    func testEmptyExternalListSkipsUnneededTopologyQueries() async throws {
        actor Commands {
            var arguments: [[String]] = []
            func record(_ value: [String]) { arguments.append(value) }
        }
        let commands = Commands()
        let empty = try plist(["AllDisksAndPartitions": []])
        let root = try plist(["DeviceIdentifier": "disk0s1"])
        let drives = try await USBEject.load { _, arguments, _ in
            await commands.record(arguments)
            return .init(status: 0, output: arguments.first == "info" ? root : empty, errorOutput: "")
        }
        XCTAssertTrue(drives.isEmpty)
        let arguments = await commands.arguments
        print("EMPTY_USB_DISKUTIL_COMMANDS: \(arguments.count)")
        XCTAssertEqual(arguments, [["list", "-plist", "external", "physical"]])
    }

    func testPhysicalDriveGroupsPartitionsAndAPFSVolumesWithoutDoubleCounting() async throws {
        let disks = try await USBEject.load(execute: fixture().execute)
        let disk = try XCTUnwrap(disks.first)
        XCTAssertEqual(disks.count, 1)
        XCTAssertEqual(disk.id, "disk4")
        XCTAssertEqual(disk.capacity, 1_000_000_000)
        XCTAssertEqual(disk.volumes.map(\.name), ["Shared", "Work Drive", "Locked Backup"])
        XCTAssertEqual(disk.mountPaths, ["/Volumes/Shared", "/Volumes/Work Drive"])
    }

    func testWholeDiskFileSystemIsIncludedInUsagePaths() throws {
        let volume: [String: Any] = ["DeviceIdentifier": "disk4", "VolumeName": "USB Stick", "MountPoint": "/Volumes/USB Stick"]
        let parsed = try USBEject.parse(external: ["AllDisksAndPartitions": [volume]], all: ["AllDisksAndPartitions": [volume]],
                                        root: ["DeviceIdentifier": "disk0s1", "ParentWholeDisk": "disk0"],
                                        info: ["disk4": ["DeviceIdentifier": "disk4", "Internal": false, "WholeDisk": true]])
        XCTAssertEqual(parsed.first?.mountPaths, ["/Volumes/USB Stick"], "Unpartitioned USB drives still need open-file inspection")
    }

    func testInternalStartupAndMultiStoreDisksAreNeverOfferedForEjection() async throws {
        for fixture in [try fixture(internalDisk: true), try fixture(bootStore: "disk4s2"),
                        try fixture(bootStore: "", bootWhole: "disk9"), try fixture(multiStore: true)] {
            let disks = try await USBEject.load(execute: fixture.execute)
            XCTAssertTrue(disks.isEmpty)
        }
        XCTAssertFalse(USBEject.isWholeDisk("disk4s1"))
        XCTAssertFalse(USBEject.isWholeDisk("disk4; id"))
    }

    func testRepluggingADifferentDriveCannotEjectTheReusedBSDIdentifier() async throws {
        let original = try await USBEject.load(execute: fixture().execute)
        for replacement in [try fixture(uuid: "replacement"), try fixture(mediaID: "new-attachment-same-UUID")] {
            do {
                try await USBEject.eject(try XCTUnwrap(original.first), execute: replacement.execute, eject: { _ in XCTFail("Must not eject a replacement drive") })
                XCTFail("Expected stale identity to be rejected")
            } catch { XCTAssertEqual(error as? USBEjectError, .changed) }
        }
    }

    func testEjectRevalidatesTheDriveBeforeCallingTheNativeOperation() async throws {
        let fixture = try fixture()
        let loaded = try await USBEject.load(execute: fixture.execute)
        let disk = try XCTUnwrap(loaded.first)
        let calls = EjectCalls()
        try await USBEject.eject(disk, execute: fixture.execute, eject: { id in await calls.add(id) })
        let ids = await calls.ids
        XCTAssertEqual(ids, ["disk4"])
        do {
            try await USBEject.eject(disk, execute: self.fixture(internalDisk: true).execute, eject: { _ in XCTFail("Internal disks must be rejected") })
            XCTFail("Expected rejection")
        } catch { XCTAssertEqual(error as? USBEjectError, .unavailable) }
    }

    func testNullDelimitedFileNamesPIDGroupingAndVolumeBoundaries() {
        let output = "p42\0cMy App\0\nf1\0n/Volumes/Work Drive/file with spaces\0\nf2\0n/Volumes/Work Drive/line\nbreak\0\nf3\0n/Volumes/Work Drive/file with spaces\0\n"
            + "p50\0cOther\0\nf1\0n/Volumes/Work Drive Extra/unrelated\0\np51\0cTerminal\0\nfcwd\0n/Volumes/Work Drive\0\n"
        let users = USBEject.parseUsers(output, mountPaths: ["/Volumes/Work Drive"])
        XCTAssertEqual(users.map(\.pid), [42, 51])
        XCTAssertEqual(users.first?.command, "My App")
        XCTAssertEqual(users.first?.files.count, 2)
        XCTAssertTrue(users.first?.files.contains("/Volumes/Work Drive/line\nbreak") == true)
    }

    func testEscapedTurkishVolumeNamesAndLiteralBackslashes() {
        let output = "p42\0cMy\\x20App\0\nf1\0n/Volumes/Ar\\xc5\\x9fiv/file.txt\0\n"
        let users = USBEject.parseUsers(output, mountPaths: ["/Volumes/Arşiv"])
        XCTAssertEqual(users.first?.command, "My App")
        XCTAssertEqual(users.first?.files, ["/Volumes/Arşiv/file.txt"])
        let literal = USBEject.parseUsers("p42\0cApp\0\nf1\0n/Volumes/literal\\n/file.txt\0\n", mountPaths: ["/Volumes/literal\\n"])
        XCTAssertEqual(literal.first?.files, ["/Volumes/literal\\n/file.txt"])
    }

    func testUsageDoesNotTreatPermissionFailureAsAnIdleDrive() async throws {
        let loaded = try await USBEject.load(execute: fixture().execute)
        let disk = try XCTUnwrap(loaded.first)
        do {
            _ = try await USBEject.usage(of: disk) { _, _, _ in .init(status: 1, output: "", errorOutput: "permission denied") }
            XCTFail("Permission failure must remain visible")
        } catch { XCTAssertNotNil(error as? USBEjectError) }
        let report = try await USBEject.usage(of: disk) { path, args, _ in
            XCTAssertEqual(path, "/usr/sbin/lsof")
            XCTAssertEqual(Array(args.suffix(2)), ["/Volumes/Shared", "/Volumes/Work Drive"])
            return .init(status: 1, output: "", errorOutput: "")
        }
        XCTAssertTrue(report.users.isEmpty)
    }

    func testInvalidDiscoveryResponseIsNotAnEmptySuccessfulList() async throws {
        let responses = ["not a plist", try plist([:]), try plist(["AllDisksAndPartitions": "unreadable"])]
        for response in responses {
            do {
                _ = try await USBEject.load { _, _, _ in .init(status: 0, output: response, errorOutput: "") }
                XCTFail("Expected discovery failure")
            } catch { XCTAssertEqual(error as? USBEjectError, .invalidResponse) }
        }
    }

    func testNativeEjectionOfOwnedDiskImageWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MACPOCKET_USB_EJECT_IMAGE_TESTS"] == "1" else {
            throw XCTSkip("Set MACPOCKET_USB_EJECT_IMAGE_TESTS=1 for an isolated disk-image integration test")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocketEject-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("fixture.sparseimage")
        let mount = directory.appendingPathComponent("Bağlı Disk")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let created = try await BoundedProcess.run("/usr/bin/hdiutil", ["create", "-size", "16m", "-fs", "HFS+", "-type", "SPARSE", "-volname", "MacPocket Eject Fixture", image.path], timeout: 30)
        XCTAssertEqual(created.status, 0, created.errorOutput)
        let attached = try await BoundedProcess.run("/usr/bin/hdiutil", ["attach", "-plist", "-nobrowse", "-mountpoint", mount.path, image.path], timeout: 30)
        XCTAssertEqual(attached.status, 0, attached.errorOutput)
        let result = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(attached.output.utf8), format: nil) as? [String: Any])
        let entities = try XCTUnwrap(result["system-entities"] as? [[String: Any]])
        let device = try XCTUnwrap(entities.compactMap { $0["dev-entry"] as? String }.first { USBEject.isWholeDisk(String($0.dropFirst(5))) })
        defer {
            if FileManager.default.fileExists(atPath: device) {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                process.arguments = ["eject", device]; try? process.run(); process.waitUntilExit()
            }
        }
        let disks = try await USBEject.load()
        XCTAssertFalse(disks.contains { "/dev/" + $0.id == device }, "Disk images must not appear as physical USB drives")
        let file = mount.appendingPathComponent("busy file.txt")
        try Data("test".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        let owners = try await BoundedProcess.run("/usr/sbin/lsof", ["-nP", "-F0pcfn", "+f", "--", mount.path], timeout: 15)
        XCTAssertTrue(USBEject.parseUsers(owners.output, mountPaths: [mount.path]).contains { $0.pid == getpid() },
                      "pid=\(getpid()), mount=\(mount.path), status=\(owners.status), stdout=\(owners.output.debugDescription), stderr=\(owners.errorOutput)")
        do {
            try await USBEject.nativeEject(String(device.dropFirst(5)))
            XCTFail("An open file should prevent normal unmount")
        } catch { XCTAssertNotNil(error as? USBEjectError) }
        try handle.close()
        try await USBEject.nativeEject(String(device.dropFirst(5)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
