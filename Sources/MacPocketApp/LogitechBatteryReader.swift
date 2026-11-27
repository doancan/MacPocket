import Foundation
import IOKit.hid
import MacPocketCore

/// Reads the battery of Logitech Bluetooth mice and keyboards over HID++ 2.0. Opening a mouse or keyboard
/// needs Input Monitoring; without it `read()` reports `.notPermitted`. Runs on its own thread with its own
/// run loop.
enum LogitechBatteryReader {
    enum Outcome: Sendable {
        case readings([(name: String, kind: BluetoothBatteryDevice.Kind, reading: HIDPPBattery.Reading)])
        case notPermitted
        case none
    }

    static var accessGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    /// Shows macOS's Input Monitoring prompt (or opens the settings once it was denied).
    static func requestAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    static func read() async -> Outcome {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: readOnThisThread()) }
            thread.name = "MacPocket Logitech battery"
            thread.qualityOfService = .utility
            thread.start()
        }
    }

    private final class Replies {
        var reports: [[UInt8]] = []
    }

    private static func readOnThisThread() -> Outcome {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else { return .none }
        // Only Bluetooth devices with the HID++ collection; receivers (Unifying/Bolt) address devices by slot
        // instead.
        let candidates = devices.filter { device in
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "").lowercased()
            let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
            return transport.contains("bluetooth") && pairs.contains { $0[kIOHIDDeviceUsagePageKey] == 0xFF43 }
        }
        guard !candidates.isEmpty else { return .none }
        guard accessGranted else { return .notPermitted }
        var results: [(name: String, kind: BluetoothBatteryDevice.Kind, reading: HIDPPBattery.Reading)] = []
        var seen: Set<String> = []
        for device in candidates {
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech"
            guard !seen.contains(name) else { continue }
            let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int
            if let reading = battery(of: device) {
                seen.insert(name)
                results.append((name, usage == 6 ? .keyboard : .mouse, reading))
            }
        }
        return .readings(results)
    }

    private static func battery(of device: IOHIDDevice) -> HIDPPBattery.Reading? {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        let replies = Replies()
        let context = Unmanaged.passRetained(replies)
        defer { context.release() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer { buffer.deallocate() }
        let callback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
            guard let context, reportID == 0x11 || reportID == 0x10 else { return }
            Unmanaged<Replies>.fromOpaque(context).takeUnretainedValue().reports.append(Array(UnsafeBufferPointer(start: report, count: length)))
        }
        guard let runLoop = CFRunLoopGetCurrent() else { return nil }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, callback, context.toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        }

        /// Sends a request and waits up to `timeout` for a reply `match` accepts.
        func ask<T>(_ request: [UInt8], timeout: TimeInterval = 0.6, match: ([UInt8]) -> T?) -> T? {
            replies.reports.removeAll()
            var packet = request
            guard IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(packet[0]), &packet, packet.count) == kIOReturnSuccess else { return nil }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.05, true)
                if let found = replies.reports.lazy.compactMap(match).first { return found }
            }
            return nil
        }

        for feature in HIDPPBattery.Feature.allCases {
            guard let index = ask(HIDPPBattery.featureRequest(feature), match: { HIDPPBattery.featureIndex(from: $0) }) else { continue }
            if let reading = ask(HIDPPBattery.levelRequest(feature, index: index),
                                 match: { HIDPPBattery.reading(from: $0, feature: feature, index: index) }) {
                return reading
            }
        }
        return nil
    }
}
