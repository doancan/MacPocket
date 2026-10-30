import Foundation
import MacPocketCore
import UserNotifications

/// Optional system notifications for low disk space, serious thermal state, critical memory pressure,
/// sustained CPU load and low battery (Settings → Monitoring). Conditions are checked on every monitoring
/// refresh; each alert is sent at most once per hour.
@MainActor
final class PocketAlertNotifier {
    private var limiter = ResourceAlertLimiter()
    private var cpuStreak = SustainedThreshold()

    /// UserNotifications needs a real app bundle; `swift run` builds have none.
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    func evaluate(_ snapshot: SystemSnapshot) {
        let settings = ResourceAlertSettings.load(from: .standard)
        // The streak is tracked even while the alert is off, so turning it on doesn't restart the clock.
        let cpuHigh = cpuStreak.update(snapshot.cpuTotalPercent, threshold: settings.cpuPercent, at: snapshot.capturedAt)
        guard !settings.enabled.isEmpty, Self.isAvailable else { return }
        let reading = ResourceAlertReading(snapshot, cpuHighDuration: cpuHigh)
        let due = limiter.admit(reading.triggered(settings), now: snapshot.capturedAt)
        guard !due.isEmpty else { return }
        let requests = due.map { Self.request(for: $0, reading: reading, settings: settings) }
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            for request in requests { try? await center.add(request) }
        }
    }

    /// Asked when the user turns an alert on. Returns whether notifications are allowed.
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationDenied() async -> Bool {
        guard isAvailable else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private static func request(for kind: ResourceAlertKind, reading: ResourceAlertReading,
                                settings: ResourceAlertSettings) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        switch kind {
        case .lowDisk:
            content.title = String(localized: "Disk alanı azaldı")
            let free = pocketPercent(reading.diskFreePercent ?? 0)
            content.body = String(localized: "Başlangıç diskinde yalnız \(free) boş alan kaldı. Disk Analizi veya Temizlik ile yer açabilirsin.")
        case .thermal:
            content.title = String(localized: "Mac çok ısındı")
            content.body = String(localized: "Termal durum ciddi seviyede; macOS performansı kısabilir. Yoğun işleri azaltmayı dene.")
        case .memoryPressure:
            content.title = String(localized: "Bellek baskısı kritik")
            content.body = String(localized: "Bellek tükenmek üzere. Kullanmadığın uygulamaları kapatmak Mac’i rahatlatır.")
        case .sustainedCPU:
            content.title = String(localized: "İşlemci uzun süredir yoğun")
            content.body = String(localized: "İşlemci kullanımı \(settings.cpuMinutes) dakikadır \(pocketPercent(settings.cpuPercent)) üzerinde. Görev Yöneticisi’nden en çok tüketen süreçlere bakabilirsin.")
        case .lowBattery:
            content.title = String(localized: "Pil azaldı")
            content.body = String(localized: "Pil \(pocketPercent(reading.batteryPercent ?? 0)) seviyesinde. Mac’i prize takmayı unutma.")
        }
        content.sound = .default
        return UNNotificationRequest(identifier: "MacPocket.alert." + kind.rawValue, content: content, trigger: nil)
    }
}

extension ResourceAlertKind {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .lowDisk: "Boş disk alanı azaldığında"
        case .thermal: "Termal durum ciddi olduğunda"
        case .memoryPressure: "Bellek baskısı kritik olduğunda"
        case .sustainedCPU: "İşlemci uzun süre yoğun kaldığında"
        case .lowBattery: "Pil azaldığında"
        }
    }
}
