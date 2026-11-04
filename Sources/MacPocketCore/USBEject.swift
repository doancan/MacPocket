import Foundation
import DiskArbitration
import Darwin
import IOKit

public struct EjectVolume: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let mountPath: String?
}

public struct EjectDrive: Identifiable, Equatable, Sendable {
    public let id: String
    public let identity: String
    public let name: String
    public let connection: String
    public let capacity: UInt64
    public let volumes: [EjectVolume]
    public var mountPaths: [String] { Array(Set(volumes.compactMap(\.mountPath))).sorted() }
}

public struct DiskUser: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let files: [String]
    public var id: Int32 { pid }
}

public struct DiskUsageReport: Sendable {
    public let users: [DiskUser]
    public let limited: Bool
}

public enum USBEjectError: Error, LocalizedError, Equatable {
    case invalidResponse, unavailable, changed, refused(String)
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: String(localized: "Harici disk bilgileri okunamadı. Yeniden dene.")
        case .unavailable: String(localized: "Disk artık bağlı değil veya güvenli çıkarma için uygun değil.")
        case .changed: String(localized: "Bağlı disk değişti. Listeyi yenileyip diski yeniden seç.")
        case .refused(let reason): String(localized: "Disk çıkarılamadı: \(reason)")
        }
    }
}

public enum USBEject {
    public typealias Execute = @Sendable (String, [String], TimeInterval) async throws -> BoundedProcess.Result
    public typealias Eject = @Sendable (String) async throws -> Void
    public static let execute: Execute = { try await BoundedProcess.run($0, $1, timeout: $2) }

    public static func load(execute: Execute? = nil) async throws -> [EjectDrive] {
        let reader = execute ?? Self.execute
        let externalList = try dictionary(await plist(["list", "-plist", "external", "physical"], execute: reader))
        guard let candidates = externalList["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw USBEjectError.invalidResponse
        }
        // The usual empty state needs no APFS topology or startup-volume query.
        guard !candidates.isEmpty else { return [] }
        async let all = plist(["list", "-plist"], execute: reader)
        async let root = plist(["info", "-plist", "/"], execute: reader)
        var info: [String: [String: Any]] = [:]
        for node in candidates {
            guard let id = node["DeviceIdentifier"] as? String, isWholeDisk(id) else { continue }
            var details = try dictionary(await plist(["info", "-plist", id], execute: reader))
            if execute == nil { details["MacPocketMediaIdentity"] = registryIdentity(id) }
            info[id] = details
        }
        let (allData, rootData) = try await (all, root)
        return try parse(external: externalList, all: dictionary(allData), root: dictionary(rootData), info: info)
    }

    private static func plist(_ arguments: [String], execute: Execute) async throws -> Data {
        let result = try await execute("/usr/sbin/diskutil", arguments, 15)
        guard result.status == 0 else { throw USBEjectError.invalidResponse }
        return Data(result.output.utf8)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw USBEjectError.invalidResponse
        }
        return value
    }

    static func isWholeDisk(_ id: String) -> Bool { id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil }
    private static func belongs(_ id: String, to disk: String) -> Bool { id == disk || id.hasPrefix(disk + "s") }

    private static func registryIdentity(_ id: String) -> String? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/" + id) else { return nil }
        let media = DADiskCopyIOMedia(disk)
        guard media != 0 else { return nil }
        defer { IOObjectRelease(media) }
        var entry: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(media, &entry) == KERN_SUCCESS else { return nil }
        return String(entry)
    }

    /// APFS synthesized volumes belong to their physical stores, rather than becoming separate eject buttons.
    static func parse(external: [String: Any], all: [String: Any], root: [String: Any], info: [String: [String: Any]]) throws -> [EjectDrive] {
        guard let candidates = external["AllDisksAndPartitions"] as? [[String: Any]],
              let nodes = all["AllDisksAndPartitions"] as? [[String: Any]], root["DeviceIdentifier"] is String else {
            throw USBEjectError.invalidResponse
        }
        let bootWhole = root["ParentWholeDisk"] as? String ?? root["DeviceIdentifier"] as? String ?? ""
        let bootStores = (root["APFSPhysicalStores"] as? [[String: Any]] ?? []).compactMap { $0["APFSPhysicalStore"] as? String }
            + nodes.filter { $0["DeviceIdentifier"] as? String == bootWhole }.flatMap {
                ($0["APFSPhysicalStores"] as? [[String: Any]] ?? []).compactMap { $0["DeviceIdentifier"] as? String }
            }
        return candidates.compactMap { candidate in
            guard let id = candidate["DeviceIdentifier"] as? String, isWholeDisk(id),
                  let details = info[id], details["DeviceIdentifier"] as? String == id,
                  details["Internal"] as? Bool == false, details["WholeDisk"] as? Bool == true,
                  details["VirtualOrPhysical"] as? String != "Virtual",
                  !belongs(bootWhole, to: id), !bootStores.contains(where: { belongs($0, to: id) }) else { return nil }
            var related = [candidate]
            for node in nodes {
                let stores = (node["APFSPhysicalStores"] as? [[String: Any]] ?? []).compactMap { $0["DeviceIdentifier"] as? String }
                if stores.contains(where: { belongs($0, to: id) }) {
                    // A multi-store container cannot be safely treated as an independently removable drive.
                    guard stores.count == 1 else { return nil }
                    related.append(node)
                }
            }
            let descendants = related.flatMap(flatten)
            let paths = descendants.compactMap { $0["MountPoint"] as? String ?? $0["SnapshotMountPoint"] as? String }
            guard !paths.contains(where: { $0 == "/" || $0.hasPrefix("/System/Volumes/") }) else { return nil }
            var seen = Set<String>()
            let volumes = descendants.compactMap { node -> EjectVolume? in
                guard let volumeID = node["DeviceIdentifier"] as? String,
                      let name = node["VolumeName"] as? String, seen.insert(volumeID).inserted else { return nil }
                return EjectVolume(id: volumeID, name: name, mountPath: node["MountPoint"] as? String)
            }
            let identities = descendants.compactMap { $0["VolumeUUID"] as? String ?? $0["DiskUUID"] as? String }.sorted()
            let name = details["MediaName"] as? String ?? volumes.first?.name ?? id
            let capacity = (details["TotalSize"] as? NSNumber)?.uint64Value ?? (candidate["Size"] as? NSNumber)?.uint64Value ?? 0
            let identity = ([id, name, String(capacity), details["DeviceTreePath"] as? String ?? "",
                             details["MacPocketMediaIdentity"] as? String ?? ""] + identities).joined(separator: "|")
            return EjectDrive(id: id, identity: identity, name: name, connection: details["BusProtocol"] as? String ?? "USB",
                              capacity: capacity, volumes: volumes)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func flatten(_ node: [String: Any]) -> [[String: Any]] {
        [node] + ["Partitions", "APFSVolumes", "MountedSnapshots"].flatMap { key in
            (node[key] as? [[String: Any]] ?? []).flatMap(flatten)
        }
    }

    public static func usage(of drive: EjectDrive, execute: Execute = execute) async throws -> DiskUsageReport {
        guard !drive.mountPaths.isEmpty else { return DiskUsageReport(users: [], limited: false) }
        let result = try await execute("/usr/sbin/lsof", ["-nP", "+c", "0", "-F0pcfn", "+f", "--"] + drive.mountPaths, 15)
        let users = parseUsers(result.output, mountPaths: drive.mountPaths)
        guard result.status == 0 || (result.status == 1 && result.output.isEmpty && result.errorOutput.isEmpty) || !users.isEmpty else {
            throw USBEjectError.refused(String(localized: "Diski kullanan süreçler okunamadı. Yeniden dene."))
        }
        return DiskUsageReport(users: users, limited: !result.errorOutput.isEmpty)
    }

    static func parseUsers(_ output: String, mountPaths: [String]) -> [DiskUser] {
        // lsof resolves paths such as /var -> /private/var even when diskutil reports the original spelling.
        let roots = Set(mountPaths.flatMap { path -> [String] in
            // NSURL can shorten /private/var back to /var; realpath matches the kernel names lsof emits.
            guard let resolved = realpath(path, nil) else { return [path] }
            defer { free(resolved) }
            return [path, String(cString: resolved)]
        })
        var pid: Int32?, command = ""
        var owners: [Int32: (String, Set<String>)] = [:]
        for raw in output.split(separator: "\0") {
            let field = raw.drop(while: { $0 == "\n" || $0 == "\r" })
            guard let tag = field.first else { continue }
            let value = String(field.dropFirst())
            switch tag {
            case "p": pid = Int32(value); command = ""
            case "c": command = unescapeLsof(value)
            case "n":
                let path = roots.contains(where: { value == $0 || value.hasPrefix($0 + "/") }) ? value : unescapeLsof(value)
                guard let pid, roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
                var owner = owners[pid] ?? (command, [])
                owner.1.insert(path)
                owners[pid] = owner
            default: break
            }
        }
        return owners.map { DiskUser(pid: $0.key, command: $0.value.0, files: $0.value.1.sorted()) }.sorted { $0.pid < $1.pid }
    }

    /// In a non-UTF-8 launch environment lsof escapes each non-ASCII byte, including Turkish volume names.
    private static func unescapeLsof(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var decoded: [UInt8] = [], index = 0
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: byte - 48
            case 65...70: byte - 55
            case 97...102: byte - 87
            default: nil
            }
        }
        while index < bytes.count {
            if bytes[index] == 92, index + 1 < bytes.count {
                if bytes[index + 1] == 120, index + 3 < bytes.count,
                   let high = hex(bytes[index + 2]), let low = hex(bytes[index + 3]) {
                    decoded.append(high << 4 | low); index += 4; continue
                }
                if let control: UInt8 = [98: 8, 102: 12, 114: 13, 110: 10, 116: 9][bytes[index + 1]] {
                    decoded.append(control); index += 2; continue
                }
            }
            decoded.append(bytes[index]); index += 1
        }
        return String(decoding: decoded, as: UTF8.self)
    }

    public static func eject(_ drive: EjectDrive, execute: Execute? = nil, eject: Eject? = nil) async throws {
        // Revalidate immediately before every action, including each item in a batch.
        guard let current = try await load(execute: execute).first(where: { $0.id == drive.id }) else { throw USBEjectError.unavailable }
        guard current.identity == drive.identity else { throw USBEjectError.changed }
        try await (eject ?? nativeEject)(current.id)
    }

    static func nativeEject(_ id: String) async throws {
        guard isWholeDisk(id) else { throw USBEjectError.unavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let operation = NativeDiskEjection(id: id, continuation: continuation) else {
                continuation.resume(throwing: USBEjectError.unavailable); return
            }
            operation.start()
        }
    }
}

/// Disk Arbitration unmounts every volume normally before ejecting the physical disk. No force option is used.
private final class NativeDiskEjection: @unchecked Sendable {
    private let session: DASession
    private let disk: DADisk
    private let continuation: CheckedContinuation<Void, Error>
    private let queue = DispatchQueue(label: "MacPocket.disk-eject")

    init?(id: String, continuation: CheckedContinuation<Void, Error>) {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/" + id),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              // Physical/external eligibility is checked by the service before this lower-level operation.
              // Virtual media can omit this attribute; explicitly internal media are still refused here.
              description[kDADiskDescriptionDeviceInternalKey as String] as? Bool != true,
              description[kDADiskDescriptionMediaWholeKey as String] as? Bool == true else { return nil }
        self.session = session; self.disk = disk; self.continuation = continuation
    }

    func start() {
        DASessionSetDispatchQueue(session, queue)
        let context = Unmanaged.passRetained(self).toOpaque()
        DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), { _, dissenter, context in
            guard let context else { return }
            let operation = Unmanaged<NativeDiskEjection>.fromOpaque(context).takeUnretainedValue()
            if let dissenter, DADissenterGetStatus(dissenter) != kDAReturnNotMounted {
                operation.finish(dissenter, context: context)
            } else {
                DADiskEject(operation.disk, DADiskEjectOptions(kDADiskEjectOptionDefault), { _, dissenter, context in
                    guard let context else { return }
                    Unmanaged<NativeDiskEjection>.fromOpaque(context).takeUnretainedValue().finish(dissenter, context: context)
                }, context)
            }
        }, context)
    }

    private func finish(_ dissenter: DADissenter?, context: UnsafeMutableRawPointer) {
        DASessionSetDispatchQueue(session, nil)
        if let dissenter {
            let reason = DADissenterGetStatusString(dissenter).map { $0 as String }
                ?? String(localized: "macOS diskin kullanımda olduğunu bildirdi. Açık dosyaları kaydedip yeniden dene.")
            continuation.resume(throwing: USBEjectError.refused(reason))
        } else { continuation.resume() }
        Unmanaged<NativeDiskEjection>.fromOpaque(context).release()
    }
}
