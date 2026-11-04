import AppKit
import MacPocketCore
import SwiftUI

/// UserDefaults keys for app-level preferences that several files read.
enum PocketPreferenceKey {
    static let showInDock = "MacPocket.showInDock"
    static let launchPage = "MacPocket.launchPage"
    static let showWindowAtLaunch = "MacPocket.showWindowAtLaunch"
    static let confirmQuitWhileAwake = "MacPocket.confirmQuitWhileAwake"
    static let accentStyle = "MacPocket.accentStyle"
    static let sidebarIcons = "MacPocket.sidebarIcons"
    static let reduceMotion = "MacPocket.reduceMotion"
    static let density = "MacPocket.density"
}

// MARK: - Language

extension AppLanguage {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .system: "Sistem"
        // Language names stay in their own language so they are recognisable from either UI.
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }

    /// The choice stored for this app (not the language it is currently running in).
    static var stored: AppLanguage {
        AppLanguage.load(from: .standard, domain: PocketDefaults.domain)
    }

    /// The localization the running process resolved at launch.
    static var running: String { Bundle.main.preferredLocalizations.first ?? "tr" }
}

/// Relaunch after a language change: the new instance is started only once termination is certain.
enum PocketDefaults {
    /// The app's own preferences domain (the executable name when run outside the app bundle).
    static var domain: String { Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName }
    static let languageConfiguredKey = "MacPocket.languageConfigured"

    /// MacPocket was Turkish-only before English was added. Until the user picks a language, keep Turkish
    /// instead of silently following an English system; an explicit "Sistem" choice is respected afterwards.
    static func applyLanguageDefault(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: languageConfiguredKey) == nil else { return }
        if AppLanguage.load(from: defaults, domain: domain) == .system { AppLanguage.turkish.save(to: defaults) }
        defaults.set(true, forKey: languageConfiguredKey)
    }
}

@MainActor
enum PocketRelaunch {
    private(set) static var pending = false
    /// Read once at launch (see the app delegate), so Settings can tell when a relaunch is needed.
    static let languageAtLaunch = AppLanguage.stored

    static func relaunch() {
        pending = true
        NSApp.terminate(nil)
        // If termination was cancelled (an operation is running, or the user kept the app open), stay put.
        DispatchQueue.main.async { pending = false }
    }

    /// Called from `applicationWillTerminate`.
    static func spawnIfPending() {
        guard pending else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The short delay lets this instance exit first, so `open` starts a fresh process instead of activating us.
        process.arguments = ["-c", "sleep 0.7; /usr/bin/open -n \"$0\"", Bundle.main.bundleURL.path]
        try? process.run()
    }
}

// MARK: - Appearance

enum PocketAccentStyle: String, CaseIterable, Identifiable {
    case brand, system
    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey { self == .brand ? "MacPocket mavisi" : "Sistem vurgu rengi" }
    static var current: PocketAccentStyle {
        PocketAccentStyle(rawValue: UserDefaults.standard.string(forKey: PocketPreferenceKey.accentStyle) ?? "") ?? .brand
    }
}

enum PocketSidebarIconStyle: String, CaseIterable, Identifiable {
    case colorful, monochrome
    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey { self == .colorful ? "Renkli kareler" : "Tek renk" }
}

enum PocketDensity: String, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey { self == .comfortable ? "Rahat" : "Sıkı" }
    var scale: CGFloat { self == .comfortable ? 1 : 0.75 }
    static var current: PocketDensity {
        PocketDensity(rawValue: UserDefaults.standard.string(forKey: PocketPreferenceKey.density) ?? "") ?? .comfortable
    }
}

/// Re-creates window content when a static design token (accent, density) changes, and applies the
/// app language's locale to formatted text.
struct PocketAppearanceRoot: ViewModifier {
    /// Off for Settings, where a rebuild would reset the selected tab while the user is changing these options.
    var rebuildsOnTokenChange = true
    @AppStorage("MacPocket.appearance") private var appearance = PocketAppearance.defaultValue
    @AppStorage(PocketPreferenceKey.accentStyle) private var accent = PocketAccentStyle.brand
    @AppStorage(PocketPreferenceKey.density) private var density = PocketDensity.comfortable

    func body(content: Content) -> some View {
        content
            .id(rebuildsOnTokenChange ? "\(accent.rawValue)/\(density.rawValue)" : "")
            .preferredColorScheme(appearance.colorScheme)
            .tint(PocketTheme.accent)
            .environment(\.locale, pocketLocale)
    }
}

extension View {
    func pocketAppearanceRoot(rebuildsOnTokenChange: Bool = true) -> some View {
        modifier(PocketAppearanceRoot(rebuildsOnTokenChange: rebuildsOnTokenChange))
    }
}

/// System Reduce Motion, or the app's own override in Settings → Appearance.
@propertyWrapper
struct PocketReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage(PocketPreferenceKey.reduceMotion) private var override = false
    var wrappedValue: Bool { system || override }
    init() {}

    /// For AppKit code outside a view.
    static var isEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || UserDefaults.standard.bool(forKey: PocketPreferenceKey.reduceMotion)
    }
}

// MARK: - Enum titles

extension PocketPage {
    var localizedTitle: String {
        switch self {
        case .overview: String(localized: "Genel Bakış")
        case .performance: String(localized: "Sistem İzleme")
        case .power: String(localized: "Güç Merkezi")
        case .cleanup: String(localized: "Temizlik")
        case .storage: String(localized: "Disk Analizi")
        case .applications: String(localized: "Uygulamalar")
        case .tools: String(localized: "Araçlar")
        }
    }

    static var launchPage: PocketPage {
        UserDefaults.standard.string(forKey: PocketPreferenceKey.launchPage).flatMap(PocketPage.init(rawValue:)) ?? .overview
    }
}

extension PocketTool {
    var localizedTitle: String {
        switch self {
        case .similarImages: String(localized: "Benzer Görseller")
        case .screenCleaning: String(localized: "Ekran Temizleme")
        case .utilities: String(localized: "macOS Araçları")
        case .leftovers: String(localized: "Uygulama Kalıntıları")
        case .taskManager: String(localized: "Görev Yöneticisi")
        case .diagnostics: String(localized: "Sistem Raporları")
        case .windowSwitcher: String(localized: "Pencere Geçişi")
        case .hiddenSettings: String(localized: "Gizli Ayarlar")
        case .clipboard: String(localized: "Pano Geçmişi")
        case .windowLayout: String(localized: "Pencere Yerleşimi")
        case .speedTest: String(localized: "Ağ Hız Testi")
        case .ports: String(localized: "Port Yöneticisi")
        case .quickActions: String(localized: "Hızlı İşlemler")
        case .quitGuard: String(localized: "Kapatma Koruması")
        case .brightness: String(localized: "Ekran Parlaklığı")
        case .macros: String(localized: "Makrolar")
        case .freezer: String(localized: "Uygulama Dondurucu")
        case .supportReport: String(localized: "Destek Raporu")
        case .focus: String(localized: "Odak Oturumu")
        case .workspaces: String(localized: "Masa Düzenleri")
        case .snippets: String(localized: "Metin Kısaltmaları")
        case .screenGrab: String(localized: "Ekrandan Al")
        case .mouseScroll: String(localized: "Fare Kaydırma")
        case .audio: String(localized: "Ses Çıkışı")
        case .mixer: String(localized: "Ses Mikseri")
        case .recorder: String(localized: "Ekran Kaydı")
        case .screenshot: String(localized: "Ekran Görüntüsü")
        case .bluetoothBattery: String(localized: "Bluetooth Pilleri")
        case .displays: String(localized: "Ekran Ayarları")
        case .networkTraffic: String(localized: "Ağ Trafiği")
        case .peripherals: String(localized: "USB ve Thunderbolt")
        case .usbEject: String(localized: "USB Çıkarma Yöneticisi")
        case .diskHealth: String(localized: "Disk Sağlığı")
        case .wifi: String(localized: "Wi-Fi Analizi")
        case .hosts: String(localized: "Hosts Dosyası")
        case .screenTime: String(localized: "Ekran Süresi")
        case .localNetwork: String(localized: "Yerel Ağ")
        case .powerSchedule: String(localized: "Güç Zamanlaması")
        case .privacy: String(localized: "Gizlilik Kontrolü")
        case .startupItems: String(localized: "Başlangıç Öğeleri")
        case .maintenance: String(localized: "Bakım")
        }
    }
}

extension PocketAppearance {
    var localizedTitle: String {
        switch self {
        case .system: String(localized: "Sistemle aynı")
        // "Açık" alone is the on/off state; the appearance needs its own key.
        case .light: String(localized: "Appearance.light", defaultValue: "Açık")
        case .dark: String(localized: "Koyu")
        }
    }
}

// MARK: - Dock and launch

@MainActor
enum PocketDock {
    /// Hiding the Dock icon needs another way back into the app, so it only applies while the menu bar item is shown.
    static var showsIcon: Bool {
        let wanted = UserDefaults.standard.object(forKey: PocketPreferenceKey.showInDock) as? Bool ?? true
        return wanted || !MenuBarPreferences.load().visible
    }

    static func apply() {
        let policy: NSApplication.ActivationPolicy = showsIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Changing the policy deactivates the app; keep the window the user is working in in front.
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}

@MainActor
enum PocketLaunch {
    static var showsWindow: Bool { UserDefaults.standard.object(forKey: PocketPreferenceKey.showWindowAtLaunch) as? Bool ?? true }
    /// The main window is created by SwiftUI at launch; when hidden at launch it is closed on first appearance.
    static var handledFirstWindow = false
    /// Set once termination is approved (also when macOS quits the app to apply a permission), so windows closing
    /// during shutdown aren't mistaken for the user closing them.
    static var terminating = false
}
