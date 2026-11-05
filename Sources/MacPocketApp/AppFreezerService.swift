import AppKit
import Darwin
import MacPocketCore
import SwiftUI

@MainActor
final class AppFreezerService: ObservableObject {
    static let shared = AppFreezerService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("AppFreezerService")
    #endif
    private(set) var moduleRunning = false

    @Published var settings: AppFreezerSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            evaluate()
        }
    }
    /// Frozen apps by process ID.
    @Published private(set) var frozen: [pid_t: String] = [:]

    private var backgroundSince: [pid_t: Date] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Frozen PIDs survive a crash in UserDefaults so the next launch can resume them.
    private static let frozenKey = "MacPocket.freezer.frozen"

    private init() {
        settings = AppFreezerSettings.load(from: .standard)
    }

    func stopForModule() {
        moduleRunning = false
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        backgroundSince = [:]
        thawAll()
    }

    func start() {
        guard !moduleRunning, PocketModule.freezer.isAvailable() else { return }
        moduleRunning = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                // Resume before the app tries to draw, so it never shows a spinning cursor.
                if let app, self?.frozen[app.processIdentifier] != nil { self?.thaw(app.processIdentifier) }
                self?.evaluate()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.backgroundSince[pid] = Date() } }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.backgroundSince[pid] = nil
                if self.frozen.removeValue(forKey: pid) != nil { self.persist() }
            }
        })
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.evaluate() } }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    /// Resumes everything (quit, or the feature turned off).
    func thawAll() {
        for pid in frozen.keys { Self.signal(pid, SIGCONT) }
        frozen = [:]
        persist()
    }

    func evaluate() {
        guard moduleRunning else { return }
        // Nothing to freeze and nothing frozen: skip scanning every running app.
        guard settings.hasWork || !frozen.isEmpty else { return }
        let now = Date()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            guard let bundleID = app.bundleIdentifier, app.processIdentifier > 1, app.processIdentifier != getpid() else { continue }
            let pid = app.processIdentifier
            let since = backgroundSince[pid] ?? app.launchDate ?? now
            backgroundSince[pid] = since
            let state = AppFreezer.AppState(bundleID: bundleID, isFrontmost: pid == front, backgroundSince: since,
                                            isFrozen: frozen[pid] != nil)
            switch AppFreezer.decide(state, settings: settings, now: now) {
            case .freeze?: freeze(pid, bundleID: bundleID)
            case .thaw?: thaw(pid)
            case nil: break
            }
        }
    }

    func freezeNow(_ app: NSRunningApplication) {
        guard !app.isTerminated, let bundleID = app.bundleIdentifier, AppFreezer.canFreeze(bundleID), app.processIdentifier != getpid(),
              app.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        freeze(app.processIdentifier, bundleID: bundleID)
    }

    func thaw(_ pid: pid_t) {
        Self.signal(pid, SIGCONT)
        frozen[pid] = nil
        backgroundSince[pid] = Date()
        persist()
    }

    private func freeze(_ pid: pid_t, bundleID: String) {
        guard frozen[pid] == nil else { return }
        Self.signal(pid, SIGSTOP)
        frozen[pid] = bundleID
        persist()
    }

    /// Sends `sig` to the app and its helper processes (renderers, plug-ins), which would otherwise keep running.
    private static func signal(_ pid: pid_t, _ sig: Int32) {
        // A terminated app reports pid -1: kill(-1, …) would reach every process of the user, kill(0, …) our group.
        guard pid > 1, pid != getpid() else { return }
        for child in Self.children(of: pid) where child > 1 && child != getpid() { kill(child, sig) }
        kill(pid, sig)
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        let count = proc_listchildpids(pid, nil, 0)
        guard count > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(count) * 2)
        let found = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        return Array(buffer.prefix(Int(max(0, found)))).filter { $0 > 1 }
    }

    private func persist() {
        UserDefaults.standard.set(frozen.map { "\($0.key):\($0.value)" }, forKey: Self.frozenKey)
    }

    /// After a crash, resumes apps the previous run froze, if each PID still belongs to the same app.
    static func recoverAfterCrash() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.frozenKey) ?? []
        for entry in stored {
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let pid = pid_t(parts[0]),
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == parts[1] else { continue }
            Self.signal(pid, SIGCONT)
        }
        UserDefaults.standard.removeObject(forKey: Self.frozenKey)
    }
}

/// Tools → Uygulama Dondurucu.
struct AppFreezerView: View {
    @ObservedObject private var service = AppFreezerService.shared
    @State private var running: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Uygulama Dondurucu",
                              subtitle: "Seçtiğin uygulamalar arka planda bir süre kalınca dondurulur ve işlemci kullanmaz; öne geldiklerinde anında çözülür.",
                              icon: "snowflake") {
                Toggle("Uygulama dondurucu", isOn: Binding(get: { service.settings.enabled }, set: { isOn in
                    service.settings.enabled = isOn
                    if !isOn { service.thawAll() }
                }))
                .toggleStyle(.switch).labelsHidden()
            }
            PocketMessage("Arka planda müzik çalan, dosya indiren veya senkronize eden uygulamaları ekleme: dondurulduklarında bu işler de durur.", tone: .neutral)
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    rules
                    current
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onAppear(perform: reload)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in reload() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in reload() }
    }

    private func reload() {
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && AppFreezer.canFreeze($0.bundleIdentifier ?? "") && $0.processIdentifier != getpid() }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Kurallar", icon: "list.bullet")
            if service.settings.rules.isEmpty {
                Text("Henüz kural yok. Aşağıdan çalışan bir uygulamayı ekleyebilir ya da Uygulamalar klasöründen seçebilirsin.")
                    .foregroundStyle(.secondary)
            }
            ForEach($service.settings.rules) { $rule in
                HStack(spacing: PocketSpacing.m) {
                    PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID), size: 24)
                    Text(Self.name(rule.bundleID))
                    Spacer()
                    Picker("Bekleme", selection: $rule.delayMinutes) {
                        ForEach(AppFreezeRule.delayChoices, id: \.self) { Text("\($0) dk sonra").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Button { service.settings.rules.removeAll { $0.bundleID == rule.bundleID } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(Self.name(rule.bundleID)) kuralını kaldır")
                }
            }
            Button { chooseApplications() } label: { Label("Uygulama ekle…", systemImage: "plus") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var current: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Çalışan uygulamalar", icon: "app.badge")
            ForEach(running, id: \.processIdentifier) { app in
                let pid = app.processIdentifier
                let isFrozen = service.frozen[pid] != nil
                let ruled = service.settings.rules.contains { $0.bundleID == app.bundleIdentifier }
                HStack(spacing: PocketSpacing.m) {
                    if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                    Text(app.localizedName ?? app.bundleIdentifier ?? "?")
                    if isFrozen { PocketStatusBadge(text: "Donduruldu", systemImage: "snowflake", tone: .accent) }
                    Spacer()
                    if !ruled, let bundleID = app.bundleIdentifier {
                        Button("Kural ekle") { service.settings.rules.append(AppFreezeRule(bundleID: bundleID)) }.controlSize(.small)
                    }
                    if isFrozen {
                        Button("Çöz") { service.thaw(pid) }.controlSize(.small)
                    } else {
                        Button("Şimdi dondur") { service.freezeNow(app) }.controlSize(.small)
                            .disabled(app.isActive)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private static func name(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            .filter { AppFreezer.canFreeze($0) && !service.settings.rules.map(\.bundleID).contains($0) }
        service.settings.rules.append(contentsOf: ids.map { AppFreezeRule(bundleID: $0) })
    }
}

#if DEBUG
extension AppFreezerService {
    var moduleDiagnosticResources: [String: Int] { ["observers": observers.count, "timer": timer?.isValid == true ? 1 : 0, "frozen": frozen.count] }
}
#endif
