import AppIntents
import AppKit
import MacPocketCore

/// Shortcuts actions for Disk Röntgeni: read the size of System Data, or free the Safe items that need no
/// password. They run the same scanner and remover as the page; nothing marked Review is ever touched.
struct SystemDataSizeIntent: AppIntent {
    static let title: LocalizedStringResource = "Sistem Verisi Boyutunu Al"
    static let description = IntentDescription("Disk Röntgeni’nin ölçtüğü Sistem Verisi boyutunu ve hemen güvenle boşaltılabilir miktarı verir.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let report = await SystemDataIntentRunner.scan()
        let size = ByteCountFormatter.string(fromByteCount: report.systemDataBytes, countStyle: .file)
        let safe = ByteCountFormatter.string(fromByteCount: report.safeBytes, countStyle: .file)
        return .result(value: Int(report.systemDataBytes),
                       dialog: "Sistem Verisi \(size); bunun \(safe) kadarı güvenle boşaltılabilir.")
    }
}

struct FreeSafeSystemDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Güvenli Sistem Verisini Temizle"
    static let description = IntentDescription("Yalnızca “Güvenli” olan, parola istemeyen ve sahibi uygulaması kapalı kalemleri kaldırır. “İncele” kalemlerine dokunmaz.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let result = await SystemDataIntentRunner.freeSafeItems()
        let text = ByteCountFormatter.string(fromByteCount: result.freedBytes, countStyle: .file)
        return .result(value: Int(result.freedBytes), dialog: "\(result.removedCount) güvenli kalem kaldırıldı; \(text) boşaldı.")
    }
}

/// The app's one Shortcuts provider: page navigation, connection diagnosis and Disk Röntgeni.
struct SystemDataShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenPocketPageIntent(), phrases: ["\(.applicationName) sayfası aç", "\(.applicationName)’te \(\.$page) aç"],
                    shortTitle: "Sayfa Aç", systemImageName: "macwindow")
        AppShortcut(intent: DiagnoseConnectionIntent(), phrases: ["\(.applicationName) ile bağlantıyı tanıla"],
                    shortTitle: "Bağlantıyı Tanıla", systemImageName: "stethoscope")
        AppShortcut(intent: SystemDataSizeIntent(), phrases: ["\(.applicationName) ile Sistem Verisi boyutunu al"],
                    shortTitle: "Sistem Verisi Boyutu", systemImageName: "scope")
        AppShortcut(intent: FreeSafeSystemDataIntent(), phrases: ["\(.applicationName) ile güvenli Sistem Verisini temizle"],
                    shortTitle: "Güvenlileri Temizle", systemImageName: "trash")
    }
}

enum SystemDataIntentRunner {
    @MainActor static func scan(environment: SystemDataEnvironment = SystemDataViewModel.liveEnvironment,
                                hidden: Set<String>? = nil) async -> SystemDataReport {
        let hiddenIDs = hidden ?? Set(UserDefaults.standard.stringArray(forKey: SystemDataViewModel.hiddenKey) ?? [])
        var finished: SystemDataReport?
        for await event in SystemDataScanner(environment: environment).scan(hidden: hiddenIDs) {
            if case .finished(let report) = event { finished = report }
        }
        return finished ?? SystemDataReport(scannedAt: Date(), items: [], totalBytes: 0, freeBytes: 0, purgeableBytes: 0, complete: false)
    }

    /// Removes the Safe items that need no password and whose apps are closed. Everything it touches is
    /// injectable so tests can run it against a fixture instead of this Mac.
    @MainActor static func freeSafeItems(environment: SystemDataEnvironment = SystemDataViewModel.liveEnvironment,
                                         remover: SystemDataRemover = SystemDataViewModel.liveRemover,
                                         mode: RemovalMode = RemovalModePreference.load(),
                                         runningBundleIDs: Set<String>? = nil) async -> (removedCount: Int, freedBytes: Int64) {
        let report = await scan(environment: environment)
        let running = runningBundleIDs ?? Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let items = SystemDataAutoClean.eligible(report.items, runningBundleIDs: running, home: environment.home,
                                                 temporaryDirectory: environment.temporaryDirectory)
        let outcomes = await remover.remove(items, mode: mode, administratorPrompt: String(localized: "MacPocket yönetici izni istiyor."))
        let done = outcomes.filter(\.succeeded)
        return (done.count, done.reduce(Int64(0)) { $0 + $1.sizeBytes })
    }
}
