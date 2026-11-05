import AppKit
import KeyboardShortcuts
import Observation
import SSHConfigKit
import SwiftUI

public enum SSHSection: String, CaseIterable, Identifiable {
    case servers, keys, knownHosts, backups, settings
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .servers: String(localized: "Sunucular")
        case .keys: String(localized: "SSH Anahtarları")
        case .knownHosts: String(localized: "Bilinen Sunucular")
        case .backups: String(localized: "Yedekler")
        case .settings: String(localized: "SSH Ayarları")
        }
    }
    public var icon: String {
        switch self {
        case .servers: "server.rack"
        case .keys: "key.fill"
        case .knownHosts: "checkmark.shield"
        case .backups: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

private struct SSHNavigateKey: EnvironmentKey {
    static let defaultValue: @MainActor (SSHSection) -> Void = { _ in }
}
extension EnvironmentValues {
    var sshNavigate: @MainActor (SSHSection) -> Void {
        get { self[SSHNavigateKey.self] }
        set { self[SSHNavigateKey.self] = newValue }
    }
}

/// Owns SSH state for the lifetime of MacPocket, including while its window is closed.
@MainActor @Observable
public final class SSHRuntime {
    public static let shared = SSHRuntime()
    let model: AppModel
    public var section: SSHSection {
        didSet {
            navigationDefaults.set(section.rawValue, forKey: "MacPocket.ssh.section")
            updateCommandAvailability()
        }
    }
    @ObservationIgnored private let navigationDefaults: UserDefaults
    @ObservationIgnored private var openWorkspace: () -> Void = {}
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var panel: QuickConnectPanelController?
    @ObservationIgnored private var workspaceVisible = false
    @ObservationIgnored private(set) lazy var quickConnect = QuickConnectModel(app: model, openMainWindow: { [weak self] in self?.open(.servers) })

    private convenience init() {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--ssh-fixture"), arguments.indices.contains(index + 1) {
            let home = URL(fileURLWithPath: arguments[index + 1])
            let fixture = SSHRuntimeAudit.makeFixture(home: home)
            self.init(model: fixture.model, navigationDefaults: fixture.defaults)
            return
        }
        #endif
        let defaults = UserDefaults(suiteName: "com.doancan.MacPocket.SSH") ?? .standard
        let home = FileManager.default.homeDirectoryForCurrentUser
        let backups = home.appending(path: "Library/Application Support/MacPocket/SSH/Backups")
        var migrationError: (any Error)?
        do {
            try SSHStandaloneMigration.run(defaults: defaults,
                legacy: UserDefaults.standard.persistentDomain(forName: "tr.com.mess.SSHConfigManager") ?? [:],
                oldBackups: home.appending(path: "Library/Application Support/SSHConfigManager/Backups"),
                newBackups: backups, shortcutDefaults: .standard)
        } catch { migrationError = error }
        let model = AppModel(settings: AppSettings(defaults: defaults), backupRoot: backups)
        if let migrationError { model.errorMessage = Messages.text(for: migrationError) }
        self.init(model: model)
    }

    init(model: AppModel, navigationDefaults: UserDefaults = .standard) {
        self.model = model
        self.navigationDefaults = navigationDefaults
        section = navigationDefaults.string(forKey: "MacPocket.ssh.section").flatMap(SSHSection.init(rawValue:)) ?? .servers
    }

    public func start(openWorkspace: @escaping () -> Void) {
        self.openWorkspace = openWorkspace
        guard panel == nil else { return }
        panel = QuickConnectPanelController(model: quickConnect,
            openMainWindow: { [weak self] in self?.open(.servers) },
            openSettings: { [weak self] in self?.open(.settings) })
        KeyboardShortcuts.onKeyUp(for: .quickConnect) { [weak self] in
            MainActor.assumeIsolated { self?.panel?.toggle() }
        }
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let becameActive = note.name == NSApplication.didBecomeActiveNotification
                MainActor.assumeIsolated {
                    if becameActive { self?.model.refreshIncludes() }
                    self?.updateCommandAvailability()
                }
            })
        }
    }

    public func stop() {
        panel?.close()
        panel = nil
        KeyboardShortcuts.disable(.quickConnect)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        model.connectionTests.cancelAll()
    }

    public func open(_ section: SSHSection = .servers) {
        self.section = section
        openWorkspace()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showQuickConnect() { panel?.show() }

    func setWorkspaceVisible(_ visible: Bool) {
        workspaceVisible = visible
        updateCommandAvailability()
    }

    private func updateCommandAvailability() {
        model.mainWindowIsKey = workspaceVisible && section == .servers
            && NSApp.keyWindow?.identifier?.rawValue.hasPrefix("main") == true
    }

    public func prepareToTerminate(_ sender: NSApplication, willTerminate: @escaping () -> Void) -> NSApplication.TerminateReply {
        guard model.store.hasUnsavedChanges || model.hasPendingFormEdits else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "SSH.quit.unsaved.title", defaultValue: "Kaydedilmemiş SSH değişiklikleri var")
        alert.informativeText = String(localized: "SSH.quit.unsaved.message", defaultValue: "Çıkmadan önce SSH yapılandırmasındaki değişiklikler kaydedilsin mi?")
        alert.addButton(withTitle: String(localized: "SSH.action.save", defaultValue: "Kaydet"))
        alert.addButton(withTitle: String(localized: "SSH.action.cancel", defaultValue: "Vazgeç"))
        alert.addButton(withTitle: String(localized: "SSH.action.discardAndQuit", defaultValue: "Kaydetmeden Çık"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.applyPendingGroupDraft()
            if model.hasBlockedFormEdits || model.hasPendingGroupDraft {
                open(.servers)
                if model.hasBlockedFormEdits {
                    model.errorMessage = String(localized: "SSH.quit.pendingForm", defaultValue: "Önce formdaki hataları düzeltin; değişiklikler kaydedilmedi.")
                }
                return .terminateCancel
            }
            Task { @MainActor in
                do {
                    try await model.store.save()
                    willTerminate()
                    sender.reply(toApplicationShouldTerminate: true)
                } catch {
                    open(.servers)
                    AppLog.error(.save, error)
                    model.errorMessage = Messages.text(for: error)
                    sender.reply(toApplicationShouldTerminate: false)
                }
            }
            return .terminateLater
        case .alertThirdButtonReturn: return .terminateNow
        default: return .terminateCancel
        }
    }
}

public struct SSHWorkspaceView: View {
    @Bindable private var runtime: SSHRuntime
    public init(runtime: SSHRuntime = .shared) { self.runtime = runtime }
    public var body: some View {
        Group {
            switch runtime.section {
            case .servers: MainWindow(model: runtime.model)
            case .keys: KeysWindow(app: runtime.model)
            case .knownHosts: KnownHostsWindow(app: runtime.model)
            case .backups: BackupsView(model: runtime.model)
            case .settings: SettingsView(model: runtime.model)
            }
        }
        .environment(\.sshNavigate, { runtime.section = $0 })
        .buttonStyle(.bordered)
        .onAppear { runtime.setWorkspaceVisible(true) }
        .onDisappear { runtime.setWorkspaceVisible(false) }
    }
}

public struct SSHQuickConnectView: View {
    private let runtime: SSHRuntime
    private let dismiss: () -> Void
    public init(runtime: SSHRuntime = .shared, dismiss: @escaping () -> Void) {
        self.runtime = runtime; self.dismiss = dismiss
    }
    public var body: some View {
        QuickConnectView(model: runtime.quickConnect, showsFooter: true, dismiss: dismiss,
            openMainWindow: { runtime.open(.servers) }, openSettings: { runtime.open(.settings) },
            openKnownHosts: { runtime.open(.knownHosts) }, openKeys: { runtime.open(.keys) })
            .frame(width: 420)
            .onAppear { runtime.quickConnect.prepareForDisplay() }
    }
}

public struct SSHCommands: Commands {
    private let runtime: SSHRuntime
    public init(runtime: SSHRuntime = .shared) { self.runtime = runtime }
    public var body: some Commands {
        HostCommandMenu(model: runtime.model, openMainWindow: { runtime.open(.servers) })
    }
}
