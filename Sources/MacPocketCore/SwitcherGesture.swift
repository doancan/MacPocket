import Foundation

public enum SwitcherGestureAxis: String, Codable, CaseIterable, Sendable {
    case horizontal, vertical
    public var localizedTitle: String {
        switch self {
        case .horizontal: String(localized: "Yatay")
        case .vertical: String(localized: "Dikey")
        }
    }
}

/// Off by default. The original finger-count key remains compatible with existing installations.
public struct SwitcherGestureOptions: Equatable, Sendable {
    public static let fingersKey = "switcher.gestureFingers"
    public static let axisKey = "switcher.gestureAxis"
    public static let hapticsKey = "switcher.gestureHaptics"
    public let fingers: Int
    public let axis: SwitcherGestureAxis
    public let haptics: Bool
    public var enabled: Bool { fingers == 3 || fingers == 4 }
    public init(fingers: Int = 0,axis: SwitcherGestureAxis = .horizontal,haptics: Bool = false) {
        self.fingers = fingers == 3 || fingers == 4 ? fingers : 0
        self.axis = axis
        self.haptics = haptics
    }
    public static func load(_ defaults: UserDefaults = .standard) -> Self {
        .init(fingers: defaults.integer(forKey: fingersKey),
              axis: .init(rawValue: defaults.string(forKey: axisKey) ?? "") ?? .horizontal,
              haptics: defaults.object(forKey: hapticsKey) as? Bool ?? false)
    }
}

public struct SwitcherGestureContact: Equatable, Sendable {
    public let id: Int32
    public let x: Double
    public let y: Double
    public init(id: Int32,x: Double,y: Double) { self.id = id;self.x = x;self.y = y }
}

public enum SwitcherGestureEvent: Equatable, Sendable {
    case step(id: UUID,axis: SwitcherGestureAxis,backwards: Bool,count: Int)
    case ended(id: UUID)
    case cancelled(id: UUID)
    public var id: UUID {
        switch self { case .step(let id,_,_,_),.ended(let id),.cancelled(let id): id }
    }
}

/// Pure contact-frame recognizer. Device and contact identity prevent jumps from finger replacement
/// and two simultaneous trackpads. After configuration, each device must first report all fingers up.
public struct SwitcherGestureTracker: Sendable {
    public static let threshold = 0.07
    private struct Device: Sendable {
        var waitingForLift = true
        var anchors: [Int32: SwitcherGestureContact] = [:]
        var id: UUID?
        var emitted = false
        var lifting = false
    }
    private let options: SwitcherGestureOptions
    private var devices: [UInt64: Device] = [:]
    private var owner: UInt64?
    public init(options: SwitcherGestureOptions) { self.options = options }

    /// nil means an undecodable frame; [] means a genuine all-fingers-up frame.
    public mutating func process(device key: UInt64,contacts: [SwitcherGestureContact]?) -> [SwitcherGestureEvent] {
        guard options.enabled else { return [] }
        var device = devices[key] ?? Device()
        defer { devices[key] = device }
        func cancel(_ state: inout Device) -> [SwitcherGestureEvent] {
            let event = state.emitted ? state.id.map { SwitcherGestureEvent.cancelled(id: $0) } : nil
            state = Device()
            return event.map { [$0] } ?? []
        }
        guard let contacts,contacts.count <= 10,
              Set(contacts.map(\.id)).count == contacts.count,
              contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            if owner == key { owner = nil }
            return cancel(&device)
        }
        if contacts.isEmpty {
            let event = device.emitted ? device.id.map { SwitcherGestureEvent.ended(id: $0) } : nil
            if owner == key { owner = nil }
            device = Device()
            device.waitingForLift = false
            return event.map { [$0] } ?? []
        }
        guard !device.waitingForLift else { return [] }
        guard owner == nil || owner == key else { device.waitingForLift = true;return [] }
        if device.id == nil {
            guard contacts.count <= options.fingers else { device.waitingForLift = true;return [] }
            guard contacts.count == options.fingers else { return [] }
            owner = key
            device.id = UUID()
            device.anchors = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id,$0) })
            return []
        }
        let ids = Set(contacts.map(\.id)),originalIDs = Set(device.anchors.keys)
        guard ids.isSubset(of: originalIDs),contacts.count <= options.fingers else {
            owner = nil
            return cancel(&device)
        }
        // A partial lift freezes navigation until the last finger leaves. Replacing/rejoining a
        // finger is cancellation, rather than a centroid jump or an accidental commit.
        if contacts.count < options.fingers { device.lifting = true;return [] }
        guard !device.lifting else { owner = nil;return cancel(&device) }
        let dx = contacts.reduce(0) { $0 + $1.x - (device.anchors[$1.id]?.x ?? $1.x) } / Double(contacts.count)
        let dy = contacts.reduce(0) { $0 + $1.y - (device.anchors[$1.id]?.y ?? $1.y) } / Double(contacts.count)
        let primary = options.axis == .horizontal ? dx : dy,cross = options.axis == .horizontal ? dy : dx
        if abs(cross) > Self.threshold,abs(cross) > abs(primary) { owner = nil;return cancel(&device) }
        let count = Int(abs(primary) / Self.threshold)
        guard count > 0,let id = device.id else { return [] }
        let travel = (primary > 0 ? 1.0 : -1.0) * Double(count) * Self.threshold
        for contact in contacts {
            guard let anchor = device.anchors[contact.id] else { continue }
            device.anchors[contact.id] = .init(id: contact.id,x: anchor.x + (options.axis == .horizontal ? travel : 0),
                                             y: anchor.y + (options.axis == .vertical ? travel : 0))
        }
        device.emitted = true
        // CoreGraphics trackpad Y increases upwards; cards below are the forward direction.
        return [.step(id: id,axis: options.axis,backwards: options.axis == .horizontal ? primary < 0 : primary > 0,count: count)]
    }
}
