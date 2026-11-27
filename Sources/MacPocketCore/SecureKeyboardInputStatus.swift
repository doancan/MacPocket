import Carbon
import Foundation
import IOKit

/// Read-only diagnostics. Secure Input can prevent event taps from receiving keyboard events
/// even when tap creation succeeds. Never turns it off or inspects accessibility text fields.
public struct SecureKeyboardInputStatus: Equatable, Sendable {
    public let enabled: Bool
    public let processID: Int32?

    public static func read() -> Self {
        guard IsSecureEventInputEnabled() else { return .init(enabled: false, processID: nil) }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return .init(enabled: true, processID: nil) }
        defer { IOObjectRelease(root) }
        let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return resolve(enabled: IsSecureEventInputEnabled(), consoleUsers: users, userID: getuid())
    }

    static func resolve(enabled: Bool, consoleUsers: Any?, userID: UInt32) -> Self {
        guard enabled else { return .init(enabled: false, processID: nil) }
        let rows = consoleUsers as? [[String: Any]] ?? []
        let owners = Set(rows.compactMap { row -> Int32? in
            guard integer(row["kCGSSessionUserIDKey"]) == Int64(userID),
                  let onConsole = row["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.doubleValue == 1,
                  let pid = integer(row["kCGSSessionSecureInputPID"]), pid > 0, pid <= Int32.max else { return nil }
            return Int32(pid)
        })
        return .init(enabled: true, processID: owners.count == 1 ? owners.first : nil)
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(UInt32.max), value.rounded(.towardZero) == value else { return nil }
        return Int64(value)
    }
}
