import Foundation

public enum SwitcherExceptionTarget: String, Codable, CaseIterable, Sendable {
    case applicationPath, bundleIdentifier, bundlePrefix
    public var localizedTitle: String {
        switch self {
        case .applicationPath: String(localized: "Uygulama yolu")
        case .bundleIdentifier: String(localized: "Tam bundle kimliği")
        case .bundlePrefix: String(localized: "Bundle kimliği öneki")
        }
    }
}
public enum SwitcherExceptionVisibility: String, Codable, CaseIterable, Sendable {
    case show, alwaysHide, windowless, titleContains
    public var localizedTitle: String {
        switch self {
        case .show: String(localized: "Gizleme kuralı yok")
        case .alwaysHide: String(localized: "Her zaman gizle")
        case .windowless: String(localized: "Açık penceresi yokken gizle")
        case .titleContains: String(localized: "Başlıkta metin geçiyorsa gizle")
        }
    }
}
public enum SwitcherExceptionShortcuts: String, Codable, CaseIterable, Sendable {
    case allow, alwaysDisable, fullscreen
    public var localizedTitle: String {
        switch self {
        case .allow: String(localized: "Etkin bırak")
        case .alwaysDisable: String(localized: "Öndeyken kapat")
        case .fullscreen: String(localized: "Yalnız tam ekranda kapat")
        }
    }
}

/// Independent visibility and shortcut policies. Multiple matching rules combine with OR.
/// Text matching is literal and case sensitive; an empty target never matches every app.
public struct SwitcherExceptionRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var enabled: Bool
    public var target: SwitcherExceptionTarget
    public var value: String
    public var visibility: SwitcherExceptionVisibility
    public var titlePatterns: [String]
    public var shortcuts: SwitcherExceptionShortcuts
    public init(id: String = UUID().uuidString, enabled: Bool = true, target: SwitcherExceptionTarget,
                value: String, visibility: SwitcherExceptionVisibility = .show, titlePatterns: [String] = [],
                shortcuts: SwitcherExceptionShortcuts = .allow) {
        self.id = id
        self.enabled = enabled
        self.target = target
        self.value = value
        self.visibility = visibility
        self.titlePatterns = titlePatterns
        self.shortcuts = shortcuts
    }
    public func matches(bundleIdentifier: String?, applicationPath: String?) -> Bool {
        guard enabled, !value.isEmpty else { return false }
        switch target {
        case .applicationPath: return applicationPath == value
        case .bundleIdentifier: return bundleIdentifier == value
        case .bundlePrefix: return bundleIdentifier?.hasPrefix(value) == true
        }
    }
    public func hides(_ window: SwitchableWindow) -> Bool {
        guard matches(bundleIdentifier: window.bundleIdentifier, applicationPath: window.applicationURL?.path) else { return false }
        switch visibility {
        case .show: return false
        case .alwaysHide: return true
        case .windowless: return !window.isRealWindow
        case .titleContains: return window.isRealWindow && titlePatterns.contains { !$0.isEmpty && window.title.contains($0) }
        }
    }
    public func disablesShortcuts(bundleIdentifier: String?, applicationPath: String?, fullscreen: Bool?) -> Bool {
        matches(bundleIdentifier: bundleIdentifier, applicationPath: applicationPath)
            && (shortcuts == .alwaysDisable || (shortcuts == .fullscreen && fullscreen == true))
    }
    public var validationMessage: String? {
        if id.isEmpty || value.isEmpty { return String(localized: "Bir uygulama yolu veya bundle kimliği gir.") }
        if value.count > 1024 { return String(localized: "Uygulama hedefi 1024 karakteri aşamaz.") }
        if target == .applicationPath {
            if !value.hasPrefix("/") || URL(fileURLWithPath: value).pathExtension.caseInsensitiveCompare("app") != .orderedSame { return String(localized: "Uygulama yolu / ile başlamalı ve .app ile bitmelidir.") }
        } else if !value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45,46,95].contains($0) }) {
            return String(localized: "Bundle kimliğinde yalnız harf, rakam, nokta, kısa çizgi ve alt çizgi kullan.")
        }
        if visibility == .show && shortcuts == .allow { return String(localized: "Bir gizleme veya kısayol kapatma davranışı seç.") }
        if visibility == .titleContains && titlePatterns.allSatisfy(\.isEmpty) { return String(localized: "Gizlenecek pencere başlığından en az bir metin gir.") }
        if titlePatterns.count > 32 || titlePatterns.contains(where: { $0.count > 512 }) { return String(localized: "En fazla 32 başlık metni kullan; her metin 512 karakteri aşamaz.") }
        return nil
    }
}

public enum SwitcherExceptionStore {
    public static let key = "switcher.exceptions.v1"
    public static let maximumCount = 128
    public struct Loaded: Sendable { public let rules: [SwitcherExceptionRule]; public let error: String? }
    public static func load(_ defaults: UserDefaults = .standard) -> Loaded {
        if defaults.object(forKey: key) != nil {
            if let data = defaults.data(forKey: key), let rules = try? JSONDecoder().decode([SwitcherExceptionRule].self, from: data),
               rules.count <= maximumCount, Set(rules.map(\.id)).count == rules.count,
               rules.allSatisfy({ $0.validationMessage == nil }) { return .init(rules: rules, error: nil) }
            return .init(rules: legacy(defaults), error: String(localized: "İstisna kuralları okunamadı. Kayıt korundu; önceki basit istisnalar kullanılıyor."))
        }
        return .init(rules: legacy(defaults), error: nil)
    }
    /// Called only on an explicit edit; reading preferences never migrates or rewrites them.
    @discardableResult public static func save(_ rules: [SwitcherExceptionRule], _ defaults: UserDefaults = .standard) -> Bool {
        guard rules.count <= maximumCount, Set(rules.map(\.id)).count == rules.count,
              rules.allSatisfy({ $0.validationMessage == nil }), let data = try? JSONEncoder().encode(rules) else { return false }
        defaults.set(data, forKey: key)
        // Retain the old exact-match subset for older MacPocket builds; never widen to a prefix.
        defaults.set(rules.filter { $0.enabled && $0.target == .applicationPath && $0.visibility == .alwaysHide }.map(\.value).sorted().joined(separator: "\n"), forKey: "switcher.excludedPaths")
        defaults.set(rules.filter { $0.enabled && $0.target == .bundleIdentifier && $0.shortcuts == .alwaysDisable }.map(\.value).sorted().joined(separator: "\n"), forKey: "switcher.disabledApps")
        return true
    }
    private static func legacy(_ defaults: UserDefaults) -> [SwitcherExceptionRule] {
        func entries(_ key: String) -> [String] { Array(Set((defaults.string(forKey: key) ?? "").split(separator: "\n").map(String.init))).sorted() }
        return entries("switcher.excludedPaths").map { .init(id: "legacy-path:" + $0, target: .applicationPath, value: $0, visibility: .alwaysHide) }
            + entries("switcher.disabledApps").map { .init(id: "legacy-bundle:" + $0, target: .bundleIdentifier, value: $0, shortcuts: .alwaysDisable) }
    }
}
