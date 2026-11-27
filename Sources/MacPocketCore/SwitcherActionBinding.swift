import Foundation

public enum SwitcherActiveAction: String, CaseIterable, Codable, Sendable {
    case choose, previous, cancel, search, close, minimizeRestore, fullScreen, hide, quit
    public var localizedTitle: String {
        switch self {
        case .choose: String(localized: "Seçili pencereye geç")
        case .previous: String(localized: "Önceki pencere")
        case .cancel: String(localized: "Vazgeç")
        case .search: String(localized: "Aramaya geç")
        case .close: String(localized: "Pencereyi kapat")
        case .minimizeRestore: String(localized: "Küçült veya geri getir")
        case .fullScreen: String(localized: "Tam ekranı değiştir")
        case .hide: String(localized: "Uygulamayı gizle")
        case .quit: String(localized: "Uygulamadan çık")
        }
    }
}

public struct SwitcherActionBinding: Codable, Hashable, Identifiable, Sendable {
    public var id: SwitcherActiveAction { action }
    public var action: SwitcherActiveAction
    public var keyCode: UInt16?
    public var modifiers: SwitcherModifiers = []
    public var shift = false
    public init(action: SwitcherActiveAction, keyCode: UInt16?, modifiers: SwitcherModifiers = [], shift: Bool = false) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.shift = shift
    }
    public var displayName: String {
        guard let keyCode else { return String(localized: "Kapalı") }
        return modifiers.symbols + (shift ? "⇧" : "") + SwitcherKeys.name(for: keyCode)
    }
    public static let defaults: [Self] = [
        .init(action: .choose, keyCode: 36), .init(action: .previous, keyCode: SwitcherKeys.tab, shift: true),
        .init(action: .cancel, keyCode: SwitcherKeys.escape), .init(action: .search, keyCode: 1, modifiers: .command),
        .init(action: .close, keyCode: 13, modifiers: .command), .init(action: .minimizeRestore, keyCode: 46, modifiers: .command),
        .init(action: .fullScreen, keyCode: 3, modifiers: .command), .init(action: .hide, keyCode: 4, modifiers: .command),
        .init(action: .quit, keyCode: 12, modifiers: .command),
    ]
}

public enum SwitcherActionBindings {
    public static let key = "switcher.actions.v1"
    private static let textKeys: Set<UInt16> = Set(0...35).union([37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 49, 50, 51])
    public static func load(_ defaults: UserDefaults = .standard) -> [SwitcherActionBinding] {
        guard let data = defaults.data(forKey: key), let stored = try? JSONDecoder().decode([SwitcherActionBinding].self, from: data),
              problems(stored).isEmpty else { return SwitcherActionBinding.defaults }
        let merged = SwitcherActionBinding.defaults.map { original in stored.first(where: { $0.action == original.action }) ?? original }
        return problems(merged).isEmpty ? merged : SwitcherActionBinding.defaults
    }
    public static func save(_ bindings: [SwitcherActionBinding], _ defaults: UserDefaults = .standard) {
        guard problems(bindings).isEmpty, let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: key)
    }
    public static func problems(_ bindings: [SwitcherActionBinding]) -> [String] {
        var messages: [String] = []
        var seenActions = Set<SwitcherActiveAction>(), seenKeys = Set<String>()
        for binding in bindings {
            if !seenActions.insert(binding.action).inserted { messages.append(String(localized: "Aynı eylem birden fazla kez tanımlanamaz.")) }
            guard let code = binding.keyCode else { continue }
            if binding.action == .choose && binding.modifiers.isEmpty && textKeys.contains(code) {
                messages.append(String(localized: "Seçim kısayolu için Enter, bir işlev tuşu veya değiştiricili bir tuş kullan."))
            }
            let reservedNavigation = binding.modifiers.isEmpty && code == SwitcherKeys.tab
            let previousTab = binding.action == .previous && code == SwitcherKeys.tab && binding.shift
            if (!SwitcherKeys.isSupported(code) && !(code == SwitcherKeys.escape && binding.action == .cancel))
                || (code == SwitcherKeys.escape && binding.action != .cancel)
                || (reservedNavigation && !previousTab)
                || (code == SwitcherKeys.tab && binding.modifiers == .command) {
                messages.append(String(localized: "\(binding.displayName): bu tuş gezinme veya vazgeçme için ayrılmıştır."))
            }
            if binding.modifiers.rawValue & ~7 != 0 { messages.append(String(localized: "Desteklenmeyen değiştirici tuş.")) }
            if !seenKeys.insert("\(code):\(binding.modifiers.rawValue):\(binding.shift)").inserted {
                messages.append(String(localized: "\(binding.displayName) birden fazla eyleme atanmış."))
            }
        }
        return messages
    }

    public static func action(for keyCode: UInt16, modifiers: SwitcherModifiers, shift: Bool, held: SwitcherModifiers,
                              isSearching: Bool, bindings: [SwitcherActionBinding]) -> SwitcherActiveAction? {
        let effective = modifiers.subtracting(held)
        // Bare letters remain text while searching, including a custom bare-letter action.
        if isSearching && effective.isEmpty && textKeys.contains(keyCode) { return nil }
        let match = bindings.first { $0.keyCode == keyCode && $0.modifiers == effective && $0.shift == shift }
            ?? (!isSearching ? bindings.first { $0.keyCode == keyCode && $0.modifiers == modifiers && $0.shift == shift } : nil)
        guard let match else { return nil }
        return match.action
    }
}
