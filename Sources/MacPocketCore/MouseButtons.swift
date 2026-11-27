import Foundation

/// Core Graphics button numbers. Primary/secondary clicks can never be assigned. 100/101 are side-wheel
/// directions.
public struct MouseButtonInput: RawRepresentable, Hashable, Identifiable, Sendable, CaseIterable {
    public let rawValue: Int
    public var id: Int { rawValue }
    public var key: String { String(rawValue) }
    public init?(rawValue: Int) {
        guard (2...31).contains(rawValue) || rawValue == 100 || rawValue == 101 else { return nil }
        self.rawValue = rawValue
    }
    public static let allCases = ((2...31).map { $0 } + [100, 101]).compactMap(Self.init(rawValue:))
    public static let common = [2, 3, 4, 100, 101].compactMap(Self.init(rawValue:))
    public var isWheel: Bool { rawValue >= 100 }
    public var localizedTitle: String {
        switch rawValue {
        case 2: String(localized: "Orta tuş")
        case 3: String(localized: "Yan tuş 1")
        case 4: String(localized: "Yan tuş 2")
        case 100: String(localized: "Yan teker sola")
        case 101: String(localized: "Yan teker sağa")
        default: String(localized: "Fare tuşu \(rawValue + 1)")
        }
    }

    /// Continuous trackpad/Magic Mouse gestures and diagonal/vertical packets are never side-wheel shortcuts.
    public static func wheel(vertical: Double, horizontal: Double, continuous: Bool) -> Self? {
        guard !continuous, vertical.isFinite, horizontal.isFinite, abs(horizontal) > abs(vertical) else { return nil }
        return Self(rawValue: horizontal > 0 ? 100 : 101)
    }
}

public enum MouseButtonAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case native, back, forward, copy, paste, shortcut, commandBar, clipboard, shelf
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .native: String(localized: "Değiştirme")
        case .back: String(localized: "Geri git")
        case .forward: String(localized: "İleri git")
        case .copy: String(localized: "Kopyala")
        case .paste: String(localized: "Yapıştır")
        case .shortcut: String(localized: "Özel kısayol")
        case .commandBar: String(localized: "Komut Çubuğu")
        case .clipboard: String(localized: "Pano Geçmişi")
        case .shelf: String(localized: "Dosya Rafı")
        }
    }
}

public struct MouseButtonBinding: Codable, Equatable, Sendable {
    public var action: MouseButtonAction
    public var shortcut: KeyCombo?
    public init(_ action: MouseButtonAction, shortcut: KeyCombo? = nil) { self.action = action; self.shortcut = shortcut }
    public var keyCombo: KeyCombo? {
        switch action {
        case .back: .init(keyCode: 33, modifiers: .command)
        case .forward: .init(keyCode: 30, modifiers: .command)
        case .copy: .init(keyCode: 8, modifiers: .command)
        case .paste: .init(keyCode: 9, modifiers: .command)
        case .shortcut: shortcut
        default: nil
        }
    }
    public var isExecutable: Bool {
        guard action != .native else { return false }
        if [.back, .forward, .copy, .paste, .shortcut].contains(action) {
            guard let combo = keyCombo else { return false }
            return SwitcherKeys.isSupported(combo.keyCode) && combo.modifiers.rawValue & ~15 == 0
        }
        return true
    }
}

public struct MouseButtonSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var bindings: [String: MouseButtonBinding] = ["3": .init(.back), "4": .init(.forward)]
    /// Missing key inherits the global binding; explicit .native opts out for that input.
    public var profiles: [String: [String: MouseButtonBinding]] = [:]
    public var excludedBundleIDs: [String] = []
    public static let storageKey = "MacPocket.mouseButtons.settings"
    public init() {}

    public func binding(for input: MouseButtonInput, application: String?) -> MouseButtonBinding {
        guard enabled, application.map({ !excludedBundleIDs.contains($0) }) ?? true else { return .init(.native) }
        return application.flatMap { profiles[$0]?[input.key] } ?? bindings[input.key] ?? .init(.native)
    }
    public func explicitBinding(for input: MouseButtonInput, application: String?) -> MouseButtonBinding? {
        if let application { return profiles[application]?[input.key] }
        return bindings[input.key]
    }
    public mutating func set(_ binding: MouseButtonBinding?, for input: MouseButtonInput, application: String?) {
        if let application { profiles[application, default: [:]][input.key] = binding }
        else { bindings[input.key] = binding }
    }
    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey), data.count <= 1_048_576,
              var result = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        func valid(_ dictionary: [String: MouseButtonBinding]) -> [String: MouseButtonBinding] {
            dictionary.filter { Int($0.key).flatMap(MouseButtonInput.init(rawValue:)) != nil }
        }
        result.bindings = valid(result.bindings)
        result.profiles = result.profiles.filter { !$0.key.isEmpty && $0.key.utf8.count <= 512 }
            .sorted { $0.key < $1.key }.prefix(128).reduce(into: [:]) { $0[$1.key] = valid($1.value) }
        result.excludedBundleIDs = Array(Set(result.excludedBundleIDs.filter { !$0.isEmpty && $0.utf8.count <= 512 })).sorted().prefix(256).map { $0 }
        return result
    }
    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Pair ownership survives profile/settings changes. Drag/up packets for a consumed down never reach the app.
public struct MouseButtonRouter: Sendable {
    public enum Phase: Sendable { case down, drag, up }
    public enum Decision: Equatable, Sendable { case pass, consume, perform(MouseButtonBinding) }
    public private(set) var pressed: Set<Int> = []
    private var wheelInput: Int?
    private var wheelTime: Double = -.infinity
    public init() {}
    public mutating func button(_ number: Int, phase: Phase, proposed: MouseButtonBinding?) -> Decision {
        guard let input = MouseButtonInput(rawValue: number), !input.isWheel else { return .pass }
        switch phase {
        case .up: return pressed.remove(number) == nil ? .pass : .consume
        case .drag: return pressed.contains(number) ? .consume : .pass
        case .down:
            if pressed.contains(number) { return .consume }
            guard let proposed, proposed.isExecutable else { return .pass }
            pressed.insert(number)
            return .perform(proposed)
        }
    }
    /// One shortcut per continuous burst; opposite direction and a quiet gap start a new burst.
    public mutating func wheel(_ input: MouseButtonInput, at time: Double, proposed: MouseButtonBinding?) -> Decision {
        guard input.isWheel, time.isFinite, let proposed, proposed.isExecutable else { return .pass }
        defer { wheelInput = input.rawValue; wheelTime = time }
        if wheelInput == input.rawValue, time >= wheelTime, time - wheelTime < 0.15 { return .consume }
        return .perform(proposed)
    }
    public mutating func reset() { self = .init() }
}
