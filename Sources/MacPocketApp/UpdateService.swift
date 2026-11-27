import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle auto-updates. The feed is the latest GitHub release's `appcast.xml`, signed with the project's
/// EdDSA key; checks download only that file and send nothing about the Mac (system profiling is off in
/// Info.plist).
@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    /// Nil when running outside a signed app bundle (`swift run`), where Sparkle can't install anything.
    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    private var subscriptions = Set<AnyCancellable>()

    var isAvailable: Bool { controller != nil }

    override init() {
        let bundled = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = bundled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        super.init()
        guard let updater = controller?.updater else { return }
        lastCheck = updater.lastUpdateCheckDate
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.canCheck = value } }
            .store(in: &subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.lastCheck = value } }
            .store(in: &subscriptions)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue; objectWillChange.send() }
    }
}

/// Settings › Genel › Güncellemeler.
struct UpdateSettingsSection: View {
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        Section {
            if updates.isAvailable {
                Toggle("Güncellemeleri otomatik denetle", isOn: Binding(get: { updates.automaticallyChecks },
                                                                       set: { updates.automaticallyChecks = $0 }))
                Toggle("Güncellemeleri otomatik indir ve kur", isOn: Binding(get: { updates.automaticallyDownloads },
                                                                             set: { updates.automaticallyDownloads = $0 }))
                    .disabled(!updates.automaticallyChecks)
                LabeledContent("Son denetim") {
                    HStack(spacing: PocketSpacing.s) {
                        Text(updates.lastCheck.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "Henüz denetlenmedi"))
                            .foregroundStyle(.secondary)
                        Button("Şimdi Denetle") { updates.checkForUpdates() }.disabled(!updates.canCheck)
                    }
                }
                Text("Denetim yalnız GitHub’daki son sürümün imzalı listesini indirir; bu Mac hakkında bilgi gönderilmez. Güncellemeler kurulmadan önce imzası doğrulanır.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Otomatik güncelleme yalnız paketlenmiş MacPocket uygulamasında çalışır.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } header: { Text("Güncellemeler") }
    }
}
