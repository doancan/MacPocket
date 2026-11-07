import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class PocketModuleRuntime: ObservableObject {
    static let shared = PocketModuleRuntime()
    @Published private(set) var available = Set(PocketModule.allCases.filter { $0.isAvailable() })
    @Published private(set) var message: String?
    private var lifecycle: ModuleLifecycle?
    private var observer: NSObjectProtocol?
    private var shuttingDown = false

    private init() {}

    func start(model: PocketModel) {
        guard lifecycle == nil else { return }
        AppFreezerService.recoverAfterCrash()
        FocusSessionService.recoverAfterCrash()
        NightModeService.recoverAfterCrashIfDisabled()
        // Closures defer all singleton access until the module is actually started.
        lifecycle = ModuleLifecycle(bindings: [
            .windowSwitcher: .init(start: { WindowSwitcherHotkeyController.shared.start() }, stop: { WindowSwitcherHotkeyController.shared.stopForModule() }),
            .windowLayout: .init(start: { WindowLayoutService.shared.start() }, stop: { WindowLayoutService.shared.stopForModule() }),
            .clipboard: .init(start: { ClipboardService.shared.start() }, stop: { ClipboardService.shared.stopForModule() }),
            .quitGuard: .init(start: { QuitGuardService.shared.start() }, stop: { QuitGuardService.shared.stopForModule() }, canStop: { [weak self] in self?.focusAllowsStop == true }),
            .displays: .init(start: {
                DisplayBrightnessService.shared.start()
                NightModeService.shared.start()
                DisplaySettingsService.shared.start()
            }, stop: {
                DisplaySettingsService.shared.stopForModule()
                NightModeService.shared.stopForModule()
                DisplayBrightnessService.shared.stopForModule()
            }, canStop: { [weak self] in self?.focusAllowsStop == true }),
            .macros: .init(start: { MacroService.shared.start() }, stop: { MacroService.shared.stopForModule() }, canStop: { [weak self] in self?.focusAllowsStop == true }),
            .freezer: .init(start: { AppFreezerService.shared.start() }, stop: { AppFreezerService.shared.stopForModule() }),
            .focus: .init(start: { [weak model] in if let model { FocusSessionService.shared.attach(model) } },
                          stop: { FocusSessionService.shared.stopForModule() }, canStop: { FocusSessionService.shared.canSuspendModule }),
            .workspaces: .init(start: { WorkspaceService.shared.start() }, stop: { WorkspaceService.shared.stopForModule() }, canStop: { WorkspaceService.shared.restoring == nil }),
            .snippets: .init(start: { SnippetService.shared.start() }, stop: { SnippetService.shared.stopForModule() }),
            .screenGrab: .init(start: { ScreenGrabService.shared.start() }, stop: { ScreenGrabService.shared.stopForModule() }, canStop: { !ScreenGrabService.shared.busy }),
            .screenshot: .init(start: { ScreenshotService.shared.start() }, stop: { ScreenshotService.shared.stopForModule() }, canStop: { ScreenshotService.shared.canSuspendModule }),
            .bluetoothBattery: .init(start: { BluetoothBatteryService.shared.start() }, stop: { BluetoothBatteryService.shared.stopForModule() }),
            .screenTime: .init(start: { ScreenTimeService.shared.start() }, stop: { ScreenTimeService.shared.stopForModule() }),
            .mouseButtons: .init(start: { MouseButtonService.shared.start() }, stop: { MouseButtonService.shared.stopForModule() }),
            .mouseScroll: .init(start: { MouseScrollService.shared.start() }, stop: { MouseScrollService.shared.stopForModule() }),
            .audioOutput: .init(start: {
                AudioOutputService.shared.start()
                MonitorVolumeService.shared.start()
            }, stop: {
                MonitorVolumeService.shared.stopForModule()
                AudioOutputService.shared.stopForModule()
            }),
            .mixer: .init(start: { VolumeMixerService.shared.start() }, stop: { VolumeMixerService.shared.stopForModule() }),
            .recorder: .init(start: { ScreenRecorderService.shared.start() }, stop: { ScreenRecorderService.shared.stopForModule() }, canStop: {
                let recorder = ScreenRecorderService.shared
                return !recorder.isRecording && !recorder.transitioning && !recorder.isSaving
            }),
            .privacy: .init(start: { PrivacyMonitorService.shared.start() }, stop: { PrivacyMonitorService.shared.stopForModule() }),
            .commandBar: .init(start: { [weak model] in if let model { CommandBarService.shared.start(model: model) } }, stop: { CommandBarService.shared.stopForModule() }),
            .shelf: .init(start: { ShelfService.shared.start() }, stop: { ShelfService.shared.stopForModule() }),
            .menuBarOrganizer: .init(start: { MenuBarOrganizerService.shared.start() }, stop: { MenuBarOrganizerService.shared.stopForModule() }),
            .dockPreview: .init(start: { DockPreviewService.shared.start() }, stop: { DockPreviewService.shared.stopForModule() })
        ])
        reconcile()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    private var focusAllowsStop: Bool {
        lifecycle?.running.contains(.focus) != true || FocusSessionService.shared.canSuspendModule
    }

    func setAvailable(_ module: PocketModule, _ enabled: Bool) {
        guard !shuttingDown else { return }
        if lifecycle?.setAvailable(module, enabled) == false {
            message = Self.busyMessage(module)
        } else {
            message = nil
        }
        refreshAvailability()
    }

    private func reconcile() {
        guard !shuttingDown else { return }
        if let rejected = lifecycle?.reconcile(), let module = PocketModule.allCases.first(where: rejected.contains) {
            message = Self.busyMessage(module)
        }
        refreshAvailability()
    }

    private func refreshAvailability() {
        let next = Set(PocketModule.allCases.filter { $0.isAvailable() })
        if available != next { available = next }
    }

    private static func busyMessage(_ module: PocketModule) -> String {
        switch module {
        case .focus, .quitGuard, .displays, .macros:
            String(localized: "Bu modülü kapatmadan önce etkin odak oturumunu bitir.")
        case .recorder:
            String(localized: "Ekran Kaydı modülünü kapatmadan önce kaydı durdur ve dosyanın kaydedilmesini bekle.")
        case .screenshot:
            String(localized: "Bu modülü kapatmadan önce çekimi bitir veya iptal et; düzenleyicideki değişiklikleri kaydet ve dışa aktarmanın bitmesini bekle.")
        default:
            String(localized: "Bu modülü kapatmadan önce devam eden işlemin bitmesini bekle.")
        }
    }

    func shutdown() {
        shuttingDown = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        lifecycle?.stopAll()
    }
}

extension PocketTool {
    var module: PocketModule? {
        switch self {
        case .windowSwitcher: .windowSwitcher
        case .windowLayout: .windowLayout
        case .clipboard: .clipboard
        case .quitGuard: .quitGuard
        case .brightness, .displays: .displays
        case .macros: .macros
        case .freezer: .freezer
        case .focus: .focus
        case .workspaces: .workspaces
        case .snippets: .snippets
        case .screenGrab: .screenGrab
        case .screenshot: .screenshot
        case .bluetoothBattery: .bluetoothBattery
        case .screenTime: .screenTime
        case .mouseScroll: .mouseScroll
        case .mouseButtons: .mouseButtons
        case .audio: .audioOutput
        case .mixer: .mixer
        case .recorder: .recorder
        case .privacy: .privacy
        case .commandBar: .commandBar
        case .shelf: .shelf
        case .dockPreview: .dockPreview
        case .menuBarOrganizer: .menuBarOrganizer
        default: nil
        }
    }
}

struct PocketModuleSettings: View {
    @ObservedObject private var runtime = PocketModuleRuntime.shared
    @State private var search = ""

    private var matching: [PocketModule] {
        PocketModule.allCases.filter { search.isEmpty || $0.localizedTitle.localizedStandardContains(search) }
    }

    var body: some View {
        Form {
            Section {
                Text("Kullanmadığın modülleri kapat. Kısayolları ve arka plan servisleri durur; ayarların ve geçmişin korunur.")
                    .foregroundStyle(.secondary)
                TextField("Modül ara…", text: $search)
                    .accessibilityLabel("Modül ara")
                if let message = runtime.message {
                    Label(message, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("modules.message")
                }
            } header: { Text("Modüller") }
            Section {
                ForEach(matching) { module in
                    Toggle(isOn: Binding(get: { runtime.available.contains(module) }, set: { runtime.setAvailable(module, $0) })) {
                        Text(module.localizedTitle)
                    }
                    .accessibilityLabel(Text(verbatim: module.localizedTitle))
                    .accessibilityIdentifier("module.\(module.rawValue)")
                }
                if matching.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            } footer: {
                Text("Bir modülü açmak, aracın kendi ayarlarında kapattığın seçenekleri açmaz. Ekran ve Gece Modu; parlaklık, gece rengi ve ekran ayarlarını birlikte yönetir.")
            }
        }
        .formStyle(.grouped)
    }
}

struct DisabledModuleView: View {
    let module: PocketModule
    @ObservedObject private var runtime = PocketModuleRuntime.shared

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "\(module.localizedTitle) kapalı"), systemImage: "pause.circle")
        } description: {
            Text("Bu modülün arka plan servisleri ve kısayolları durduruldu. Tekrar açtığında kayıtlı ayarlarınla devam edersin.")
        } actions: {
            Button("Modülü Aç") { runtime.setAvailable(module, true) }
                .buttonStyle(.borderedProminent)
        }
    }
}
