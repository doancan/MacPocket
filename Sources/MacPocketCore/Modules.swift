import Foundation

/// Availability is independent of a tool's own settings. Turning a module off preserves those settings.
public enum PocketModule: String, CaseIterable, Identifiable, Sendable {
    case menuBarOrganizer
    case windowSwitcher, windowLayout, clipboard, quitGuard, displays, freezer
    case mouseButtons
    case screenGrab, screenshot, bluetoothBattery, mouseScroll, audioOutput, mixer, recorder, commandBar, shelf, dockPreview

    public var id: String { rawValue }
    public var availabilityKey: String { "MacPocket.modules.\(rawValue).available" }

    public func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        // Existing installations retain every tool; missing/corrupt values never silently disable one.
        defaults.object(forKey: availabilityKey) as? Bool ?? true
    }

    public var localizedTitle: String {
        switch self {
        case .windowSwitcher: String(localized: "Pencere Geçişi")
        case .windowLayout: String(localized: "Pencere Yerleşimi")
        case .clipboard: String(localized: "Pano Geçmişi")
        case .quitGuard: String(localized: "Kapatma Koruması")
        case .displays: String(localized: "Ekran ve Gece Modu")
        case .freezer: String(localized: "Uygulama Dondurucu")
        case .screenGrab: String(localized: "Ekrandan Al")
        case .screenshot: String(localized: "Ekran Görüntüsü")
        case .bluetoothBattery: String(localized: "Bluetooth Pilleri")
        case .mouseScroll: String(localized: "Fare Kaydırma")
        case .mouseButtons: String(localized: "Fare Tuşları")
        case .audioOutput: String(localized: "Ses Çıkışı")
        case .mixer: String(localized: "Ses Mikseri")
        case .recorder: String(localized: "Ekran Kaydı")
        case .commandBar: String(localized: "Komut Çubuğu")
        case .shelf: String(localized: "Dosya Rafı")
        case .dockPreview: String(localized: "Dock Önizlemeleri")
        case .menuBarOrganizer: String(localized: "Menü Çubuğu Düzenleyici")
        }
    }
}

/// Lazy, idempotent service ownership. Binding closures must not capture already-created services.
/// A rejected stop leaves both the running service and its saved availability intact.
@MainActor
public final class ModuleLifecycle {
    public struct Binding {
        public var start: () -> Void
        public var stop: () -> Void
        public var canStop: () -> Bool

        public init(start: @escaping () -> Void, stop: @escaping () -> Void, canStop: @escaping () -> Bool = { true }) {
            self.start = start
            self.stop = stop
            self.canStop = canStop
        }
    }

    public private(set) var running: Set<PocketModule> = []
    private let bindings: [PocketModule: Binding]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, bindings: [PocketModule: Binding]) {
        self.defaults = defaults
        self.bindings = bindings
    }

    /// Also reconciles preference import/reset. Does not instantiate disabled, never-started services.
    @discardableResult
    public func reconcile() -> Set<PocketModule> {
        var rejected: Set<PocketModule> = []
        for module in PocketModule.allCases {
            guard let binding = bindings[module] else { continue }
            if module.isAvailable(in: defaults) {
                if running.insert(module).inserted { binding.start() }
            } else if running.contains(module) {
                guard binding.canStop() else {
                    defaults.set(true, forKey: module.availabilityKey)
                    rejected.insert(module)
                    continue
                }
                running.remove(module)
                binding.stop()
            }
        }
        return rejected
    }

    @discardableResult
    public func setAvailable(_ module: PocketModule, _ available: Bool) -> Bool {
        if !available, running.contains(module), let binding = bindings[module], !binding.canStop() { return false }
        defaults.set(available, forKey: module.availabilityKey)
        return !reconcile().contains(module)
    }

    /// Quit only touches services which were started, in reverse start order.
    public func stopAll() {
        for module in PocketModule.allCases.reversed() where running.remove(module) != nil {
            bindings[module]?.stop()
        }
    }
}
