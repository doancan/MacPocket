import Foundation

public struct WindowCreationObservation: Sendable, Equatable {
    public let sessionID: UUID
    public let sequence: UInt64
    public let observedAt: Date
    public init(sessionID: UUID, sequence: UInt64, observedAt: Date) {
        self.sessionID = sessionID; self.sequence = sequence; self.observedAt = observedAt
    }
}

public struct WindowLifecycleIdentity: Sendable, Equatable {
    public let windowID: UInt32
    public let processID: Int32
    public let launchedAt: Date
    public init(windowID: UInt32, processID: Int32, launchedAt: Date) {
        self.windowID = windowID; self.processID = processID; self.launchedAt = launchedAt
    }
}

public struct WindowLifecycleSnapshot: Sendable {
    struct Entry: Sendable {
        var revision: UInt64
        var creation: WindowCreationObservation?
        var identity: WindowLifecycleIdentity?
        var destroyed: Bool
    }
    public let sessionID: UUID
    public let revision: UInt64
    public let available: Bool
    let floorRevision: UInt64
    let entries: [UInt32: Entry]
    public static var unavailable: Self { .init(sessionID: UUID(), revision: 0, available: false, floorRevision: 0, entries: [:]) }

    public func creation(for identity: WindowLifecycleIdentity) -> WindowCreationObservation? {
        guard available, let entry = entries[identity.windowID], !entry.destroyed, entry.identity == identity else { return nil }
        return entry.creation
    }

    /// A changed physical ID cannot be trusted by an inventory read started before that event.
    /// Evicted history also expires old scans/handles, rather than silently treating it as live.
    public func invalidates(_ windowID: UInt32, since earlier: Self) -> Bool {
        guard available || earlier.available else { return false }
        guard available, earlier.available, sessionID == earlier.sessionID else { return true }
        return earlier.revision < floorRevision || entries[windowID].map { $0.destroyed || $0.revision > earlier.revision } == true
    }
}

public protocol WindowLifecycleProviding: Sendable {
    func snapshot(admitting identities: [WindowLifecycleIdentity]) async -> WindowLifecycleSnapshot
}

/// Primitive payload parsing is independent of the private callback and safe for unaligned data.
enum WindowLifecycleEvent: UInt32, Sendable { case created = 811, destroyed = 804 }
struct WindowLifecycleMessage: Sendable {
    let event: WindowLifecycleEvent
    let windowID: UInt32
    static func decode(event: UInt32, data: UnsafeRawPointer?, length: Int) -> Self? {
        guard let event = WindowLifecycleEvent(rawValue: event), length == MemoryLayout<UInt32>.size, let data else { return nil }
        var id: UInt32 = 0
        withUnsafeMutableBytes(of: &id) { $0.copyMemory(from: UnsafeRawBufferPointer(start: data, count: 4)) }
        return id == 0 ? nil : .init(event: event, windowID: id)
    }
}

/// Bounded observed history. Baseline snapshots never create a birth date. Numeric window IDs,
/// z-order, first-seen time, and application launch time are not window creation evidence.
struct WindowLifecycleTimeline {
    let sessionID: UUID
    private(set) var revision: UInt64 = 0
    private var floorRevision: UInt64 = 0
    private var entries: [UInt32: WindowLifecycleSnapshot.Entry] = [:]
    private let capacity: Int
    init(sessionID: UUID = UUID(), capacity: Int = 8_192) { self.sessionID = sessionID; self.capacity = max(0, capacity) }
    var snapshot: WindowLifecycleSnapshot {
        .init(sessionID: sessionID, revision: revision, available: true, floorRevision: floorRevision, entries: entries)
    }
    mutating func record(_ message: WindowLifecycleMessage, at date: Date) {
        guard message.windowID > 0 else { return }
        revision &+= 1
        switch message.event {
        case .created:
            // A duplicate delivery does not change the first observed creation order.
            if entries[message.windowID]?.destroyed == false, entries[message.windowID]?.creation != nil,
               entries[message.windowID]?.identity != nil { return }
            entries[message.windowID] = .init(revision: revision,
                creation: .init(sessionID: sessionID, sequence: revision, observedAt: date), identity: nil, destroyed: false)
        case .destroyed:
            entries[message.windowID] = .init(revision: revision, creation: nil,
                identity: entries[message.windowID]?.identity, destroyed: true)
        }
        trim()
    }
    mutating func admit(_ identities: [WindowLifecycleIdentity]) {
        let grouped = Dictionary(grouping: identities, by: \.windowID)
        for (id, facts) in grouped {
            guard id > 0, facts.count == 1, let identity = facts.first, identity.processID > 0 else { continue }
            guard var entry = entries[id] else {
                // Owner facts are useful for a later destroy notification; a baseline is still
                // not a creation event and must not advance observed chronology.
                entries[id] = .init(revision: 0, creation: nil, identity: identity, destroyed: false)
                continue
            }
            guard !entry.destroyed else { continue }
            if let known = entry.identity, known != identity {
                // Owner changes without a matching observed birth are unknown history.
                revision &+= 1
                entry = .init(revision: revision, creation: nil, identity: identity, destroyed: false)
            } else if entry.identity == nil {
                guard let creation = entry.creation, creation.observedAt >= identity.launchedAt else { continue }
                entry.identity = identity
            }
            entries[id] = entry
        }
        trim()
    }
    private mutating func trim() {
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.revision < $1.value.revision }) {
            floorRevision = max(floorRevision, oldest.value.revision)
            entries.removeValue(forKey: oldest.key)
        }
    }
}
