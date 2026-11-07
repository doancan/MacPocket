import Darwin
import Foundation

public struct SwitcherNativeKeyState: Equatable, Sendable {
    public let forward: Bool
    public let reverse: Bool
    public init(forward: Bool, reverse: Bool) { self.forward = forward;self.reverse = reverse }
    var mask: Int { (forward ? 1 : 0) | (reverse ? 2 : 0) }
    init?(mask: Int) { guard (0...3).contains(mask) else { return nil };forward = mask & 1 != 0;reverse = mask & 2 != 0 }
}

protocol SwitcherNativeKeyAccess {
    func enabled(_ id: Int32) -> Bool?
    func set(_ id: Int32, enabled: Bool) -> Bool
}

enum SwitcherNativeKeyTransaction {
    static func snapshot(_ access: some SwitcherNativeKeyAccess) -> SwitcherNativeKeyState? {
        guard let forward = access.enabled(1),let reverse = access.enabled(2) else { return nil }
        return .init(forward: forward,reverse: reverse)
    }
    static func disable(_ access: some SwitcherNativeKeyAccess,original: SwitcherNativeKeyState) -> Bool {
        guard access.set(1,enabled: false),access.set(2,enabled: false),snapshot(access) == .init(forward: false,reverse: false) else {
            _ = restore(access,original: original);return false
        }
        return true
    }
    static func restore(_ access: some SwitcherNativeKeyAccess,original: SwitcherNativeKeyState) -> Bool {
        // Always attempt both keys, including when the first setter fails.
        let forward = access.set(1,enabled: original.forward),reverse = access.set(2,enabled: original.reverse)
        return forward && reverse && snapshot(access) == original
    }
}

private struct SystemSwitcherNativeKeys: SwitcherNativeKeyAccess {
    private final class Functions: @unchecked Sendable {
        typealias Query = @convention(c) (Int32) -> Bool
        typealias Set = @convention(c) (Int32,Bool) -> Int32
        let query: Query,set: Set
        private let library: UnsafeMutableRawPointer
        init?() {
            guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY | RTLD_LOCAL) else { return nil }
            guard let query = dlsym(library,"CGSIsSymbolicHotKeyEnabled"),let set = dlsym(library,"CGSSetSymbolicHotKeyEnabled") else { dlclose(library);return nil }
            self.library = library;self.query = unsafeBitCast(query,to: Query.self);self.set = unsafeBitCast(set,to: Set.self)
        }
    }
    private static let functions = Functions()
    func enabled(_ id: Int32) -> Bool? { Self.functions?.query(id) }
    func set(_ id: Int32,enabled: Bool) -> Bool { Self.functions?.set(id,enabled) == 0 }
}

public enum SwitcherNativeKeyError: Error, LocalizedError {
    case unavailable,protocolFailure
    public var errorDescription: String? {
        switch self {
        case .unavailable,.protocolFailure: String(localized: "⌘Tab için macOS kısayolu devralınamadı. Diğer kısayolları kullanabilir veya yeniden deneyebilirsin.")
        }
    }
}

/// Two-phase pipe protocol. A ready guardian knows the original state before any mutation.
/// A = acquire, H = UI heartbeat, Q = restore and quit. EOF, invalid input,
/// or missing heartbeats also restore. No preferences, input events or root privileges.
public enum SwitcherNativeKeyGuard {
    public static func currentState() -> SwitcherNativeKeyState? { SwitcherNativeKeyTransaction.snapshot(SystemSwitcherNativeKeys()) }
    public static func run() -> Int32 {
        run(access: SystemSwitcherNativeKeys())
    }
    static func run(access: some SwitcherNativeKeyAccess,heartbeatTimeout: TimeInterval = 4) -> Int32 {
        guard getuid() > 0,geteuid() == getuid(),getppid() > 1,
              NativeKeyPipe.isPipe(STDIN_FILENO),NativeKeyPipe.isPipe(STDOUT_FILENO),
              fcntl(STDOUT_FILENO,F_SETNOSIGPIPE,1) == 0,
              let original = SwitcherNativeKeyTransaction.snapshot(access) else { return 69 }
        var armed = false
        defer { if armed { _ = SwitcherNativeKeyTransaction.restore(access,original: original) } }
        guard NativeKeyPipe.write("R\(original.mask)\n",to: STDOUT_FILENO) else { return 74 }
        var lastHeartbeat = ProcessInfo.processInfo.systemUptime
        while true {
            if ProcessInfo.processInfo.systemUptime-lastHeartbeat > heartbeatTimeout { return 0 }
            var descriptor = pollfd(fd: STDIN_FILENO,events: Int16(POLLIN | POLLHUP),revents: 0)
            let result = poll(&descriptor,1,100)
            if result < 0 { if errno == EINTR { continue };return 74 }
            if result == 0 { continue }
            var bytes = [UInt8](repeating: 0,count: 64)
            let count = read(STDIN_FILENO,&bytes,bytes.count)
            if count == 0 { return 0 }
            if count < 0 { if errno == EINTR { continue };return 74 }
            for byte in bytes.prefix(count) {
                switch byte {
                case 65: // A
                    guard !armed else { _ = NativeKeyPipe.write("E\n",to: STDOUT_FILENO);return 77 }
                    armed = true
                    guard SwitcherNativeKeyTransaction.disable(access,original: original) else { _ = NativeKeyPipe.write("E\n",to: STDOUT_FILENO);return 70 }
                    lastHeartbeat = ProcessInfo.processInfo.systemUptime
                    guard NativeKeyPipe.write("A\n",to: STDOUT_FILENO) else { return 74 }
                case 72: lastHeartbeat = ProcessInfo.processInfo.systemUptime // H
                case 81: // Q
                    let restored = !armed || SwitcherNativeKeyTransaction.restore(access,original: original)
                    if restored { armed = false }
                    _ = NativeKeyPipe.write(restored ? "Q\n" : "E\n",to: STDOUT_FILENO)
                    return restored ? 0 : 70
                default: return 65
                }
            }
        }
    }
    fileprivate static func restore(_ state: SwitcherNativeKeyState) -> Bool { SwitcherNativeKeyTransaction.restore(SystemSwitcherNativeKeys(),original: state) }
}

private enum NativeKeyPipe {
    static func isPipe(_ descriptor: Int32) -> Bool {
        var info = stat()
        return fstat(descriptor,&info) == 0 && info.st_mode & S_IFMT == S_IFIFO
    }
    static func write(_ string: String,to descriptor: Int32) -> Bool {
        let bytes = Array(string.utf8)
        return bytes.withUnsafeBytes { Darwin.write(descriptor,$0.baseAddress,bytes.count) == bytes.count }
    }
    static func line(from descriptor: Int32,timeout: TimeInterval) throws -> String {
        let deadline = ProcessInfo.processInfo.systemUptime+timeout
        var bytes: [UInt8] = []
        while bytes.count < 32 {
            let remaining = deadline-ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw SwitcherNativeKeyError.protocolFailure }
            var item = pollfd(fd: descriptor,events: Int16(POLLIN | POLLHUP),revents: 0)
            let result = poll(&item,1,Int32(min(1000,remaining*1000)))
            if result < 0,errno == EINTR { continue }
            guard result > 0 else { throw SwitcherNativeKeyError.protocolFailure }
            var byte: UInt8 = 0
            guard read(descriptor,&byte,1) == 1 else { throw SwitcherNativeKeyError.protocolFailure }
            if byte == 10 { return String(decoding: bytes,as: UTF8.self) }
            bytes.append(byte)
        }
        throw SwitcherNativeKeyError.protocolFailure
    }
}

/// The termination callback runs independently of the UI thread. Its lock also ensures a late
/// callback from the old child cannot overwrite a newly acquired lease after a successful stop.
private final class NativeKeyRestoration: @unchecked Sendable {
    private let lock = NSLock()
    private var original: SwitcherNativeKeyState?
    private var active = false
    private var replacedSafely = false
    private let restore: @Sendable (SwitcherNativeKeyState) -> Bool
    init(restore: @escaping @Sendable (SwitcherNativeKeyState) -> Bool) { self.restore = restore }
    var isActive: Bool { lock.withLock { active } }
    var canReplace: Bool { lock.withLock { replacedSafely } }
    func arm(_ state: SwitcherNativeKeyState) { lock.withLock { original = state;active = true } }
    func disarm() { lock.withLock { active = false;replacedSafely = true } }
    func restoreIfNeeded() { lock.withLock { if active,let original { if restore(original) { active = false } } } }
}

@MainActor public final class SwitcherNativeKeyLease {
    private static var previous: (process: Process,state: NativeKeyRestoration)?
    private let process = Process(),input = Pipe(),output = Pipe()
    private let restoration: NativeKeyRestoration
    private var closed = false
    private var restoredAcknowledgement = false
    public var isActive: Bool { !closed && process.isRunning && restoration.isActive }
    public var isRunning: Bool { process.isRunning }
    private init(executable: URL,arguments: [String],restore: @escaping @Sendable (SwitcherNativeKeyState) -> Bool) throws {
        restoration = NativeKeyRestoration(restore: restore)
        guard fcntl(input.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1) == 0,
              fcntl(input.fileHandleForWriting.fileDescriptor,F_SETFL,O_NONBLOCK) == 0 else { throw SwitcherNativeKeyError.unavailable }
        process.executableURL = executable;process.arguments = arguments
        process.standardInput = input;process.standardOutput = output;process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            Self.previous = (process,restoration)
            try? input.fileHandleForReading.close();try? output.fileHandleForWriting.close()
            let ready = try NativeKeyPipe.line(from: output.fileHandleForReading.fileDescriptor,timeout: 1)
            guard ready.hasPrefix("R"),let mask = Int(ready.dropFirst()),let original = SwitcherNativeKeyState(mask: mask) else { throw SwitcherNativeKeyError.unavailable }
            restoration.arm(original)
            let restoration = self.restoration
            process.terminationHandler = { _ in restoration.restoreIfNeeded() }
            guard NativeKeyPipe.write("A",to: input.fileHandleForWriting.fileDescriptor),
                  try NativeKeyPipe.line(from: output.fileHandleForReading.fileDescriptor,timeout: 1) == "A" else { throw SwitcherNativeKeyError.unavailable }
        } catch {
            _ = stop();throw error
        }
    }
    public static func acquire(executable: URL) throws -> SwitcherNativeKeyLease {
        try prepareNext()
        return try .init(executable: executable,arguments: ["--switcher-native-key-guard"],restore: { SwitcherNativeKeyGuard.restore($0) })
    }
    private static func prepareNext() throws {
        if let old = previous {
            guard !old.process.isRunning || old.state.canReplace else { throw SwitcherNativeKeyError.unavailable }
            if !old.process.isRunning {
                old.state.restoreIfNeeded()
                guard !old.state.isActive else { throw SwitcherNativeKeyError.unavailable }
            }
            previous = nil
        }
    }
    /// Called from the UI heartbeat, so a stalled UI lets the child restore native switching.
    public func pulse() -> Bool { isActive && NativeKeyPipe.write("H",to: input.fileHandleForWriting.fileDescriptor) }
    /// False means the old guardian may still be restoring. Keep this lease and refuse a new
    /// acquisition until a later stop confirms it has exited; no overlapping state owners.
    @discardableResult public func stop() -> Bool {
        if closed { restoration.restoreIfNeeded();return restoredAcknowledgement || (!process.isRunning && !restoration.isActive) }
        closed = true
        if process.isRunning {
            _ = NativeKeyPipe.write("Q",to: input.fileHandleForWriting.fileDescriptor)
            if (try? NativeKeyPipe.line(from: output.fileHandleForReading.fileDescriptor,timeout: 0.5)) == "Q" {
                restoration.disarm()
                restoredAcknowledgement = true
                try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()
                return true
            }
        }
        try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()
        restoration.restoreIfNeeded()
        return !process.isRunning && !restoration.isActive
    }
    deinit {
        // Closing the owned pipe is enough for a live guardian to restore after owner release.
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }
}

#if DEBUG
/// Process-level fixture backend. Only a UUID-owned directory under the user's temp folder
/// is accepted. It exercises the same protocol without calling any WindowServer setters.
public enum SwitcherNativeKeyFixture {
    public static func valid(_ url: URL) -> Bool {
        let file = url.standardizedFileURL.resolvingSymlinksInPath(),directory = file.deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket.NativeKeyAudit").standardizedFileURL.resolvingSymlinksInPath()
        return file.lastPathComponent == "state.json" && UUID(uuidString: directory.lastPathComponent) != nil && directory.deletingLastPathComponent().path == root.path
    }
    public static func run(file: URL,timeout: TimeInterval) -> Int32 {
        guard valid(file),(0.15...4).contains(timeout) else { return 65 }
        return SwitcherNativeKeyGuard.run(access: FileAccess(url: file),heartbeatTimeout: timeout)
    }
    fileprivate struct FileAccess: SwitcherNativeKeyAccess {
        let url: URL
        func enabled(_ id: Int32) -> Bool? {
            guard let data = try? Data(contentsOf: url),let values = try? JSONSerialization.jsonObject(with: data) as? [String:Bool] else { return nil }
            return values[String(id)]
        }
        func set(_ id: Int32,enabled: Bool) -> Bool {
            if enabled,FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("deny-restoration").path) { return false }
            guard let data = try? Data(contentsOf: url),var values = try? JSONSerialization.jsonObject(with: data) as? [String:Bool] else { return false }
            values[String(id)] = enabled
            guard let encoded = try? JSONSerialization.data(withJSONObject: values) else { return false }
            do { try encoded.write(to: url,options: .atomic);return true } catch { return false }
        }
    }
}
extension SwitcherNativeKeyLease {
    public func terminateOwnedSystemGuardForAudit() -> Bool {
        guard process.arguments == ["--switcher-native-key-guard"],process.isRunning else { return false }
        process.terminate();return true
    }
    public var fixturePipeHandlesForAudit: (input: FileHandle,output: FileHandle)? {
        guard process.arguments?.first == "--switcher-native-key-guard-fixture" else { return nil }
        return (input.fileHandleForWriting,output.fileHandleForReading)
    }
    public static func fixture(executable: URL,file: URL,timeout: TimeInterval = 0.4) throws -> SwitcherNativeKeyLease {
        guard SwitcherNativeKeyFixture.valid(file),(0.15...4).contains(timeout) else { throw SwitcherNativeKeyError.protocolFailure }
        try prepareNext()
        return try .init(executable: executable,arguments: ["--switcher-native-key-guard-fixture",file.path,String(timeout)],restore: { state in
            SwitcherNativeKeyTransaction.restore(SwitcherNativeKeyFixture.FileAccess(url: file),original: state)
        })
    }
    public func killFixtureChildForAudit() {
        guard process.arguments?.first == "--switcher-native-key-guard-fixture",process.isRunning else { return }
        process.terminate()
    }
}
#endif
