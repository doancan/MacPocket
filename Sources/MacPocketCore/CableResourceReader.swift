import AppKit
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import SystemConfiguration

public enum CableResourceReader {
    public static func read() async throws -> CableInventory {
        async let registry = Task.detached(priority: .utility) { CableRegistryReader.read() }.value
        var issues: [String] = [], drives: [EjectDrive] = []
        do { drives = try await USBEject.load() }
        catch { try Task.checkCancellation(); issues.append(String(localized: "Disk envanteri okunamadı: \(error.localizedDescription)")) }
        let snapshot = await registry
        try Task.checkCancellation()
        if !snapshot.complete { issues.append(String(localized: "Donanım ağacı kısmen okunabildi. Eksik bağlantılar olabilir.")) }
        let displayNames = await MainActor.run {
            Dictionary(NSScreen.screens.compactMap { screen -> (UInt32, String)? in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
                return (id, screen.localizedName)
            }, uniquingKeysWith: { first, _ in first })
        }
        let resources = await Task.detached(priority: .utility) {
            systemResources(nodes: snapshot.nodes, displayNames: displayNames)
        }.value
        try Task.checkCancellation()
        var endpoints = resources.endpoints, byID: [String: EjectDrive] = [:]
        for drive in drives {
            let id = "disk:" + drive.identity
            byID[id] = drive
            let entries = Set(snapshot.nodes.filter { $0.kind == .media && $0.bsdName == drive.id }.map(\.id))
            endpoints.append(.init(id: id, name: drive.name, kind: .storage, registryIDs: entries,
                                   detail: drive.mountPaths.joined(separator: " · "), active: !drive.mountPaths.isEmpty))
        }
        endpoints += snapshot.nodes.filter { !$0.builtIn && ($0.kind == .usb || $0.kind == .thunderbolt) }.map {
            .init(id: "device:\($0.id)", name: $0.name, kind: .usb, registryIDs: [$0.id])
        }
        let end = await Task.detached(priority: .utility) { CableRegistryReader.read() }.value
        try Task.checkCancellation()
        guard Set(snapshot.nodes.filter { $0.kind != .service }) == Set(end.nodes.filter { $0.kind != .service }) else {
            throw NSError(domain: "MacPocket.CableImpact", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Donanım okunurken bağlantılar değişti. Listeyi yeniden yenile.")])
        }
        return .init(nodes: snapshot.nodes, connections: CableTopology.connections(in: snapshot.nodes), endpoints: endpoints,
                     drives: byID, issues: issues + resources.issues, networkAddressInterfaces: resources.networkOwners)
    }

    private static func systemResources(nodes: [CableRegistryNode], displayNames: [UInt32: String]) -> (endpoints: [CableEndpoint], issues: [String], networkOwners: [String: Set<String>]) {
        var issues: [String] = []
        let network = networkResources(nodes: nodes)
        if !network.complete { issues.append(String(localized: "Ağ arayüzlerinin tamamı okunamadı.")) }
        let audio = audioResources(nodes: nodes)
        if !audio.complete { issues.append(String(localized: "Ses aygıtlarının tamamı okunamadı.")) }
        let displays = displayResources(nodes: nodes, names: displayNames)
        if !displays.complete { issues.append(String(localized: "Ekranların tamamı okunamadı.")) }
        return (network.items + audio.items + displays.items, issues, network.owners)
    }

    private static func networkResources(nodes: [CableRegistryNode]) -> (items: [CableEndpoint], complete: Bool, owners: [String: Set<String>]) {
        var addresses: [String: Set<String>] = [:], active = Set<String>()
        var head: UnsafeMutablePointer<ifaddrs>?
        let complete = getifaddrs(&head) == 0
        if let head {
            defer { freeifaddrs(head) }
            var current: UnsafeMutablePointer<ifaddrs>? = head
            while let entry = current {
                defer { current = entry.pointee.ifa_next }
                let info = entry.pointee, name = String(cString: info.ifa_name)
                if info.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING) { active.insert(name) }
                guard let address = info.ifa_addr, [AF_INET, AF_INET6].contains(Int32(address.pointee.sa_family)) else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let value = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    if let canonical = CableSessionParser.canonicalAddress(value) { addresses[name, default: []].insert(canonical) }
                }
            }
        }
        let store = SCDynamicStoreCreate(nil, "MacPocket.CableImpact" as CFString, nil, nil)
        let primary = Set(["IPv4", "IPv6"].compactMap { family -> String? in
            (SCDynamicStoreCopyValue(store, "State:/Network/Global/\(family)" as CFString) as? [String: Any])?["PrimaryInterface"] as? String
        })
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let names = Dictionary(interfaces.compactMap { interface -> (String, String)? in
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  SCNetworkInterfaceGetInterfaceType(interface) as String? == kSCNetworkInterfaceTypeEthernet as String else { return nil }
            return (bsd, SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsd)
        }, uniquingKeysWith: { first, _ in first })
        let entries = Dictionary(grouping: nodes.filter { $0.kind == .network && $0.bsdName != nil }, by: { $0.bsdName! })
        var owners: [String: Set<String>] = [:]
        for (name, values) in addresses { for address in values { owners[address, default: []].insert(name) } }
        return (names.keys.sorted().map { bsd in
            .init(id: "network:\(bsd):" + (entries[bsd] ?? []).map { String($0.id) }.sorted().joined(separator: ","),
                  name: names[bsd] ?? bsd, kind: .network, registryIDs: Set((entries[bsd] ?? []).map(\.id)),
                  detail: bsd, active: active.contains(bsd) && !(addresses[bsd] ?? []).isEmpty,
                  isDefault: primary.contains(bsd), interfaceName: bsd, addresses: addresses[bsd] ?? [])
        }, complete && store != nil, owners)
    }

    private static func displayResources(nodes: [CableRegistryNode], names: [UInt32: String]) -> (items: [CableEndpoint], complete: Bool) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 64), count: UInt32 = 0
        guard CGGetOnlineDisplayList(64, &ids, &count) == .success else { return ([], false) }
        let external = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
        let identities = Dictionary(grouping: external) { id in
            CableDisplayIdentity(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
        }
        return (external.enumerated().map { index, id in
            let identity = CableDisplayIdentity(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
            // Two identical serial-less displays cannot be assigned by registry iteration order.
            let matches = nodes.filter { $0.kind == .display && $0.displayIdentity == identity }
            let entries = identities[identity]?.count == 1 && matches.count == 1 ? Set(matches.map(\.id)) : []
            return .init(id: "display:\(identity.vendor):\(identity.product):\(identity.serial):\(id)", name: names[id] ?? String(localized: "Harici ekran \(index + 1)"), kind: .display,
                         registryIDs: entries, detail: "\(CGDisplayPixelsWide(id)) × \(CGDisplayPixelsHigh(id))",
                         active: CGDisplayIsActive(id) != 0, isDefault: CGDisplayIsMain(id) != 0)
        }, count < 64)
    }

    private static func audioResources(nodes: [CableRegistryNode]) -> (items: [CableEndpoint], complete: Bool) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let devices = audioArray(system, kAudioHardwarePropertyDevices) else { return ([], false) }
        let defaultOutput = audioValue(system, kAudioHardwarePropertyDefaultOutputDevice)
        let defaultInput = audioValue(system, kAudioHardwarePropertyDefaultInputDevice)
        var processes: [AudioObjectID: [String]] = [:]
        for object in audioArray(system, kAudioHardwarePropertyProcessObjectList) ?? [] {
            guard let pid = audioValue(object, kAudioProcessPropertyPID), pid > 0 else { continue }
            for (scope, selector) in [(kAudioObjectPropertyScopeInput, kAudioProcessPropertyIsRunningInput),
                                      (kAudioObjectPropertyScopeOutput, kAudioProcessPropertyIsRunningOutput)] {
                guard audioValue(object, selector) == 1 else { continue }
                let name = audioString(object, kAudioProcessPropertyBundleID) ?? String(localized: "Süreç")
                for device in audioArray(object, kAudioProcessPropertyDevices, scope: scope) ?? [] {
                    processes[device, default: []].append("\(name) (\(pid))")
                }
            }
        }
        let transports: Set<UInt32> = [kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt,
                                        kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort]
        let items = devices.compactMap { id -> CableEndpoint? in
            guard let uid = audioString(id, kAudioDevicePropertyDeviceUID), let name = audioString(id, kAudioObjectPropertyName) else { return nil }
            let entries = nodes.filter { $0.audioUID == uid }
            guard transports.contains(audioValue(id, kAudioDevicePropertyTransportType) ?? 0) || !entries.isEmpty else { return nil }
            var details: [String] = []
            if id == defaultOutput { details.append(String(localized: "Varsayılan ses çıkışı")) }
            if id == defaultInput { details.append(String(localized: "Varsayılan mikrofon")) }
            if let users = processes[id] { details.append(String(localized: "Kullanan süreçler: \(Set(users).sorted().joined(separator: ", "))")) }
            return .init(id: "audio:\(uid):\(id)", name: name, kind: .audio, registryIDs: Set(entries.map(\.id)),
                         detail: details.joined(separator: " · "), active: audioValue(id, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1,
                         isDefault: id == defaultOutput || id == defaultInput)
        }
        return (items, true)
    }

    private static func audioArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [UInt32]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size <= 65536, size % 4 == 0 else { return nil }
        guard size > 0 else { return [] }
        var values = [UInt32](repeating: 0, count: Int(size) / 4)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values) == noErr else { return nil }
        return values
    }
    private static func audioValue(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 4, value: UInt32 = 0
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    private static func audioString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size), value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
