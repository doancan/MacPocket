import CoreGraphics
import Foundation

/// Modifier keys a switcher shortcut holds. Shift is reserved for reverse navigation.
public struct SwitcherModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = SwitcherModifiers(rawValue: 1)
    public static let option = SwitcherModifiers(rawValue: 2)
    public static let command = SwitcherModifiers(rawValue: 4)

    /// Carbon `RegisterEventHotKey` flags (cmdKey 0x100, optionKey 0x800, controlKey 0x1000).
    public var carbonFlags: UInt32 {
        (contains(.command) ? 0x0100 : 0) | (contains(.option) ? 0x0800 : 0) | (contains(.control) ? 0x1000 : 0)
    }
    public static let carbonShift: UInt32 = 0x0200

    public var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.command) ? "⌘" : "")
    }
}

/// One keyboard trigger with its own window filters.
public struct SwitcherShortcut: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    /// Virtual key code (kVK_*).
    public var keyCode: UInt16
    public var modifiers: SwitcherModifiers
    /// Nil preserves the original behavior: hold all opening modifiers. An explicit value is
    /// a nonempty subset; opening-only modifiers can stay down without delaying selection.
    public var holdModifiers: SwitcherModifiers?
    public var effectiveHoldModifiers: SwitcherModifiers { holdModifiers ?? modifiers }
    /// Explicit sets keep their identity if the opening chord later gains another modifier.
    public var holdModifierChoices: [SwitcherModifiers] {
        (1...7).map(SwitcherModifiers.init(rawValue:)).filter { modifiers.isSuperset(of: $0) }
    }
    public var releaseBehavior: SwitcherReleaseBehavior = .choose
    /// Compatibility with the original two-state setting and callers.
    public var releaseToChoose: Bool {
        get { releaseBehavior == .choose }
        set { releaseBehavior = newValue ? .choose : .hold }
    }
    public var filter = WindowListFilter()
    public var presentation = SwitcherPresentationOverrides()

    public init(keyCode: UInt16, modifiers: SwitcherModifiers, releaseToChoose: Bool = true, filter: WindowListFilter = .init(),
                releaseBehavior: SwitcherReleaseBehavior? = nil, presentation: SwitcherPresentationOverrides = .init(),holdModifiers: SwitcherModifiers? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.holdModifiers = holdModifiers
        self.releaseBehavior = releaseBehavior ?? (releaseToChoose ? .choose : .hold)
        self.filter = filter
        self.presentation = presentation
    }

    enum CodingKeys: String, CodingKey { case id, keyCode, modifiers, holdModifiers, releaseToChoose, releaseBehavior, filter, presentation }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keyCode = try values.decode(UInt16.self, forKey: .keyCode)
        modifiers = try values.decode(SwitcherModifiers.self, forKey: .modifiers)
        holdModifiers = try values.decodeIfPresent(SwitcherModifiers.self,forKey: .holdModifiers)
        let legacy = try values.decodeIfPresent(Bool.self, forKey: .releaseToChoose) ?? true
        releaseBehavior = try values.decodeIfPresent(String.self, forKey: .releaseBehavior).flatMap(SwitcherReleaseBehavior.init(rawValue:))
            ?? (legacy ? .choose : .hold)
        filter = try values.decodeIfPresent(WindowListFilter.self, forKey: .filter) ?? .init()
        presentation = try values.decodeIfPresent(SwitcherPresentationOverrides.self, forKey: .presentation) ?? .init()
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(keyCode, forKey: .keyCode)
        try values.encode(modifiers, forKey: .modifiers)
        try values.encodeIfPresent(holdModifiers,forKey: .holdModifiers)
        try values.encode(releaseToChoose, forKey: .releaseToChoose)
        try values.encode(releaseBehavior, forKey: .releaseBehavior)
        try values.encode(filter, forKey: .filter)
        try values.encode(presentation, forKey: .presentation)
    }

    public var displayName: String { modifiers.symbols + SwitcherKeys.name(for: keyCode) }

    /// Change the opening chord without replacing the independent profile settings or identity.
    public func replacingOpeningChord(keyCode: UInt16,modifiers: SwitcherModifiers) -> Self {
        var copy = self
        copy.keyCode = keyCode
        copy.modifiers = modifiers
        if let held = copy.holdModifiers,!modifiers.isSuperset(of: held) { copy.holdModifiers = nil }
        return copy
    }

    public static let maximumCount = 9
    public static let defaultOptionTab = SwitcherShortcut(keyCode: SwitcherKeys.tab, modifiers: .option)
}

public enum SwitcherKeys {
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let grave: UInt16 = 50
    public static let escape: UInt16 = 53

    private static let names: [UInt16: String] = [
        48: "⇥", 49: "Space", 50: "`", 36: "↩", 51: "⌫",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 42: "\\", 43: ",", 47: ".", 44: "/",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static func name(for keyCode: UInt16) -> String {
        if keyCode == space { return String(localized: "Boşluk") }
        return names[keyCode] ?? String(localized: "Tuş \(keyCode)")
    }
    public static func isSupported(_ keyCode: UInt16) -> Bool { names[keyCode] != nil && keyCode != escape }
}

public enum SwitcherShortcutValidation {
    /// Human-readable problems; empty means the list can be registered.
    public static func problems(_ shortcuts: [SwitcherShortcut]) -> [String] {
        var problems: [String] = []
        if shortcuts.isEmpty { problems.append(String(localized: "En az bir kısayol tanımlanmalı.")) }
        if shortcuts.count > SwitcherShortcut.maximumCount { problems.append(String(localized: "En fazla \(SwitcherShortcut.maximumCount) kısayol tanımlanabilir.")) }
        var seen = Set<String>()
        for shortcut in shortcuts {
            if shortcut.modifiers.isEmpty { problems.append(String(localized: "\(shortcut.displayName): en az bir ⌃, ⌥ veya ⌘ tuşu gerekir.")) }
            if shortcut.modifiers.rawValue & ~7 != 0 { problems.append(String(localized: "Desteklenmeyen değiştirici tuş.")) }
            if let held = shortcut.holdModifiers,held.isEmpty || held.rawValue & ~7 != 0 || !shortcut.modifiers.isSuperset(of: held) {
                problems.append(String(localized: "Basılı tutulacak tuşlar, açma kısayolundaki ⌃, ⌥ veya ⌘ tuşlarından seçilmelidir."))
            }
            if !SwitcherKeys.isSupported(shortcut.keyCode) { problems.append(String(localized: "\(shortcut.displayName): bu tuş desteklenmiyor.")) }
            if !seen.insert("\(shortcut.modifiers.rawValue)-\(shortcut.keyCode)").inserted {
                problems.append(String(localized: "\(shortcut.displayName) birden fazla kez tanımlı."))
            }
        }
        return problems
    }
}

/// Persists shortcuts as JSON in user defaults and migrates the single-preset setting.
public enum SwitcherShortcutStore {
    public static let key = "switcher.shortcuts.v2"

    public static func load(_ defaults: UserDefaults = .standard) -> [SwitcherShortcut] {
        if let data = defaults.data(forKey: key),
           let shortcuts = try? JSONDecoder().decode([SwitcherShortcut].self, from: data), !shortcuts.isEmpty {
            return Array(shortcuts.prefix(SwitcherShortcut.maximumCount))
        }
        return [migratedLegacy(defaults)]
    }

    public static func save(_ shortcuts: [SwitcherShortcut], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Array(shortcuts.prefix(SwitcherShortcut.maximumCount))) else { return }
        defaults.set(data, forKey: key)
    }

    static func migratedLegacy(_ defaults: UserDefaults) -> SwitcherShortcut {
        var shortcut: SwitcherShortcut
        switch defaults.string(forKey: "switcher.shortcut") {
        case "controlTab": shortcut = .init(keyCode: SwitcherKeys.tab, modifiers: .control)
        case "controlOptionSpace": shortcut = .init(keyCode: SwitcherKeys.space, modifiers: [.control, .option])
        default: shortcut = .defaultOptionTab
        }
        shortcut.releaseToChoose = defaults.object(forKey: "switcher.releaseToChoose") as? Bool ?? true
        shortcut.filter.includeMinimized = defaults.object(forKey: "switcher.includeMinimized") as? Bool ?? true
        shortcut.filter.includeHidden = defaults.object(forKey: "switcher.includeHidden") as? Bool ?? true
        shortcut.filter.includeWindowless = defaults.object(forKey: "switcher.includeWindowless") as? Bool ?? false
        shortcut.filter.currentApplicationOnly = defaults.bool(forKey: "switcher.currentApplication")
        return shortcut
    }
}

public enum SwitcherStyle: String, CaseIterable, Codable, Sendable {
    case thumbnails, icons, titles
    public var localizedTitle: String {
        switch self {
        case .thumbnails: String(localized: "Küçük resimler")
        case .icons: String(localized: "Uygulama simgeleri")
        case .titles: String(localized: "Başlık listesi")
        }
    }
}

/// Grid geometry for the switcher panel ("auto-size": cards shrink as the window count grows).
public struct SwitcherLayout: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let itemSize: CGSize
    public let panelSize: CGSize

    public static let padding: CGFloat = 22
    public static let spacing: CGFloat = 12
    /// Vertical room beyond the grid: an optional one-line status (permissions) and its spacing.
    public static let chrome: CGFloat = 28

    /// - Parameters:
    ///   - available: usable screen area for the panel.
    ///   - scale: user size preference, 0.6…1.4.
    public static func compute(count: Int, style: SwitcherStyle, available: CGSize, autoSize: Bool, scale: Double = 1) -> SwitcherLayout {
        let count = max(1, count)
        let maxWidth = max(320, available.width * 0.9)
        let maxHeight = max(240, available.height * 0.8)
        let scale = CGFloat(min(1.4, max(0.6, scale)))

        if style == .titles {
            let rowHeight: CGFloat = 40
            let width = min(maxWidth, 620 * scale)
            let visibleRows = min(count, Int((maxHeight - chrome - padding * 2) / (rowHeight + 4)))
            let height = chrome + padding * 2 + CGFloat(max(1, visibleRows)) * (rowHeight + 4)
            return .init(columns: 1, rows: max(1, visibleRows), itemSize: CGSize(width: width - padding * 2, height: rowHeight),
                         panelSize: CGSize(width: width, height: min(maxHeight, height)))
        }

        // Windows 11-sized previews: large enough to recognise window contents at a glance.
        let base: CGSize = style == .icons ? CGSize(width: 120, height: 124) : CGSize(width: 270, height: 200)
        let minimum: CGSize = style == .icons ? CGSize(width: 84, height: 92) : CGSize(width: 160, height: 124)
        var item = CGSize(width: max(minimum.width, base.width * scale), height: max(minimum.height, base.height * scale))
        func fits(_ size: CGSize, columns: Int) -> Bool {
            let rows = Int(ceil(Double(count) / Double(columns)))
            return CGFloat(columns) * size.width + CGFloat(columns - 1) * spacing + padding * 2 <= maxWidth
                && CGFloat(rows) * size.height + CGFloat(rows - 1) * spacing + padding * 2 + chrome <= maxHeight
        }
        var columns = max(1, Int((maxWidth - padding * 2 + spacing) / (item.width + spacing)))
        if autoSize {
            // Shrink in 5% steps until every window fits on screen without scrolling.
            while !fits(item, columns: columns), item.width > minimum.width {
                item = CGSize(width: max(minimum.width, item.width * 0.95), height: max(minimum.height, item.height * 0.95))
                columns = max(1, Int((maxWidth - padding * 2 + spacing) / (item.width + spacing)))
            }
        }
        columns = min(columns, count)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let visibleRows = max(1, min(rows, Int((maxHeight - chrome - padding * 2 + spacing) / (item.height + spacing))))
        let width = CGFloat(columns) * item.width + CGFloat(columns - 1) * spacing + padding * 2
        let height = CGFloat(visibleRows) * item.height + CGFloat(visibleRows - 1) * spacing + padding * 2 + chrome
        return .init(columns: columns, rows: rows, itemSize: item,
                     panelSize: CGSize(width: max(min(width, maxWidth), 360), height: min(height, maxHeight)))
    }
}
