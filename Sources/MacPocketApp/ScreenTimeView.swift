import AppKit
import Charts
import Combine
import CoreGraphics
import IOKit.pwr_mgt
import MacPocketCore
import SwiftUI

// MARK: - Service

/// Tracks the frontmost app while the user is actually at the Mac. Counting pauses on screen lock, sleep and idle
/// input; an app that keeps the display awake (video, presentations) counts as in use even without input.
/// Opt-in, and the ledger never leaves this Mac.
@MainActor
final class ScreenTimeService: ObservableObject {
    static let shared = ScreenTimeService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("ScreenTimeService")
    #endif
    private(set) var moduleRunning = false
    static let enabledKey = "MacPocket.screenTime.enabled"
    static let idleKey = "MacPocket.screenTime.idleSeconds"

    @Published private(set) var ledger = UsageLedger()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: ScreenTimeService.enabledKey)
    @Published var idleSeconds: Double = {
        let stored = UserDefaults.standard.double(forKey: ScreenTimeService.idleKey)
        return [120.0, 300, 600].contains(stored) ? stored : 300
    }() {
        didSet { UserDefaults.standard.set(idleSeconds, forKey: Self.idleKey) }
    }
    /// The app being counted right now, for the live row on the page.
    @Published private(set) var current: (app: String, name: String, since: Date)?
    @Published private(set) var pausedReason: PauseReason?

    enum PauseReason { case idle, locked, asleep }

    #if DEBUG
    private let store = UsageStore(url: ModuleRuntimeAudit.dataURL("usage.json"))
    #else
    private let store = UsageStore()
    #endif
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var loaded = false
    private var loading = false
    private var dirty = false
    private var lastSave = Date.distantPast
    private var locked = false
    private var asleep = false

    func stopForModule() {
        moduleRunning = false
        end()
    }

    func start() {
        guard !moduleRunning, PocketModule.screenTime.isAvailable() else { return }
        moduleRunning = true
        if loaded { if enabled { begin() }; return }
        guard !loading else { return }
        loading = true
        Task {
            var stored = await store.load()
            stored.prune()
            ledger = stored
            loaded = true
            loading = false
            if enabled, moduleRunning { begin() }
        }
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value { begin() } else { end() }
    }

    /// The ledger with the running segment included, so totals on screen tick live.
    var live: UsageLedger {
        guard let current else { return ledger }
        var copy = ledger
        copy.record(app: current.app, name: current.name, from: current.since, to: Date())
        return copy
    }

    func remove(app: String) {
        if current?.app == app { current = (app, current!.name, Date()) }
        ledger.remove(app: app)
        save(force: true)
    }

    func deleteAll() {
        if let current { self.current = (current.app, current.name, Date()) }
        ledger = UsageLedger()
        Task { try? await store.delete() }
    }

    func flush() {
        closeSegment(at: Date())
        save(force: true)
        if moduleRunning && enabled && pausedReason == nil { openSegment() }
    }

    // MARK: Tracking

    private func begin() {
        guard moduleRunning, loaded, observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor @Sendable () -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            })
        }
        on(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.frontmostChanged() }
        on(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.pause(.asleep) }
        on(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.pause(.asleep) }
        on(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.pause(.locked) }
        on(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.asleep = false; self?.resumeIfPossible() }
        on(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.asleep = false; self?.resumeIfPossible() }
        on(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.locked = false; self?.resumeIfPossible() }
        let distributed = DistributedNotificationCenter.default()
        on(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.pause(.locked) }
        on(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.locked = false; self?.resumeIfPossible() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { ScreenTimeService.shared.tick() }
        }
        pausedReason = nil
        openSegment()
    }

    private func end() {
        closeSegment(at: Date())
        save(force: true)
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        pausedReason = nil
    }

    private func frontmostChanged() {
        guard pausedReason == nil || pausedReason == .idle else { return }
        let previous = current?.app
        closeSegment(at: Date())
        pausedReason = nil
        openSegment()
        if let app = current?.app, app != previous { ledger.countSwitch(at: Date()) }
        save(force: false)
    }

    private func pause(_ reason: PauseReason) {
        if reason == .locked { locked = true }
        if reason == .asleep { asleep = true }
        closeSegment(at: Date())
        pausedReason = reason
        save(force: true)
    }

    private func resumeIfPossible() {
        guard moduleRunning, enabled, !locked, !asleep else { return }
        pausedReason = nil
        openSegment()
    }

    private func tick() {
        guard enabled else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if pausedReason == nil, idle >= idleSeconds, !(current != nil && Self.keepsDisplayAwake(pid: currentPID)) {
            // Count up to the last input, not the moment idleness was noticed.
            closeSegment(at: Date().addingTimeInterval(-idle))
            pausedReason = .idle
        } else if pausedReason == .idle, idle < idleSeconds {
            pausedReason = nil
            openSegment()
        } else if pausedReason == nil, let current, Date().timeIntervalSince(current.since) > 300 {
            // Bank long segments periodically so a crash loses at most a few minutes.
            closeSegment(at: Date())
            openSegment()
        }
        save(force: false)
    }

    private var currentPID: pid_t?

    private func openSegment() {
        guard enabled, current == nil, let app = NSWorkspace.shared.frontmostApplication,
              let bundle = app.bundleIdentifier, !UsageExclusions.bundleIdentifiers.contains(bundle) else { return }
        current = (bundle, app.localizedName ?? bundle, Date())
        currentPID = app.processIdentifier
    }

    private func closeSegment(at end: Date) {
        guard let segment = current else { return }
        current = nil
        ledger.record(app: segment.app, name: segment.name, from: segment.since, to: max(segment.since, end))
        dirty = true
    }

    private func save(force: Bool) {
        guard dirty, force || Date().timeIntervalSince(lastSave) > 20 else { return }
        dirty = false
        lastSave = Date()
        var snapshot = ledger
        snapshot.prune()
        let store = store
        Task { try? await store.save(snapshot) }
    }

    /// Video players and presentation apps hold a display-sleep assertion while playing.
    private static func keepsDisplayAwake(pid: pid_t?) -> Bool {
        guard let pid else { return false }
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              let assertions = byProcess[NSNumber(value: pid)] else { return false }
        return assertions.contains { ($0["AssertType"] as? String).map { $0.contains("DisplaySleep") } ?? false }
    }
}

// MARK: - Page

private enum ScreenTimeRange: String, CaseIterable, Identifiable {
    case today, yesterday, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: String(localized: "Bugün")
        case .yesterday: String(localized: "Dün")
        case .week: String(localized: "7 Gün")
        case .month: String(localized: "30 Gün")
        }
    }
    var dayCount: Int { switch self { case .today, .yesterday: 1; case .week: 7; case .month: 30 } }
    var isSingleDay: Bool { dayCount == 1 }
}

/// Tools → Ekran Süresi.
struct ScreenTimeView: View {
    @ObservedObject private var service = ScreenTimeService.shared
    @State private var range = ScreenTimeRange.today
    @State private var search = ""
    @State private var confirmDelete = false
    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ekran Süresi",
                              subtitle: "Hangi uygulamada ne kadar zaman geçirdiğini gör. Boşta, kilitli ve uykuda geçen süre sayılmaz; veriler yalnız bu Mac’te kalır.",
                              icon: "hourglass") {
                Toggle(isOn: Binding(get: { service.enabled }, set: { service.setEnabled($0) })) { Text("Takip") }
                    .toggleStyle(.switch).fixedSize()
            }
            if !service.enabled && service.ledger.days.isEmpty {
                ScrollView { intro }
            } else {
                GlassTabBar(tabs: ScreenTimeRange.allCases.map { GlassTab(id: $0, title: $0.title) }, selection: $range)
                    .frame(maxWidth: 420)
                ScrollView {
                    VStack(alignment: .leading, spacing: PocketSpacing.l) {
                        content
                    }
                    .padding(.bottom, PocketSpacing.l)
                }
            }
        }
        .pocketPage()
        .onReceive(ticker) { now = $0 }
        .confirmationDialog("Tüm ekran süresi verileri silinsin mi?", isPresented: $confirmDelete) {
            Button("Tümünü Sil", role: .destructive) { service.deleteAll() }
        } message: {
            Text("Son 30 günün kaydı bu Mac’ten silinir. Takip açıksa yeniden saymaya başlar.")
        }
    }

    private var intro: some View {
        VStack(spacing: PocketSpacing.l) {
            Image(systemName: "hourglass.circle.fill").font(.system(size: 64)).foregroundStyle(PocketTheme.brandGradient)
            Text("Zamanının nereye gittiğini gör").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                Label("Öndeki uygulamanın süresi sayılır; arka plandaki uygulamalar sayılmaz.", systemImage: "macwindow")
                Label("Klavye ve fare kullanılmadığında, ekran kilitliyken ve uykuda sayaç durur. Video oynatan uygulamalar sayılmaya devam eder.", systemImage: "pause.circle")
                Label("Kayıtlar yalnız bu Mac’te, son 30 gün için tutulur; hiçbir yere gönderilmez.", systemImage: "lock.shield")
            }
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: 520, alignment: .leading)
            Button { service.setEnabled(true) } label: {
                Label("Takibi Başlat", systemImage: "play.fill").padding(.horizontal, PocketSpacing.s)
            }
            .buttonStyle(.pocketPrimary).controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .pocketCard(padding: PocketSpacing.xl)
    }

    @ViewBuilder private var content: some View {
        let ledger = service.live
        let calendar = Calendar.current
        let endDate = range == .yesterday ? calendar.date(byAdding: .day, value: -1, to: now) ?? now : now
        let days = ledger.range(endingAt: endDate, count: range.dayCount)
        let total = days.reduce(0) { $0 + $1.day.total }
        let apps = UsageLedger.appTotals(days.map(\.day), names: ledger.names)
        let activeDays = max(1, days.filter { $0.day.total > 0 }.count)
        let hourly = UsageLedger.hourTotals(days.map(\.day))
        // Today/yesterday trend by hour; longer ranges by day.
        let trend = range.isSingleDay ? hourly : days.map(\.day.total)
        let topTrend = apps.first.map { top in range.isSingleDay ? [] : days.map { $0.day.apps[top.app] ?? 0 } } ?? []

        statusLine
        HStack(spacing: PocketSpacing.m) {
            PocketMetricTile(title: "Toplam", value: "\(UsageFormatter.duration(total))", detail: "\(totalDetail(days: days))",
                             icon: "hourglass", color: PocketTheme.brand, history: trend, historyCeiling: nil)
            if range.isSingleDay {
                PocketMetricTile(title: "Uygulama geçişi", value: "\(days.first?.day.switches ?? 0)",
                                 detail: "\(String(localized: "\(apps.count) uygulama kullanıldı"))",
                                 icon: "arrow.left.arrow.right", color: PocketTheme.brandSecondary, history: hourly, historyCeiling: nil)
            } else {
                PocketMetricTile(title: "Günlük ortalama", value: "\(UsageFormatter.duration(total / Double(activeDays)))",
                                 detail: "\(String(localized: "\(activeDays) günlük kayıt"))",
                                 icon: "chart.bar", color: PocketTheme.brandSecondary, history: trend, historyCeiling: nil)
            }
            PocketMetricTile(title: "En çok", value: "\(apps.first.map { ledger.names[$0.app] ?? $0.app } ?? "—")",
                             detail: "\(apps.first.map { UsageFormatter.duration($0.seconds) } ?? String(localized: "Henüz kayıt yok"))",
                             icon: "crown", color: PocketTheme.power, history: topTrend, historyCeiling: nil)
            PocketMetricTile(title: "En yoğun saat", value: "\(peakHour(days.map(\.day)))",
                             detail: "\(String(localized: "Saat dilimine göre"))", icon: "clock", color: PocketTheme.disk,
                             history: hourly, historyCeiling: nil)
        }
        chart(days: days)
        appList(apps, total: total, ledger: ledger)
        footer
    }

    @ViewBuilder private var statusLine: some View {
        if service.enabled {
            HStack(spacing: PocketSpacing.s) {
                switch service.pausedReason {
                case .idle?: Label("Boşta: sayaç duraklatıldı", systemImage: "pause.circle.fill").foregroundStyle(.orange)
                case .locked?: Label("Ekran kilitli: sayaç duraklatıldı", systemImage: "lock.fill").foregroundStyle(.secondary)
                case .asleep?: Label("Uyku: sayaç duraklatıldı", systemImage: "moon.fill").foregroundStyle(.secondary)
                case nil:
                    if let current = service.current {
                        PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: current.app), size: 18)
                        Text(String(localized: "Şu an sayılıyor: \(current.name)"))
                        Text(verbatim: "· " + UsageFormatter.duration(now.timeIntervalSince(current.since))).foregroundStyle(.secondary)
                    } else {
                        Label("Takip açık", systemImage: "record.circle").foregroundStyle(PocketTheme.disk)
                    }
                }
            }
            .font(.callout)
        } else {
            PocketMessage("Takip kapalı; aşağıdaki kayıtlar önceki dönemden. Yeniden saymak için sağ üstten aç.", tone: .warning)
        }
    }

    private func totalDetail(days: [(date: Date, day: UsageDay)]) -> String {
        guard range == .today, let today = days.first?.day.total else {
            return range.isSingleDay ? String(localized: "Ön plandaki süre") : String(localized: "Seçili dönemde")
        }
        let yesterday = service.live.day(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now).total
        guard yesterday > 0 else { return String(localized: "Dün kayıt yok") }
        let difference = today - yesterday
        let text = UsageFormatter.duration(abs(difference))
        return difference >= 0 ? String(localized: "Düne göre \(text) fazla") : String(localized: "Düne göre \(text) az")
    }

    private func peakHour(_ days: [UsageDay]) -> String {
        let hours = UsageLedger.hourTotals(days)
        guard let peak = hours.indices.max(by: { hours[$0] < hours[$1] }), hours[peak] > 0 else { return "—" }
        return String(format: "%02d:00", peak)
    }

    @ViewBuilder private func chart(days: [(date: Date, day: UsageDay)]) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader(range.isSingleDay ? "Saatlere göre" : "Günlere göre", icon: "chart.bar.xaxis")
            if range.isSingleDay {
                let hours = UsageLedger.hourTotals(days.map(\.day))
                Chart(Array(hours.enumerated()), id: \.offset) { hour, seconds in
                    BarMark(x: .value("Saat", hour), y: .value("Dakika", seconds / 60))
                        .foregroundStyle(PocketTheme.brandGradient)
                        .cornerRadius(3)
                }
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine(); AxisValueLabel { if let hour = value.as(Int.self) { Text(String(format: "%02d", hour)) } }
                } }
                .chartYScale(domain: 0...60)
                .chartYAxis { AxisMarks(position: .leading, values: [0, 30, 60]) { value in
                    AxisGridLine(); AxisValueLabel { if let minutes = value.as(Int.self) { Text(String(localized: "\(minutes) dk")) } }
                } }
                .frame(height: 170)
            } else {
                let average = days.map(\.day.total).reduce(0, +) / Double(max(1, days.filter { $0.day.total > 0 }.count))
                Chart {
                    ForEach(days, id: \.date) { item in
                        BarMark(x: .value("Gün", item.date, unit: .day), y: .value("Dakika", item.day.total / 60))
                            .foregroundStyle(Calendar.current.isDateInToday(item.date) ? AnyShapeStyle(PocketTheme.brandGradient) : AnyShapeStyle(PocketTheme.brand.opacity(0.55)))
                            .cornerRadius(3)
                    }
                    if average > 0 {
                        RuleMark(y: .value("Ortalama", average / 60))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .leading) {
                                Text(String(localized: "Ortalama \(UsageFormatter.duration(average))")).font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
                    AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                } }
                .chartYScale(domain: 0...max(60, (days.map(\.day.total).max() ?? 0) / 60 * 1.15))
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(); AxisValueLabel { if let minutes = value.as(Double.self) { Text(UsageFormatter.duration(minutes * 60)) } }
                } }
                .frame(height: 170)
            }
        }
        .pocketCard()
    }

    @ViewBuilder private func appList(_ apps: [(app: String, seconds: Double)], total: Double, ledger: UsageLedger) -> some View {
        let filtered = search.isEmpty ? apps : apps.filter { (ledger.names[$0.app] ?? $0.app).localizedCaseInsensitiveContains(search) }
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Uygulamalar", icon: "square.grid.2x2") {
                Text(String(localized: "\(apps.count) uygulama"))
            }
            if apps.count > 6 { PocketSearchField("Uygulama ara", text: $search) }
            if filtered.isEmpty {
                Text(apps.isEmpty ? "Bu dönem için kayıt yok. Takip açıkken kullandığın uygulamalar burada görünür." : "Aramayla eşleşen uygulama yok.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.prefix(40).enumerated()), id: \.element.app) { index, item in
                        ScreenTimeAppRow(app: item.app, name: ledger.names[item.app] ?? item.app, seconds: item.seconds,
                                         share: total > 0 ? item.seconds / total : 0, maximum: filtered.first?.seconds ?? 1,
                                         live: service.current?.app == item.app && service.pausedReason == nil,
                                         remove: { service.remove(app: item.app) })
                        if index < min(filtered.count, 40) - 1 { Divider().padding(.leading, 44) }
                    }
                }
            }
        }
        .pocketCard()
    }

    private var footer: some View {
        HStack(spacing: PocketSpacing.m) {
            Picker("Boşta sayılma süresi", selection: $service.idleSeconds) {
                Text("2 dakika").tag(120.0)
                Text("5 dakika").tag(300.0)
                Text("10 dakika").tag(600.0)
            }
            .fixedSize()
            Spacer()
            Button("Tüm Verileri Sil…", role: .destructive) { confirmDelete = true }
                .buttonStyle(.bordered).tint(.red)
                .disabled(service.ledger.days.isEmpty)
        }
        .font(.callout)
        .padding(.horizontal, PocketSpacing.xs)
    }
}

private struct ScreenTimeAppRow: View {
    let app: String
    let name: String
    let seconds: Double
    let share: Double
    let maximum: Double
    let live: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: app), size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(name).font(.headline).lineLimit(1)
                    if live { PocketStatusBadge(text: "Şimdi", systemImage: "record.circle", tone: .success) }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule().fill(PocketTheme.brandGradient)
                            .frame(width: max(4, proxy.size.width * CGFloat(seconds / max(1, maximum))))
                    }
                }
                .frame(height: 6)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(UsageFormatter.duration(seconds)).font(.callout.weight(.semibold)).monospacedDigit()
                Text(MenuBarFormatter.percent(share * 100, decimals: false)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.vertical, PocketSpacing.s)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Bu Uygulamanın Kaydını Sil", role: .destructive, action: remove)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
extension ScreenTimeService {
    var moduleDiagnosticResources: [String: Int] { ["observers": observers.count, "timer": timer?.isValid == true ? 1 : 0, "current": current == nil ? 0 : 1] }
}
#endif
