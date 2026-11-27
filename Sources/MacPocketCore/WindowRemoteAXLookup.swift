@preconcurrency import ApplicationServices
import Darwin
import Foundation

/// An action-only fallback for a cold, off-Space AppKit window absent from AXWindows.
/// The optional Cocoa remote-token ABI is undocumented. Never infer a match from a title,
/// containing child or token number: require the exact live PID, CGWindowID and AXWindow role.
/// This runs on WindowCatalog's actor, never the main actor, and sends no input events.
enum WindowRemoteAXLookup {
    private typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private static let create: Create? = {
        guard let library = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let symbol = dlsym(library, "_AXUIElementCreateWithRemoteToken") else { dlclose(library); return nil }
        // Keep the function's image loaded for the process lifetime.
        return unsafeBitCast(symbol, to: Create.self)
    }()

    static func resolve(windowID: UInt32, processID: Int32) -> AXUIElement? {
        guard windowID > 0, processID > 0, AXIsProcessTrusted(), !Task.isCancelled,
              let create, let token = CFDataCreateMutable(nil, 20) else { return nil }
        CFDataSetLength(token, 20)
        guard let bytes = CFDataGetMutableBytePtr(token) else { return nil }
        memset(bytes, 0, 20)
        var pid = processID.littleEndian, cocoa: UInt32 = UInt32(0x636f636f).littleEndian
        memcpy(bytes, &pid, 4)
        memcpy(bytes + 8, &cocoa, 4)
        let clock = ContinuousClock(), start = ContinuousClock.now
        // One bounded lookup per explicit focus action; no background sweeps or retries.
        // Sparse/high AX IDs may remain unresolved, in which case focus fails explicitly.
        for serial: UInt64 in 0..<8_192 {
            guard !Task.isCancelled, clock.now - start < .milliseconds(250) else { return nil }
            var value = serial.littleEndian
            memcpy(bytes + 12, &value, 8)
            guard let candidate = create(token)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(candidate, 0.02)
            guard WindowCatalog.windowID(of: candidate) == windowID else { continue }
            var actualPID: pid_t = 0, role: CFTypeRef?
            guard !Task.isCancelled, clock.now - start < .milliseconds(250),
                  AXUIElementGetPid(candidate, &actualPID) == .success, actualPID == processID,
                  AXUIElementCopyAttributeValue(candidate, kAXRoleAttribute as CFString, &role) == .success,
                  role as? String == kAXWindowRole as String else { continue }
            return candidate
        }
        return nil
    }
}
