import Foundation
import IOKit

public enum CableRegistryReader {
    public struct Snapshot: Sendable {
        public let nodes: [CableRegistryNode]
        public let complete: Bool
    }

    /// No user clients, device opens or property writes. Registry IDs identify this attachment only.
    public static func read() -> Snapshot {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return .init(nodes: [], complete: false)
        }
        defer { IOObjectRelease(iterator) }
        var nodes: [CableRegistryNode] = [], seen = Set<UInt64>(), complete = true
        let deadline = ContinuousClock.now + .seconds(5)
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard nodes.count < 20000, ContinuousClock.now < deadline, !Task.isCancelled else { complete = false; break }
            guard let id = entryID(entry), seen.insert(id).inserted else { continue }
            var classBytes = [CChar](repeating: 0, count: 128), nameBytes = classBytes
            IOObjectGetClass(entry, &classBytes)
            IORegistryEntryGetName(entry, &nameBytes)
            let className = decode(classBytes), registryName = decode(nameBytes)
            var properties: [String: Any] = [:]
            let usb = IOObjectConformsTo(entry, "IOUSBHostDevice") != 0
            let thunderbolt = className.hasPrefix("IOThunderboltSwitch")
            let relevant = usb || thunderbolt || IOObjectConformsTo(entry, "IOMedia") != 0 ||
                IOObjectConformsTo(entry, "IONetworkInterface") != 0 || className.contains("Audio") ||
                className.contains("Display") || className.contains("Framebuffer") || className == "AppleCLCD2"
            if relevant {
                var value: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(entry, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                    properties = value?.takeRetainedValue() as? [String: Any] ?? [:]
                }
            }
            func text(_ keys: String...) -> String? {
                keys.lazy.compactMap { properties[$0] as? String }.first { !$0.isEmpty }
            }
            let product = (properties["DisplayAttributes"] as? [String: Any])?["ProductAttributes"] as? [String: Any]
            let vendor = (properties["DisplayVendorID"] as? NSNumber)?.uint32Value ?? (product?["LegacyManufacturerID"] as? NSNumber)?.uint32Value
            let model = (properties["DisplayProductID"] as? NSNumber)?.uint32Value ?? (product?["ProductID"] as? NSNumber)?.uint32Value
            let serial = (properties["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? (product?["SerialNumber"] as? NSNumber)?.uint32Value ?? 0
            let display = vendor.flatMap { v in model.map { CableDisplayIdentity(vendor: v, product: $0, serial: serial) } }
            let uid = text("IOAudioEngineGlobalUniqueID", "IOAudioDeviceGlobalUniqueID", "IOAudioDeviceUID", "DeviceUID")
            let bsd = text("BSD Name")
            let remoteThunderbolt = thunderbolt && ((properties["Route String"] as? NSNumber)?.uint64Value ?? 0) != 0
            let kind: CableRegistryNode.Kind
            if usb { kind = .usb }
            else if remoteThunderbolt { kind = .thunderbolt }
            else if display != nil { kind = .display }
            else if uid != nil { kind = .audio }
            else if IOObjectConformsTo(entry, "IOMedia") != 0 { kind = .media }
            else if IOObjectConformsTo(entry, "IONetworkInterface") != 0 { kind = .network }
            else { kind = .service }
            let builtIn = (properties["Built-In"] as? Bool) == true || (properties["built-in"] as? Bool) == true ||
                (properties["built-in"] as? Data)?.contains(where: { $0 != 0 }) == true ||
                (usb && (properties["USBPortType"] as? NSNumber)?.intValue == 2)
            let name = usb ? text("USB Product Name", "kUSBProductString") ?? registryName :
                remoteThunderbolt ? text("Device Name", "Device Model Name") ?? String(localized: "Thunderbolt aygıtı") : registryName
            let parents = parents(of: entry)
            if !parents.complete { complete = false }
            nodes.append(.init(id: id, parents: parents.ids, name: name, kind: kind, containerID: text("kUSBContainerID"),
                               builtIn: builtIn, bsdName: bsd, audioUID: uid, displayIdentity: display))
        }
        if IOIteratorIsValid(iterator) == 0 { complete = false }
        return .init(nodes: nodes, complete: complete)
    }

    public static func entriesStillPresent(_ ids: Set<UInt64>) -> Bool {
        ids.allSatisfy { id in
            guard let matching = IORegistryEntryIDMatching(id) else { return false }
            let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            guard entry != 0 else { return false }
            IOObjectRelease(entry)
            return true
        }
    }

    private static func parents(of entry: io_registry_entry_t) -> (ids: Set<UInt64>, complete: Bool) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetParentIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return ([], false) }
        defer { IOObjectRelease(iterator) }
        var ids = Set<UInt64>()
        while case let parent = IOIteratorNext(iterator), parent != 0 {
            defer { IOObjectRelease(parent) }
            guard ids.count < 32 else { return (ids, false) }
            if let id = entryID(parent) { ids.insert(id) }
        }
        return (ids, true)
    }
    private static func entryID(_ entry: io_registry_entry_t) -> UInt64? {
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS ? id : nil
    }
    private static func decode(_ bytes: [CChar]) -> String {
        String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
