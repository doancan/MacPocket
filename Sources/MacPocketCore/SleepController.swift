import Foundation
import IOKit.pwr_mgt

public struct AwakeSession: Codable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endsAt: Date?
    public let keepDisplayAwake: Bool
    public let active: Bool
    public init(id: UUID = UUID(), startedAt: Date, endsAt: Date?, keepDisplayAwake: Bool, active: Bool = true) {
        self.id = id; self.startedAt = startedAt; self.endsAt = endsAt; self.keepDisplayAwake = keepDisplayAwake; self.active = active
    }
}

public protocol IdleSleepControlling: Sendable {
    func status() async -> AwakeSession?
    func startIfIdle(sessionID: UUID, durationSeconds: Double, keepDisplayAwake: Bool) async throws -> AwakeSession?
    @discardableResult func stop(sessionID: UUID) async throws -> Bool
}

public protocol SleepControlling: IdleSleepControlling {
    func start(durationSeconds: Double?, keepDisplayAwake: Bool) async throws -> AwakeSession
    func stop() async throws
}

public enum SleepControllerError: Error, LocalizedError, Sendable {
    case invalidDuration
    case nativeCall(operation: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return String(localized: "Uyanık tutma süresi sıfırdan büyük, sonlu ve en fazla 7 gün olmalıdır.")
        case let .nativeCall(operation, code):
            return String(localized: "Uyku kontrolü başarısız: \(operation) (\(code)).")
        }
    }
}

/// Owns temporary idle-sleep assertions only. Manual sleep and lid-close behavior
/// remain controlled by macOS; no persistent power setting is changed.
public actor SleepController: SleepControlling {
    /// A finite session can last up to seven days. Nil means until manually stopped.
    public static let maximumDurationSeconds: Double = 7 * 24 * 60 * 60

    private struct OwnedAssertion: Sendable {
        let id: IOPMAssertionID
        let display: Bool
    }

    private var assertions: [OwnedAssertion] = []
    private var session: AwakeSession?
    private var expiryTask: Task<Void, Never>?

    public init() {}

    /// Claims an idle controller atomically; a concurrent manual session always keeps ownership.
    public func startIfIdle(sessionID: UUID = UUID(), durationSeconds: Double, keepDisplayAwake: Bool) throws -> AwakeSession? {
        guard status() == nil else { return nil }
        return try replace(sessionID: sessionID, durationSeconds: durationSeconds, keepDisplayAwake: keepDisplayAwake)
    }

    /// An expired automation/focus operation must never stop a replacement session.
    @discardableResult public func stop(sessionID: UUID) throws -> Bool {
        guard session?.id == sessionID else { return false }
        try stop(); return true
    }

    deinit {
        expiryTask?.cancel()
        for assertion in assertions { IOPMAssertionRelease(assertion.id) }
    }

    /// Replaces the controller's previous session; invalid input leaves it intact.
    public func start(durationSeconds: Double?, keepDisplayAwake: Bool) throws -> AwakeSession {
        try replace(sessionID: UUID(), durationSeconds: durationSeconds, keepDisplayAwake: keepDisplayAwake)
    }

    private func replace(sessionID id: UUID, durationSeconds: Double?, keepDisplayAwake: Bool) throws -> AwakeSession {
        if let durationSeconds {
            guard durationSeconds.isFinite, durationSeconds > 0,
                  durationSeconds <= Self.maximumDurationSeconds else {
                throw SleepControllerError.invalidDuration
            }
        }
        try stop()
        // Publish ownership before acquiring handles so a failed creation AND failed rollback
        // still has a UUID that its caller can clean up without touching a manual replacement.
        session = AwakeSession(id: id, startedAt: Date(), endsAt: nil, keepDisplayAwake: keepDisplayAwake)
        do {
            assertions.append(try Self.makeAssertion(sessionID: id, display: false))
            if keepDisplayAwake {
                assertions.append(try Self.makeAssertion(sessionID: id, display: true))
            }
        } catch {
            // A display assertion failure must not leave the system assertion active.
            // Failed releases remain owned so stop/deinit can retry cleanup.
            try? stop()
            throw error
        }
        let startedAt = Date()
        let newSession = AwakeSession(id: id, startedAt: startedAt,
                                      endsAt: durationSeconds.map { startedAt.addingTimeInterval($0) },
                                      keepDisplayAwake: keepDisplayAwake, active: true)
        session = newSession
        if let durationSeconds {
            expiryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(durationSeconds)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await self?.expire(sessionID: id)
            }
        }
        return newSession
    }

    /// Idempotent: releases this controller's handles and cancels its own timer.
    /// If a native release fails, its handle remains owned for a subsequent retry.
    public func stop() throws {
        expiryTask?.cancel()
        expiryTask = nil
        var remaining: [OwnedAssertion] = []
        var firstFailure: Int32?
        for assertion in assertions {
            let result = IOPMAssertionRelease(assertion.id)
            if result != kIOReturnSuccess && result != kIOReturnNotFound {
                remaining.append(assertion)
                if firstFailure == nil { firstFailure = result }
            }
        }
        assertions = remaining
        if remaining.isEmpty {
            session = nil
        } else if let old = session {
            session = AwakeSession(id: old.id, startedAt: old.startedAt, endsAt: nil,
                                   keepDisplayAwake: remaining.contains { $0.display }, active: true)
        }
        if let firstFailure {
            throw SleepControllerError.nativeCall(operation: "IOPMAssertionRelease", code: firstFailure)
        }
    }

    public func status() -> AwakeSession? {
        if let end = session?.endsAt, end <= Date() {
            try? stop()
        }
        return session
    }

    private func expire(sessionID: UUID) {
        // A cancelled or delayed timer from an older session cannot stop its replacement.
        guard session?.id == sessionID else { return }
        try? stop()
    }

    private static func makeAssertion(sessionID: UUID, display: Bool) throws -> OwnedAssertion {
        let type = display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let name = "MacPocket Awake \(sessionID.uuidString) \(display ? "display" : "system")"
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               name as CFString, &id)
        guard result == kIOReturnSuccess else {
            throw SleepControllerError.nativeCall(operation: "IOPMAssertionCreateWithName", code: result)
        }
        return OwnedAssertion(id: id, display: display)
    }
}
