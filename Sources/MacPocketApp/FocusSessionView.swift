import AppKit
import MacPocketCore
import SwiftUI
import UserNotifications

@MainActor
final class FocusSessionService: ObservableObject {
    static let shared = FocusSessionService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("FocusSessionService")
    #endif

    @Published var settings = FocusSettings.load(from: .standard) {
        didSet { if settings != oldValue { settings.save(to: .standard) } }
    }
    @Published private(set) var history = FocusHistory.load(from: .standard)
    @Published private(set) var startedAt: Date?
    @Published private(set) var endsAt: Date?
    @Published private(set) var applied: [FocusChange] = []
    @Published private(set) var message: String?

    private weak var model: PocketModel?
    private var timer: Timer?
    private var plannedMinutes = 0
    private var ownedAwakeSessionID: UUID?

    private init() {}

    /// What a running session changed that would outlive MacPocket: undone at the next launch after a crash.
    private static let pendingKey = "MacPocket.focus.pending"
    private struct Pending: Codable {
        var hidDesktopIcons = false
        var guardedQuit = false
        /// Display ID → brightness before dimming.
        var dimmed: [UInt32: Double]?
    }
    /// Set while start or finish is between awaits, so a second click can't interleave with it.
    private var transitioning = false
    private(set) var moduleRunning = false
    var canSuspendModule: Bool { !isRunning && !transitioning }

    func attach(_ model: PocketModel) {
        guard !moduleRunning, PocketModule.focus.isAvailable() else { return }
        moduleRunning = true
        self.model = model
    }

    func stopForModule() {
        moduleRunning = false
        undoForQuit()
        if PocketModule.displays.isAvailable() { DisplayBrightnessService.shared.scheduleHeld = false }
        timer?.invalidate()
        timer = nil
        startedAt = nil
        endsAt = nil
        applied = []
        ownedAwakeSessionID = nil
        model = nil
    }

    private func recordPending() {
        var pending = Pending()
        for change in applied {
            if case .hideDesktopIcons = change { pending.hidDesktopIcons = true }
            if case .guardQuit = change { pending.guardedQuit = true }
            if case let .dimDisplay(display, _, previous) = change { pending.dimmed = (pending.dimmed ?? [:]).merging([display: previous]) { $1 } }
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: Self.pendingKey)
    }

    static func recoverAfterCrash() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingKey),
              let pending = try? JSONDecoder().decode(Pending.self, from: data) else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        if pending.guardedQuit {
            var settings = QuitGuardSettings.load(from: .standard)
            settings.quitMode = .off
            settings.save(to: .standard)
        }
        DisplayBrightnessService.restoreInterruptedLevels(pending.dimmed ?? [:])
        if pending.hidDesktopIcons { Task { try? await QuickActionService.setDesktopIcons(visible: true) } }
    }

    /// At quit: puts back what can be undone without waiting (Finder restarts on its own).
    func undoForQuit() {
        guard isRunning else { return }
        for change in applied {
            switch change {
            case .hideDesktopIcons:
                _ = SystemHiddenSettingsStore().write(nil, key: "CreateDesktop", domain: .finder)
                let restart = Process()
                restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                restart.arguments = ["Finder"]
                try? restart.run()
            case .guardQuit:
                QuitGuardService.shared.settings.quitMode = .off
            case let .dimDisplay(display, _, previous):
                DisplayBrightnessService.shared.restoreLevelNow(previous, for: display)
            default:
                break
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    var isRunning: Bool { startedAt != nil }

    func start() async {
        guard moduleRunning, !isRunning, !transitioning else { return }
        guard (!settings.guardQuit || PocketModule.quitGuard.isAvailable()),
              (settings.dimOtherDisplays == nil || PocketModule.displays.isAvailable()),
              ((settings.startMacro == nil && settings.endMacro == nil) || PocketModule.macros.isAvailable()) else {
            message = String(localized: "Odak oturumunun kullanacağı modülleri Ayarlar > Modüller’den aç veya ilgili oturum seçeneklerini kapat.")
            return
        }
        transitioning = true
        defer { transitioning = false }
        let brightness = PocketModule.displays.isAvailable() ? DisplayBrightnessService.shared : nil
        var active: UInt32?
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(CGEvent(source: nil)?.location ?? .zero, 1, &id, &count) == .success, count > 0 { active = id }
        let environment = FocusEnvironment(
            desktopIconsVisible: QuickActionService.desktopIconsVisible,
            quitGuardOff: PocketModule.quitGuard.isAvailable() && QuitGuardService.shared.settings.quitMode == .off,
            displayLevels: Dictionary(uniqueKeysWithValues: (brightness?.displays ?? []).map { ($0.id, $0.level) }),
            activeDisplay: active)
        let changes = FocusPlanner.start(settings, environment: environment)
        let now = Date()
        startedAt = now
        endsAt = now.addingTimeInterval(Double(settings.minutes) * 60)
        plannedMinutes = settings.minutes
        message = nil
        applied = []
        brightness?.scheduleHeld = true
        for change in changes {
            switch change {
            case let .keepAwake(minutes):
                guard let session = await model?.startAwake(duration: Double(minutes) * 60) else {
                    message = model?.awakeError ?? String(localized: "Uyanık tutma oturumu başlatılamadı."); continue
                }
                ownedAwakeSessionID = session.id
            case .hideDesktopIcons:
                do { try await QuickActionService.setDesktopIcons(visible: false) } catch { message = error.localizedDescription; continue }
            case let .dimDisplay(display, level, _):
                brightness?.setLevel(level, for: display, fromSchedule: true)
            case .guardQuit:
                QuitGuardService.shared.settings.quitMode = .hold
            case let .runMacro(id):
                if let macro = MacroService.shared.library.macros.first(where: { $0.id == id }) { MacroService.shared.run(macro) }
            }
            applied.append(change)
            recordPending()
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let end = self.endsAt, Date() >= end else { return }
                Task { await self.finish(completed: true) }
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ends the session and undoes exactly what it changed.
    func finish(completed: Bool) async {
        guard let started = startedAt, !transitioning else { return }
        transitioning = true
        defer { transitioning = false }
        timer?.invalidate()
        timer = nil
        let brightness = PocketModule.displays.isAvailable() ? DisplayBrightnessService.shared : nil
        for change in applied.reversed() {
            switch change {
            case .keepAwake:
                if let ownedAwakeSessionID { await model?.stopAwake(sessionID: ownedAwakeSessionID) }
                ownedAwakeSessionID = nil
            case .hideDesktopIcons:
                try? await QuickActionService.setDesktopIcons(visible: true)
            case let .dimDisplay(display, _, previous):
                brightness?.setLevel(previous, for: display, fromSchedule: true)
            case .guardQuit:
                QuitGuardService.shared.settings.quitMode = .off
            case .runMacro:
                break
            }
        }
        brightness?.scheduleHeld = false
        if let id = settings.endMacro, let macro = MacroService.shared.library.macros.first(where: { $0.id == id }) {
            MacroService.shared.run(macro)
        }
        let record = FocusSessionRecord(start: started, end: Date(), plannedMinutes: plannedMinutes)
        history.add(record)
        history.save(to: .standard)
        startedAt = nil
        endsAt = nil
        applied = []
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        if completed { Self.notify(minutes: record.minutes) }
        message = completed ? String(localized: "Oturum tamamlandı: \(record.minutes) dk odaklandın.")
                            : String(localized: "Oturum \(record.minutes) dakikada bitirildi.")
    }

    private static func notify(minutes: Int) {
        guard PocketAlertNotifier.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Odak oturumu bitti")
        content.body = String(localized: "\(minutes) dakika odaklandın. Kısa bir mola iyi gelir.")
        content.sound = .default
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            try? await center.add(UNNotificationRequest(identifier: "MacPocket.focus", content: content, trigger: nil))
        }
    }
}

/// Tools → Odak Oturumu.
struct FocusSessionView: View {
    @ObservedObject private var service = FocusSessionService.shared
    @ObservedObject private var modules = PocketModuleRuntime.shared
    private var availableMacros: [Macro] {
        guard modules.available.contains(.macros) else { return [] }
        return MacroService.shared.library.macros
    }
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Odak Oturumu",
                              subtitle: "Tek düğmeyle Mac’i odaklanmaya hazırla; süre bitince her şey eski hâline döner.",
                              icon: "scope")
            if let message = service.message { PocketMessage(message, tone: .success) }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    hero
                    if !service.isRunning { options }
                    statistics
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
    }

    private var hero: some View {
        HStack(spacing: PocketSpacing.xl) {
            ZStack {
                if let start = service.startedAt, let end = service.endsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let progress = min(1, context.date.timeIntervalSince(start) / end.timeIntervalSince(start))
                        PocketRing(fraction: progress, color: PocketTheme.brand, lineWidth: 12)
                            .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                    }
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                } else {
                    PocketRing(fraction: 0, color: PocketTheme.brand, lineWidth: 12)
                    Text("\(service.settings.minutes) dk").font(.system(size: 30, weight: .semibold, design: .rounded))
                }
            }
            .frame(width: 170, height: 170)
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                Text(service.isRunning ? "Odaktasın" : "Hazır").font(.title.weight(.bold))
                if service.isRunning {
                    ForEach(Array(service.applied.enumerated()), id: \.offset) { _, change in
                        Label(Self.describe(change), systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    }
                    Button("Oturumu bitir") { Task { await service.finish(completed: false) } }
                        .controlSize(.large)
                } else {
                    GlassTabBar(tabs: FocusSettings.minuteChoices.map { GlassTab(id: $0, title: "\($0) dk") }, selection: $service.settings.minutes)
                        .frame(maxWidth: 380)
                        .accessibilityLabel("Süre")
                    Button { Task { await service.start() } } label: { Label("Odaklan", systemImage: "play.fill") }
                        .buttonStyle(.pocketPrimary)
                        .controlSize(.large)
                }
            }
            Spacer(minLength: 0)
        }
        .pocketCard()
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Oturum boyunca", icon: "slider.horizontal.3")
            Toggle("Mac’i uyanık tut", isOn: $service.settings.keepAwake)
            Toggle("Masaüstü simgelerini gizle", isOn: $service.settings.hideDesktopIcons)
            HStack {
                Toggle("Diğer harici ekranları karart", isOn: Binding(get: { service.settings.dimOtherDisplays != nil },
                                                                       set: { service.settings.dimOtherDisplays = $0 ? 0.35 : nil }))
                if let level = service.settings.dimOtherDisplays {
                    Slider(value: Binding(get: { level }, set: { service.settings.dimOtherDisplays = $0 }), in: 0.05...0.9) { Text("Karartma") }
                        .labelsHidden().frame(maxWidth: 200)
                    Text(verbatim: pocketPercent(level * 100)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Toggle("⌘Q ile yanlışlıkla çıkmayı engelle", isOn: $service.settings.guardQuit)
            Picker("Başlarken çalışacak makro", selection: $service.settings.startMacro) {
                Text("Yok").tag(UUID?.none)
                ForEach(availableMacros) { Text($0.name).tag(Optional($0.id)) }
            }
            .frame(maxWidth: 420)
            Picker("Biterken çalışacak makro", selection: $service.settings.endMacro) {
                Text("Yok").tag(UUID?.none)
                ForEach(availableMacros) { Text($0.name).tag(Optional($0.id)) }
            }
            .frame(maxWidth: 420)
            Text("İpucu: macOS Odak modunu açan bir Kestirme’yi bir makroya koyup burada seçebilirsin. Oturum yalnız kendi değiştirdiklerini geri alır.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var statistics: some View {
        let today = service.history.minutes(on: Date())
        let streak = service.history.streak(until: Date())
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Geçmiş", icon: "chart.bar")
            HStack(spacing: PocketSpacing.xxl) {
                stat("Bugün", "\(today) dk")
                stat("Seri", String(localized: "\(streak) gün"))
                stat("Toplam oturum", "\(service.history.records.count)")
            }
            ForEach(service.history.records.prefix(8)) { record in
                HStack {
                    Image(systemName: record.completed ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(record.completed ? PocketTheme.disk : .secondary)
                    Text(record.start.formatted(.dateTime.day().month().hour().minute().locale(pocketLocale)))
                    Spacer()
                    Text("\(record.minutes) / \(record.plannedMinutes) dk").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }

    private static func describe(_ change: FocusChange) -> String {
        switch change {
        case let .keepAwake(minutes): String(localized: "\(minutes) dk uyanık")
        case .hideDesktopIcons: String(localized: "Masaüstü simgeleri gizli")
        case let .dimDisplay(_, level, _): String(localized: "Diğer ekran \(pocketPercent(level * 100))")
        case .guardQuit: String(localized: "⌘Q koruması açık")
        case .runMacro: String(localized: "Başlangıç makrosu çalıştı")
        }
    }
}

#if DEBUG
extension FocusSessionService {
    var moduleDiagnosticResources: [String: Int] { ["timer": timer?.isValid == true ? 1 : 0, "running": isRunning ? 1 : 0] }
}
#endif
