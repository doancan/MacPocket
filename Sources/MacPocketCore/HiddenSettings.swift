import Foundation

// MARK: - Catalog model

/// Preference domains MacPocket may write. Nothing outside this list can be targeted.
public enum HiddenSettingDomain: String, CaseIterable, Sendable {
    case dock = "com.apple.dock"
    case finder = "com.apple.finder"
    case screenCapture = "com.apple.screencapture"
    case global = "NSGlobalDomain"
    case desktopServices = "com.apple.desktopservices"
    case timeMachine = "com.apple.TimeMachine"

    /// The domain argument as `defaults` takes it.
    public var commandName: String { self == .global ? "-g" : rawValue }
}

/// System processes MacPocket restarts so a change takes effect; launchd starts them again.
public enum HiddenSettingRestart: String, CaseIterable, Sendable {
    case dock = "Dock"
    case finder = "Finder"
    case systemUIServer = "SystemUIServer"

    public var title: String {
        switch self {
        case .dock: "Dock"
        case .finder: "Finder"
        case .systemUIServer: String(localized: "Sistem arayüzü")
        }
    }
}

/// When a written value starts to apply.
public enum HiddenSettingEffect: Equatable, Sendable {
    /// MacPocket restarts the owning process after applying.
    case restarts(HiddenSettingRestart)
    /// Each app reads it when it is next opened.
    case reopenApps
    /// Read at login.
    case nextLogin
    /// Read on every use.
    case immediate

    public var title: String {
        switch self {
        case let .restarts(target): String(localized: "\(target.title) yeniden başlatılınca")
        case .reopenApps: String(localized: "Uygulamalar yeniden açılınca")
        case .nextLogin: String(localized: "Oturum yeniden açılınca")
        case .immediate: String(localized: "Hemen")
        }
    }
}

public struct HiddenSettingOption: Equatable, Sendable, Identifiable {
    public let value: String
    public let title: String
    public var id: String { value }

    public init(_ value: String, _ title: String) { self.value = value; self.title = title }
}

public enum HiddenSettingKind: Equatable, Sendable {
    case toggle(systemDefault: Bool)
    case seconds(range: ClosedRange<Double>, step: Double, systemDefault: Double)
    case choice(options: [HiddenSettingOption], systemDefault: String)
}

public enum HiddenSettingValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case text(String)
}

public enum HiddenSettingGroup: String, CaseIterable, Identifiable, Sendable {
    case dock, finder, screenshots, windows, files
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dock: "Dock"
        case .finder: "Finder"
        case .screenshots: String(localized: "Ekran Görüntüleri")
        case .windows: String(localized: "Pencereler ve Klavye")
        case .files: String(localized: "Dosyalar ve Yedekleme")
        }
    }

    public var symbol: String {
        switch self {
        case .dock: "dock.rectangle"
        case .finder: "folder"
        case .screenshots: "camera.viewfinder"
        case .windows: "macwindow"
        case .files: "externaldrive"
        }
    }
}

/// A macOS preference with no control in System Settings: normally changed with `defaults write` in Terminal.
public struct HiddenSetting: Identifiable, Equatable, Sendable {
    public let id: String
    public let group: HiddenSettingGroup
    public let domain: HiddenSettingDomain
    public let key: String
    public let kind: HiddenSettingKind
    public let effect: HiddenSettingEffect
    public let title: String
    public let detail: String

    public var systemDefault: HiddenSettingValue {
        switch kind {
        case let .toggle(value): .bool(value)
        case let .seconds(_, _, value): .number(value)
        case let .choice(_, value): .text(value)
        }
    }

    public func accepts(_ value: HiddenSettingValue) -> Bool {
        switch (kind, value) {
        case (.toggle, .bool): true
        case let (.seconds(range, _, _), .number(number)): number.isFinite && range.contains(number)
        case let (.choice(options, _), .text(text)): options.contains { $0.value == text }
        default: false
        }
    }

    /// Interprets what `defaults` stored. Values written by hand (`-string YES`, `-int 1`) are accepted;
    /// anything that doesn't fit the kind returns nil.
    public func decode(_ raw: Any?) -> HiddenSettingValue? {
        guard let raw else { return nil }
        switch kind {
        case .toggle:
            if let number = raw as? NSNumber { return .bool(number.boolValue) }
            switch (raw as? String)?.lowercased() {
            case "1", "yes", "true": return .bool(true)
            case "0", "no", "false": return .bool(false)
            default: return nil
            }
        case .seconds:
            let number = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
            return number.flatMap { $0.isFinite ? .number($0) : nil }
        case let .choice(options, _):
            guard let text = (raw as? String)?.lowercased(), options.contains(where: { $0.value == text }) else { return nil }
            return .text(text)
        }
    }

    // MARK: Terminal equivalents

    /// The exact Terminal command that writes `value`, e.g. `defaults write com.apple.dock autohide-delay -float 0`.
    public func writeCommand(_ value: HiddenSettingValue) -> String {
        "defaults write \(domain.commandName) \(key) " + Self.typedArgument(value).joined(separator: " ")
    }

    public var deleteCommand: String { "defaults delete \(domain.commandName) \(key)" }

    public var restartCommand: String? {
        if case let .restarts(target) = effect { return "killall \(target.rawValue)" }
        return nil
    }

    static func typedArgument(_ value: HiddenSettingValue) -> [String] {
        switch value {
        case let .bool(flag): ["-bool", flag ? "true" : "false"]
        case let .number(number): ["-float", formatNumber(number)]
        case let .text(text): ["-string", text]
        }
    }

    /// POSIX formatting ("0.15", "0"), independent of the app language.
    static func formatNumber(_ number: Double) -> String {
        let rounded = (number * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}

// MARK: - Catalog

extension HiddenSetting {
    /// Settings verified to have no control in System Settings on macOS 14–27.
    public static let catalog: [HiddenSetting] = [
        // Dock
        HiddenSetting(id: "dock.autohide-delay", group: .dock, domain: .dock, key: "autohide-delay",
                      kind: .seconds(range: 0...2, step: 0.05, systemDefault: 0.5), effect: .restarts(.dock),
                      title: String(localized: "Gizlenen Dock’un görünme gecikmesi"),
                      detail: String(localized: "İmleç ekran kenarına geldikten sonra otomatik gizlenen Dock’un belirmesi için beklenen süre. 0: anında.")),
        HiddenSetting(id: "dock.autohide-time-modifier", group: .dock, domain: .dock, key: "autohide-time-modifier",
                      kind: .seconds(range: 0...2, step: 0.05, systemDefault: 0.5), effect: .restarts(.dock),
                      title: String(localized: "Dock gizlenme animasyonu süresi"),
                      detail: String(localized: "Dock’un kayarak açılıp kapanma animasyonunun süresi. 0: animasyonsuz.")),
        HiddenSetting(id: "dock.showhidden", group: .dock, domain: .dock, key: "showhidden",
                      kind: .toggle(systemDefault: false), effect: .restarts(.dock),
                      title: String(localized: "Gizlenen uygulamaları soluk göster"),
                      detail: String(localized: "⌘H ile gizlenen uygulamaların Dock simgeleri yarı saydam görünür.")),
        HiddenSetting(id: "dock.static-only", group: .dock, domain: .dock, key: "static-only",
                      kind: .toggle(systemDefault: false), effect: .restarts(.dock),
                      title: String(localized: "Yalnız açık uygulamaları göster"),
                      detail: String(localized: "Dock’ta sabitlenmiş ama çalışmayan uygulamalar gizlenir.")),
        HiddenSetting(id: "dock.scroll-to-open", group: .dock, domain: .dock, key: "scroll-to-open",
                      kind: .toggle(systemDefault: false), effect: .restarts(.dock),
                      title: String(localized: "Simge üzerinde kaydırınca pencereleri göster"),
                      detail: String(localized: "Dock simgesinin üzerinde yukarı kaydırmak o uygulamanın pencerelerini açar.")),
        // Finder
        HiddenSetting(id: "finder.AppleShowAllFiles", group: .finder, domain: .finder, key: "AppleShowAllFiles",
                      kind: .toggle(systemDefault: false), effect: .restarts(.finder),
                      title: String(localized: "Gizli dosyaları her zaman göster"),
                      detail: String(localized: "Nokta ile başlayan dosyalar ve sistem klasörleri tüm Finder pencerelerinde görünür (⇧⌘. kısayolunun kalıcı hâli).")),
        HiddenSetting(id: "finder._FXShowPosixPathInTitle", group: .finder, domain: .finder, key: "_FXShowPosixPathInTitle",
                      kind: .toggle(systemDefault: false), effect: .restarts(.finder),
                      title: String(localized: "Pencere başlığında tam yolu göster"),
                      detail: String(localized: "Finder pencere başlığı klasör adı yerine /Users/… biçiminde tam yolu gösterir.")),
        HiddenSetting(id: "finder.QuitMenuItem", group: .finder, domain: .finder, key: "QuitMenuItem",
                      kind: .toggle(systemDefault: false), effect: .restarts(.finder),
                      title: String(localized: "Finder’dan Çık menüsü"),
                      detail: String(localized: "Finder menüsüne Çık (⌘Q) eklenir; çıkınca masaüstü simgeleri de gizlenir.")),
        HiddenSetting(id: "finder.DisableAllAnimations", group: .finder, domain: .finder, key: "DisableAllAnimations",
                      kind: .toggle(systemDefault: false), effect: .restarts(.finder),
                      title: String(localized: "Finder animasyonlarını kapat"),
                      detail: String(localized: "Bilgi Al penceresi ve klasör açma gibi Finder animasyonları atlanır.")),
        // Screenshots
        HiddenSetting(id: "screencapture.type", group: .screenshots, domain: .screenCapture, key: "type",
                      kind: .choice(options: [HiddenSettingOption("png", "PNG"), HiddenSettingOption("jpg", "JPEG"),
                                              HiddenSettingOption("heic", "HEIC"), HiddenSettingOption("tiff", "TIFF"),
                                              HiddenSettingOption("pdf", "PDF")], systemDefault: "png"),
                      effect: .restarts(.systemUIServer),
                      title: String(localized: "Dosya biçimi"),
                      detail: String(localized: "⇧⌘3, ⇧⌘4 ve ⇧⌘5 ile alınan ekran görüntülerinin biçimi. JPEG ve HEIC daha küçük dosya üretir.")),
        HiddenSetting(id: "screencapture.disable-shadow", group: .screenshots, domain: .screenCapture, key: "disable-shadow",
                      kind: .toggle(systemDefault: false), effect: .restarts(.systemUIServer),
                      title: String(localized: "Pencere görüntülerinde gölgeyi kaldır"),
                      detail: String(localized: "Tek pencere yakalarken (⇧⌘4, ardından Boşluk) çevresindeki gölge ve saydam kenar eklenmez.")),
        HiddenSetting(id: "screencapture.include-date", group: .screenshots, domain: .screenCapture, key: "include-date",
                      kind: .toggle(systemDefault: true), effect: .restarts(.systemUIServer),
                      title: String(localized: "Dosya adında tarih ve saat"),
                      detail: String(localized: "Kapatınca dosyalar “Ekran Resmi 1”, “Ekran Resmi 2” gibi sıra numarasıyla adlandırılır.")),
        // Windows and keyboard
        HiddenSetting(id: "global.NSWindowResizeTime", group: .windows, domain: .global, key: "NSWindowResizeTime",
                      kind: .seconds(range: 0.001...1, step: 0.01, systemDefault: 0.2), effect: .reopenApps,
                      title: String(localized: "Sayfa ve pencere animasyonu süresi"),
                      detail: String(localized: "Kaydet panelleri gibi açılır sayfaların ve pencere yeniden boyutlandırma animasyonlarının süresi.")),
        HiddenSetting(id: "global.NSAutomaticWindowAnimationsEnabled", group: .windows, domain: .global,
                      key: "NSAutomaticWindowAnimationsEnabled", kind: .toggle(systemDefault: true), effect: .reopenApps,
                      title: String(localized: "Yeni pencere açılış animasyonu"),
                      detail: String(localized: "Kapatınca yeni pencereler büyüyerek değil, doğrudan açılır.")),
        HiddenSetting(id: "global.ApplePressAndHoldEnabled", group: .windows, domain: .global, key: "ApplePressAndHoldEnabled",
                      kind: .toggle(systemDefault: true), effect: .reopenApps,
                      title: String(localized: "Basılı tutunca aksanlı harf menüsü"),
                      detail: String(localized: "Kapatınca bir tuşa basılı tutmak harf seçenekleri yerine tuşu tekrarlar (kod yazarken ve oyunlarda kullanışlı).")),
        HiddenSetting(id: "global.NSDocumentSaveNewDocumentsToCloud", group: .windows, domain: .global,
                      key: "NSDocumentSaveNewDocumentsToCloud", kind: .toggle(systemDefault: true), effect: .reopenApps,
                      title: String(localized: "Yeni belgeleri önce iCloud’a kaydet"),
                      detail: String(localized: "Kapatınca Kaydet paneli iCloud Drive yerine bu Mac’teki bir konumla açılır.")),
        // Files and backup
        HiddenSetting(id: "desktopservices.DSDontWriteNetworkStores", group: .files, domain: .desktopServices,
                      key: "DSDontWriteNetworkStores", kind: .toggle(systemDefault: false), effect: .nextLogin,
                      title: String(localized: "Ağ sürücülerine .DS_Store yazma"),
                      detail: String(localized: "Finder, SMB ve diğer ağ paylaşımlarında görünüm bilgisini tutan .DS_Store dosyaları oluşturmaz.")),
        HiddenSetting(id: "desktopservices.DSDontWriteUSBStores", group: .files, domain: .desktopServices,
                      key: "DSDontWriteUSBStores", kind: .toggle(systemDefault: false), effect: .nextLogin,
                      title: String(localized: "USB sürücülere .DS_Store yazma"),
                      detail: String(localized: "Başka bilgisayarlarla paylaşılan USB disklerde .DS_Store dosyaları oluşmaz.")),
        HiddenSetting(id: "timemachine.DoNotOfferNewDisksForBackup", group: .files, domain: .timeMachine,
                      key: "DoNotOfferNewDisksForBackup", kind: .toggle(systemDefault: false), effect: .immediate,
                      title: String(localized: "Yeni disklerde Time Machine sorma"),
                      detail: String(localized: "Bir disk takıldığında “Time Machine ile yedeklemek için kullanılsın mı?” sorusu çıkmaz.")),
    ]

    public static func setting(id: String) -> HiddenSetting? { catalog.first { $0.id == id } }
}

// MARK: - Storage

/// Where hidden settings live. The system implementation is CFPreferences for the current user on any
/// host, the same store `defaults write` uses; tests substitute an in-memory one.
public protocol HiddenSettingsStore: Sendable {
    func read(_ key: String, domain: HiddenSettingDomain) -> Any?
    /// nil removes the key (`defaults delete`). Returns false when the change could not be saved.
    func write(_ value: HiddenSettingValue?, key: String, domain: HiddenSettingDomain) -> Bool
}

public struct SystemHiddenSettingsStore: HiddenSettingsStore {
    public init() {}

    private func application(_ domain: HiddenSettingDomain) -> CFString {
        domain == .global ? kCFPreferencesAnyApplication : domain.rawValue as CFString
    }

    public func read(_ key: String, domain: HiddenSettingDomain) -> Any? {
        CFPreferencesCopyValue(key as CFString, application(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    public func write(_ value: HiddenSettingValue?, key: String, domain: HiddenSettingDomain) -> Bool {
        let property: CFPropertyList? = switch value {
        case let .bool(flag)?: flag as CFBoolean
        case let .number(number)?: number as CFNumber
        case let .text(text)?: text as CFString
        case nil: nil
        }
        let app = application(domain)
        CFPreferencesSetValue(key as CFString, property, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

// MARK: - Restarting

public protocol HiddenSettingsRestarting: Sendable {
    func restart(_ target: HiddenSettingRestart) async throws
}

public enum HiddenSettingsError: Error, LocalizedError, Equatable, Sendable {
    case unknownSetting(String)
    case invalidValue(String)
    case restartFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownSetting(id): String(localized: "Bilinmeyen gizli ayar: \(id).")
        case let .invalidValue(id): String(localized: "“\(id)” için geçersiz değer.")
        case let .restartFailed(name): String(localized: "\(name) yeniden başlatılamadı.")
        }
    }
}

/// `/usr/bin/killall <name>` with the name taken from `HiddenSettingRestart`; launchd starts the process again.
/// Exit status 1 means the process wasn't running, so there is nothing to restart.
public struct KillallRestarter: HiddenSettingsRestarting {
    public init() {}

    public func restart(_ target: HiddenSettingRestart) async throws {
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [target.rawValue]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 || status == 1 else { throw HiddenSettingsError.restartFailed(target.title) }
    }
}

// MARK: - Service

public struct HiddenSettingState: Equatable, Sendable {
    /// The value in effect: the stored one, or the macOS default when nothing is stored.
    public let value: HiddenSettingValue
    /// A value is stored (by MacPocket, Terminal or another tool).
    public let isCustomized: Bool
    /// Something is stored that MacPocket can't interpret; `value` is then the macOS default.
    public let isUnrecognized: Bool

    public init(value: HiddenSettingValue, isCustomized: Bool, isUnrecognized: Bool) {
        self.value = value; self.isCustomized = isCustomized; self.isUnrecognized = isUnrecognized
    }
}

public enum HiddenSettingChange: Equatable, Sendable {
    case set(id: String, value: HiddenSettingValue)
    /// Back to the macOS default (`defaults delete`).
    case reset(id: String)

    public var id: String {
        switch self {
        case let .set(id, _), let .reset(id): id
        }
    }
}

public struct HiddenSettingsApplyReport: Equatable, Sendable {
    public var written: [String] = []
    public var failed: [String] = []
    public var restarted: [HiddenSettingRestart] = []
    public var restartFailures: [HiddenSettingRestart] = []
}

public struct HiddenSettingsService: Sendable {
    private let store: any HiddenSettingsStore
    private let restarter: any HiddenSettingsRestarting

    public init(store: any HiddenSettingsStore = SystemHiddenSettingsStore(),
                restarter: any HiddenSettingsRestarting = KillallRestarter()) {
        self.store = store; self.restarter = restarter
    }

    public func state(of setting: HiddenSetting) -> HiddenSettingState {
        let raw = store.read(setting.key, domain: setting.domain)
        let decoded = setting.decode(raw)
        return HiddenSettingState(value: decoded ?? setting.systemDefault, isCustomized: raw != nil,
                                  isUnrecognized: raw != nil && decoded == nil)
    }

    /// Validates every change before writing any, writes them, then restarts each affected process once.
    public func apply(_ changes: [HiddenSettingChange]) async throws -> HiddenSettingsApplyReport {
        let resolved = try changes.map { change -> (HiddenSetting, HiddenSettingValue?) in
            guard let setting = HiddenSetting.setting(id: change.id) else { throw HiddenSettingsError.unknownSetting(change.id) }
            switch change {
            case let .set(_, value):
                guard setting.accepts(value) else { throw HiddenSettingsError.invalidValue(change.id) }
                return (setting, value)
            case .reset:
                return (setting, nil)
            }
        }
        var report = HiddenSettingsApplyReport()
        var targets: [HiddenSettingRestart] = []
        for (setting, value) in resolved {
            if store.write(value, key: setting.key, domain: setting.domain) {
                report.written.append(setting.id)
                if case let .restarts(target) = setting.effect, !targets.contains(target) { targets.append(target) }
            } else {
                report.failed.append(setting.id)
            }
        }
        for target in HiddenSettingRestart.allCases where targets.contains(target) {
            do {
                try await restarter.restart(target)
                report.restarted.append(target)
            } catch {
                report.restartFailures.append(target)
            }
        }
        return report
    }
}
