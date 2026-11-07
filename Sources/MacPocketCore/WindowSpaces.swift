import CoreGraphics
import Darwin
import Foundation

/// Position in the current Mission Control topology, not a persistent user-assigned desktop name.
public struct WindowSpace: Hashable, Sendable {
    public enum Kind: Sendable, Hashable { case desktop, fullScreen, unknown }
    public let id: UInt64
    public let ordinal: Int
    public let displayIdentifier: String
    public let kind: Kind
    public let visible: Bool
    public init(id: UInt64, ordinal: Int, displayIdentifier: String, kind: Kind, visible: Bool) {
        self.id = id; self.ordinal = ordinal; self.displayIdentifier = displayIdentifier
        self.kind = kind; self.visible = visible
    }
    public var localizedTitle: String {
        kind == .fullScreen ? String(localized: "Tam ekran masaüstü \(ordinal)") : String(localized: "Masaüstü \(ordinal)")
    }
}

public struct WindowSpaceMembership: Equatable, Sendable {
    public let spaces: [WindowSpace]
    /// Keep unmapped IDs through a topology transition; never turn them into guessed desktop numbers.
    public let unknownIDs: Set<UInt64>
    public init(spaces: [WindowSpace], unknownIDs: Set<UInt64> = []) {
        self.spaces = spaces.sorted { $0.ordinal < $1.ordinal }; self.unknownIDs = unknownIDs
    }
    public var isVisible: Bool? {
        if spaces.contains(where: \.visible) { return true }
        return !spaces.isEmpty && unknownIDs.isEmpty ? false : nil
    }
    public var firstOrdinal: Int? { unknownIDs.isEmpty ? spaces.first?.ordinal : nil }
    public var localizedDescription: String {
        var titles = spaces.map(\.localizedTitle)
        if !unknownIDs.isEmpty || titles.isEmpty { titles.append(String(localized: "Masaüstü bilgisi bilinmiyor")) }
        return titles.joined(separator: ", ")
    }
}

public struct WindowSpaceSnapshot: Sendable {
    public let spaces: [WindowSpace]
    public let memberships: [UInt32: Set<UInt64>]
    public let partial: Bool
    public var available: Bool { !spaces.isEmpty }
    public init(spaces: [WindowSpace] = [], memberships: [UInt32: Set<UInt64>] = [:], partial: Bool = false) {
        self.spaces = spaces; self.memberships = memberships; self.partial = partial
    }
    public func membership(for windowID: UInt32) -> WindowSpaceMembership? {
        guard available, let ids = memberships[windowID], !ids.isEmpty else { return nil }
        let known = spaces.filter { ids.contains($0.id) }
        return .init(spaces: known, unknownIDs: ids.subtracting(known.map(\.id)))
    }
}

public protocol WindowSpaceProviding: Sendable {
    func snapshot(windowIDs: [UInt32]) async -> WindowSpaceSnapshot
}

/// Reads private WindowServer metadata. All symbols are optional and loaded at runtime; no
/// private framework is linked and no Space, application, or window is moved or activated here.
public actor WindowSpaceProvider: WindowSpaceProviding {
    public static let shared = WindowSpaceProvider()
    private let backend: (any WindowSpaceQuerying)?
    private let queryBudget: Duration
    public init() { backend = SpaceFunctions.load(); queryBudget = .milliseconds(250) }
    init(backend: (any WindowSpaceQuerying)?, queryBudget: Duration = .milliseconds(250)) {
        self.backend = backend; self.queryBudget = queryBudget
    }

    public func snapshot(windowIDs: [UInt32]) -> WindowSpaceSnapshot {
        guard !Task.isCancelled, let backend else { return .init() }
        let connection = backend.connectionID()
        guard connection != 0, let raw = backend.copyTopology(connection: connection),
              let before = SpaceTopology.parse(raw) else { return .init() }
        var memberships: [UInt32: Set<UInt64>] = [:]
        let knownIDs = Set(before.spaces.map(\.id))
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: queryBudget)
        var partial = false
        for id in Set(windowIDs.filter { $0 > 0 }).sorted() {
            guard !Task.isCancelled, clock.now < deadline else { partial = true; break }
            guard let rawIDs = backend.copyMembership(connection: connection, windowID: id),
                  let ids = SpaceTopology.ids(rawIDs) else { partial = true; continue }
            memberships[id] = ids
            if !ids.isSubset(of: knownIDs) { partial = true }
        }
        // The user can change a Space while the per-window calls run. Discard that mixed result
        // and let the next ordinary catalog refresh retry instead of publishing stale visibility.
        guard let rawAfter = backend.copyTopology(connection: connection),
              let after = SpaceTopology.parse(rawAfter), before == after else { return .init(partial: true) }
        return .init(spaces: after.spaces, memberships: memberships, partial: partial)
    }
}

protocol WindowSpaceQuerying: Sendable {
    func connectionID() -> UInt32
    func copyTopology(connection: UInt32) -> CFArray?
    func copyMembership(connection: UInt32, windowID: UInt32) -> CFArray?
}

/// Structural decoding is kept independent of private calls, with malformed data treated as unknown.
struct SpaceTopology: Equatable, Sendable {
    let spaces: [WindowSpace]

    static func parse(_ raw: CFArray) -> SpaceTopology? {
        guard let displays = raw as? [[String: Any]], !displays.isEmpty, displays.count <= 64 else { return nil }
        var spaces: [WindowSpace] = [], seen = Set<UInt64>()
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String, !identifier.isEmpty,
                  let values = display["Spaces"] as? [[String: Any]], !values.isEmpty, values.count <= 256,
                  let current = display["Current Space"] as? [String: Any], let currentID = id(current["id64"]) else { return nil }
            var displayIDs = Set<UInt64>()
            for value in values {
                guard let spaceID = id(value["id64"]), displayIDs.insert(spaceID).inserted else { return nil }
                // With shared Spaces a WindowServer entry may cover more than one display.
                guard seen.insert(spaceID).inserted else {
                    if spaceID == currentID, let index = spaces.firstIndex(where: { $0.id == spaceID }), !spaces[index].visible {
                        let old = spaces[index]
                        spaces[index] = .init(id: old.id, ordinal: old.ordinal, displayIdentifier: old.displayIdentifier, kind: old.kind, visible: true)
                    }
                    continue
                }
                let kind: WindowSpace.Kind
                switch (value["type"] as? NSNumber)?.intValue {
                case 0: kind = .desktop
                case 4: kind = .fullScreen
                default: kind = .unknown
                }
                spaces.append(.init(id: spaceID, ordinal: spaces.count + 1, displayIdentifier: identifier,
                                    kind: kind, visible: spaceID == currentID))
            }
            guard displayIDs.contains(currentID) else { return nil }
        }
        return spaces.isEmpty ? nil : .init(spaces: spaces)
    }

    static func ids(_ raw: CFArray) -> Set<UInt64>? {
        guard let values = raw as? [Any], values.count <= 16_384 else { return nil }
        var ids = Set<UInt64>()
        for value in values {
            guard let parsed = id(value) else { return nil }
            ids.insert(parsed)
        }
        return ids
    }

    private static func id(_ value: Any?) -> UInt64? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              let result = UInt64(value.stringValue), result > 0 else { return nil }
        return result
    }
}

/// Immutable C function pointers and their process-lifetime dlopen handle. Only the provider actor
/// invokes these functions; the handle intentionally remains open while pointers may be used.
private final class SpaceFunctions: WindowSpaceQuerying, @unchecked Sendable {
    typealias Connection = @convention(c) () -> UInt32
    typealias Topology = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    typealias Membership = @convention(c) (UInt32, Int, CFArray) -> Unmanaged<CFArray>?
    let connection: Connection
    let topology: Topology
    let membership: Membership
    private let library: UnsafeMutableRawPointer
    private init(library: UnsafeMutableRawPointer, connection: Connection, topology: Topology, membership: Membership) {
        self.library = library; self.connection = connection; self.topology = topology; self.membership = membership
    }
    func connectionID() -> UInt32 { connection() }
    func copyTopology(connection: UInt32) -> CFArray? { topology(connection)?.takeRetainedValue() }
    func copyMembership(connection: UInt32, windowID: UInt32) -> CFArray? {
        membership(connection, 7, [NSNumber(value: windowID)] as CFArray)?.takeRetainedValue()
    }
    static func load() -> SpaceFunctions? {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let connection = dlsym(library, "CGSMainConnectionID"),
              let topology = dlsym(library, "CGSCopyManagedDisplaySpaces"),
              let membership = dlsym(library, "CGSCopySpacesForWindows") else { dlclose(library); return nil }
        return SpaceFunctions(library: library, connection: unsafeBitCast(connection, to: Connection.self),
                              topology: unsafeBitCast(topology, to: Topology.self), membership: unsafeBitCast(membership, to: Membership.self))
    }
}
