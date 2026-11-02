import AppKit
import MacPocketCore
import SwiftUI
import UserNotifications

struct PrivacyEvent: Identifiable {
    let id = UUID()
    let activity: PrivacyActivity
    let startedAt: Date
}

extension PrivacyActivity {
    var displayName: String {
        appName ?? bundleID ?? String(localized: "Bilinmeyen uygulama")
    }
}

/// Watches microphone and camera use. Polls every 2 s while notifications are on or the page is open; the probe
/// runs off the main thread. Notifications are opt-in, so turning the switch on is what asks for permission.
@MainActor
final class PrivacyMonitorService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PrivacyMonitorService()

    private nonisolated static let notificationPrefix = "MacPocket.privacy."
    private nonisolated static let ignoreAction = "MacPocket.privacy.ignore"
    private static let ignorableCategory = "MacPocket.privacy.ignorable"
    private static let pollInterval = Duration.seconds(2)
    private static let recentLimit = 20

    @Published var settings = PrivacySettings.load(from: .standard) {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            if settings.isEnabled != oldValue.isEnabled { enabledChanged() }
            updatePolling()
        }
    }
    @Published private(set) var activities: [PrivacyActivity] = []
    @Published private(set) var recent: [PrivacyEvent] = []
    @Published private(set) var notificationsDenied = false

    private var tracker = PrivacyChangeTracker()
    private var pollTask: Task<Void, Never>?
    private var viewers = 0

    private override init() { super.init() }

    func start() {
        if PocketAlertNotifier.isAvailable {
            let ignore = UNNotificationAction(identifier: Self.ignoreAction, title: String(localized: "Bu uygulama için bildirme"), options: [])
            let category = UNNotificationCategory(identifier: Self.ignorableCategory, actions: [ignore], intentIdentifiers: [])
            UNUserNotificationCenter.current().setNotificationCategories([category])
            UNUserNotificationCenter.current().delegate = self
        }
        updatePolling()
    }

    /// The page being visible keeps the live status current even while notifications are off.
    func setViewing(_ viewing: Bool) {
        viewers = max(0, viewers + (viewing ? 1 : -1))
        updatePolling()
    }

    func ignore(bundleID: String, name: String) {
        settings.ignoredApps[bundleID] = name
    }

    func stopIgnoring(_ bundleID: String) {
        settings.ignoredApps[bundleID] = nil
    }

    func refreshAuthorization() async {
        notificationsDenied = await PocketAlertNotifier.authorizationDenied()
    }

    private func enabledChanged() {
        guard settings.isEnabled else { return }
        Task {
            let allowed = await PocketAlertNotifier.requestAuthorization()
            notificationsDenied = !allowed && PocketAlertNotifier.isAvailable
        }
    }

    private func updatePolling() {
        let wanted = settings.isEnabled || viewers > 0
        if wanted, pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    try? await Task.sleep(for: Self.pollInterval)
                }
            }
        } else if !wanted {
            pollTask?.cancel()
            pollTask = nil
            // A stopped monitor must not report stale use, and starting again must not alert about use already under way.
            activities = []
            tracker = PrivacyChangeTracker()
        }
    }

    private func poll() async {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningAppInfo? in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return RunningAppInfo(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
        }
        let current = await Task.detached(priority: .utility) { PrivacyProbe.activities(apps: apps) }.value
        guard !Task.isCancelled else { return }
        apply(current)
    }

    private func apply(_ current: Set<PrivacyActivity>) {
        let sorted = current.sorted { $0.id < $1.id }
        if sorted != activities { activities = sorted }
        let now = Date()
        let started = tracker.update(current: current, ignoredApps: Set(settings.ignoredApps.keys), now: now)
        guard !started.isEmpty else { return }
        recent = Array((started.map { PrivacyEvent(activity: $0, startedAt: now) } + recent).prefix(Self.recentLimit))
        if settings.isEnabled { started.forEach(notify) }
    }

    private func notify(_ activity: PrivacyActivity) {
        guard PocketAlertNotifier.isAvailable else { return }
        let content = UNMutableNotificationContent()
        switch activity.device {
        case .microphone:
            content.title = String(localized: "Mikrofon kullanılıyor")
            content.body = activity.appName != nil || activity.bundleID != nil
                ? String(localized: "\(activity.displayName) mikrofonu kullanıyor.")
                : String(localized: "Bir uygulama mikrofonu kullanıyor.")
        case .camera:
            content.title = String(localized: "Kamera kullanılıyor")
            content.body = String(localized: "Bir uygulama kamerayı kullanıyor. macOS hangi uygulama olduğunu bildirmez.")
        }
        if let bundleID = activity.bundleID {
            content.categoryIdentifier = Self.ignorableCategory
            content.userInfo = ["bundleID": bundleID, "name": activity.displayName]
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: Self.notificationPrefix + activity.id, content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            try? await center.add(request)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Banners show even while MacPocket is frontmost, but only for this feature: other alerts keep their behavior.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix(Self.notificationPrefix) ? [.banner, .sound] : []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.ignoreAction,
              let bundleID = response.notification.request.content.userInfo["bundleID"] as? String,
              let name = response.notification.request.content.userInfo["name"] as? String else { return }
        await MainActor.run { PrivacyMonitorService.shared.ignore(bundleID: bundleID, name: name) }
    }
}

/// Tools → Gizlilik Kontrolü.
struct PrivacyCheckView: View {
    @ObservedObject private var service = PrivacyMonitorService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Gizlilik Kontrolü",
                              subtitle: "Mikrofon ya da kamera açıldığında anında gör ve bildirim al; izin listelerine değil, gerçek kullanıma bakar.",
                              icon: "eye.trianglebadge.exclamationmark") {
                if service.settings.isEnabled {
                    PocketStatusBadge(text: "Bildirimler açık", systemImage: "bell.fill", tone: .success)
                } else {
                    PocketStatusBadge(text: "Bildirimler kapalı", systemImage: "bell.slash", tone: .neutral)
                }
            }
            if service.notificationsDenied && service.settings.isEnabled {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Bildirimler macOS’ta kapalı. Uyarı alabilmek için Sistem Ayarları’ndan MacPocket bildirimlerine izin ver.", tone: .warning)
                    Button("Bildirim ayarları…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    toggleCard
                    liveCard
                    if !service.recent.isEmpty { recentCard }
                    if !service.settings.ignoredApps.isEmpty { ignoredCard }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onAppear {
            service.setViewing(true)
            Task { await service.refreshAuthorization() }
        }
        .onDisappear { service.setViewing(false) }
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Toggle("Kullanım başladığında bildir", isOn: $service.settings.isEnabled)
                .toggleStyle(.switch)
                .font(.headline)
            Text("MacPocket açıkken arka planda izler. Hiçbir ses ya da görüntü okunmaz; yalnız macOS’un “kullanımda” bilgisine bakılır.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Şu an", icon: "dot.radiowaves.left.and.right")
            deviceRow(.microphone, title: "Mikrofon", symbol: "mic.fill")
            Divider()
            deviceRow(.camera, title: "Kamera", symbol: "camera.fill")
            Text("Kamera için macOS hangi uygulamanın kullandığını bildirmez; bu yüzden uygulama adı gösterilemez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private func deviceRow(_ device: PrivacyDevice, title: LocalizedStringKey, symbol: String) -> some View {
        let active = service.activities.filter { $0.device == device }
        return VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.s) {
                Label(title, systemImage: symbol).font(.headline)
                Spacer(minLength: PocketSpacing.m)
                if active.isEmpty {
                    PocketStatusBadge(text: "Kullanımda değil", systemImage: "checkmark.circle", tone: .neutral)
                } else {
                    PocketStatusBadge(text: "Kullanımda", systemImage: "circle.fill", tone: .critical)
                }
            }
            ForEach(active) { activity in
                HStack(spacing: PocketSpacing.s) {
                    Text(activity.bundleID == nil && activity.appName == nil && device == .microphone
                         ? String(localized: "Bilinmeyen uygulama") : activityTitle(activity))
                        .font(.subheadline)
                    Spacer(minLength: PocketSpacing.m)
                    if let bundleID = activity.bundleID {
                        if service.settings.ignoredApps[bundleID] != nil {
                            Text("Bildirimi kapalı").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Bu uygulama için bildirme") { service.ignore(bundleID: bundleID, name: activity.displayName) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func activityTitle(_ activity: PrivacyActivity) -> String {
        activity.device == .camera ? String(localized: "Bir uygulama") : activity.displayName
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Son etkinlik", icon: "clock")
            ForEach(service.recent) { event in
                HStack(spacing: PocketSpacing.s) {
                    Image(systemName: event.activity.device == .microphone ? "mic.fill" : "camera.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(activityTitle(event.activity)).font(.subheadline)
                    Spacer(minLength: PocketSpacing.m)
                    Text(event.startedAt, style: .time).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var ignoredCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Bildirimi kapalı uygulamalar", icon: "bell.slash")
            ForEach(service.settings.ignoredApps.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }, id: \.key) { entry in
                HStack(spacing: PocketSpacing.s) {
                    Text(entry.value).font(.subheadline)
                    Spacer(minLength: PocketSpacing.m)
                    Button("Tekrar bildir") { service.stopIgnoring(entry.key) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}
