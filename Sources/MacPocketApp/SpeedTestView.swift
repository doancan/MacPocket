import MacPocketCore
import SwiftUI
import SystemConfiguration

@MainActor
final class SpeedTestModel: ObservableObject {
    @Published var options: SpeedTestOptions {
        didSet { if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: Self.optionsKey) } }
    }
    @Published private(set) var history: SpeedTestHistory
    @Published private(set) var running = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private static let optionsKey = "MacPocket.speedTest.options"

    static let shared = SpeedTestModel()

    private init() {
        options = UserDefaults.standard.data(forKey: Self.optionsKey)
            .flatMap { try? JSONDecoder().decode(SpeedTestOptions.self, from: $0) } ?? SpeedTestOptions()
        history = SpeedTestHistory.load(from: .standard)
    }

    var latest: SpeedTestResult? { history.results.first }

    func start() {
        guard !running else { return }
        running = true
        startedAt = Date()
        error = nil
        let options = options
        task = Task { [weak self] in
            do {
                let result = try await SpeedTestRunner.run(options)
                self?.finish(result)
            } catch is CancellationError {
                self?.finish(nil)
            } catch {
                self?.finish(nil, error: error.localizedDescription)
            }
        }
    }

    func cancel() { task?.cancel() }

    private func finish(_ result: SpeedTestResult?, error: String? = nil) {
        running = false
        startedAt = nil
        self.error = error
        guard let result else { return }
        history.add(result)
        history.save(to: .standard)
    }

    func remove(_ result: SpeedTestResult) {
        history.remove(result.id)
        history.save(to: .standard)
    }

    func clearHistory() {
        history.clear()
        history.save(to: .standard)
    }

    /// Network interfaces with their user-facing names (Wi-Fi, Ethernet, Thunderbolt Bridge…).
    static func interfaces() -> [(name: String, title: String)] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        return all.compactMap { interface in
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String?, SpeedTestOptions.isValidInterface(name) else { return nil }
            let title = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? name
            return (name, "\(title) (\(name))")
        }
    }
}

/// Tools → Ağ Hız Testi.
struct SpeedTestView: View {
    @ObservedObject private var model = SpeedTestModel.shared
    @State private var interfaces = SpeedTestModel.interfaces()
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ağ Hız Testi",
                              subtitle: "macOS’un yerleşik networkQuality aracıyla indirme, yükleme ve yük altında yanıt verme hızını ölç.",
                              icon: "speedometer") {
                SpeedTestStartButton(model: model)
            }
            if let error = model.error { PocketMessage(error, tone: .warning) }
            if model.running { SpeedTestProgress(startedAt: model.startedAt) }
            tiles
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    options
                    historyCard
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
    }

    private var tiles: some View {
        let latest = model.latest
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: PocketSpacing.m), count: 4), spacing: PocketSpacing.m) {
            PocketMetricTile(title: "İndirme", value: "\(SpeedFormatter.bitRate(latest?.downloadBitsPerSecond))",
                             detail: "\(Self.bestText(model.history.best(\.downloadBitsPerSecond)))", icon: "arrow.down", color: PocketTheme.disk)
            PocketMetricTile(title: "Yükleme", value: "\(SpeedFormatter.bitRate(latest?.uploadBitsPerSecond))",
                             detail: "\(Self.bestText(model.history.best(\.uploadBitsPerSecond)))", icon: "arrow.up", color: PocketTheme.accent)
            PocketMetricTile(title: "Yanıt verme", value: "\(latest?.responsivenessRPM.map { "\(Int($0)) RPM" } ?? "—")",
                             detail: "\(latest?.responsiveness?.title ?? String(localized: "Yük altında dakikadaki gidiş-dönüş"))",
                             icon: "waveform.path.ecg", color: PocketTheme.memory)
            PocketMetricTile(title: "Gecikme", value: "\(latest?.baseRTTMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—")",
                             detail: "\(latest?.interface.map { String(localized: "Arayüz: \($0)") } ?? String(localized: "Boşta gidiş-dönüş süresi"))",
                             icon: "timer", color: PocketTheme.power)
        }
    }

    private static func bestText(_ value: Double?) -> String {
        value.map { String(localized: "En iyi: \(SpeedFormatter.bitRate($0))") } ?? String(localized: "Henüz ölçüm yok")
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Ölçüm seçenekleri", icon: "slider.horizontal.3")
            GlassTabBar(tabs: SpeedTestOptions.Mode.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol) },
                        selection: $model.options.mode)
                .accessibilityLabel("Ölçüm türü")
                .frame(maxWidth: 620)
                .disabled(model.running)
            Text(model.options.mode.detail).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: PocketSpacing.xl) {
                Picker("Arayüz", selection: $model.options.interface) {
                    Text("Otomatik").tag(String?.none)
                    ForEach(interfaces, id: \.name) { interface in Text(interface.title).tag(Optional(interface.name)) }
                }
                .frame(maxWidth: 300)
                    .pocketMenuPicker()
                Picker("Süre sınırı", selection: $model.options.maximumSeconds) {
                    ForEach(SpeedTestOptions.durationChoices, id: \.self) { seconds in
                        Text(seconds.map { "\($0) sn" as LocalizedStringKey } ?? "Otomatik").tag(seconds)
                    }
                }
                .frame(maxWidth: 220)
                    .pocketMenuPicker()
            }
            .disabled(model.running)
            Toggle("iCloud Özel Geçiş üzerinden ölç", isOn: $model.options.usePrivateRelay)
                .disabled(model.running)
            Text("Ölçüm Apple’ın test sunucularına bağlanır ve birkaç yüz megabayt veri aktarabilir; tarifeli bağlantılarda dikkat et.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Geçmiş", icon: "clock") {
                if !model.history.results.isEmpty {
                    Button("Temizle", role: .destructive) { confirmClear = true }
                        .controlSize(.small)
                        .confirmationDialog("Ölçüm geçmişi silinsin mi?", isPresented: $confirmClear) {
                            Button("Sil", role: .destructive) { model.clearHistory() }
                        }
                }
            }
            if model.history.results.isEmpty {
                Text("Henüz ölçüm yok.").foregroundStyle(.secondary)
            } else {
                HStack(spacing: PocketSpacing.xl) {
                    summary("Ortanca indirme", SpeedFormatter.bitRate(model.history.median(\.downloadBitsPerSecond)))
                    summary("Ortanca yükleme", SpeedFormatter.bitRate(model.history.median(\.uploadBitsPerSecond)))
                    summary("Ortanca yanıt verme", model.history.median(\.responsivenessRPM).map { "\(Int($0)) RPM" } ?? "—")
                }
                Divider()
                ForEach(model.history.results) { result in
                    HStack(spacing: PocketSpacing.m) {
                        Text(result.date.formatted(.dateTime.day().month().hour().minute().locale(pocketLocale)))
                            .frame(width: 130, alignment: .leading)
                        Label(SpeedFormatter.bitRate(result.downloadBitsPerSecond), systemImage: "arrow.down").frame(width: 120, alignment: .leading)
                        Label(SpeedFormatter.bitRate(result.uploadBitsPerSecond), systemImage: "arrow.up").frame(width: 120, alignment: .leading)
                        Text(result.responsivenessRPM.map { "\(Int($0)) RPM" } ?? "—").frame(width: 90, alignment: .leading)
                        Text(result.interface ?? "—").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .font(.callout).monospacedDigit()
                    .contextMenu { Button("Sil", role: .destructive) { model.remove(result) } }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private func summary(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }
}

struct SpeedTestStartButton: View {
    @ObservedObject var model: SpeedTestModel

    var body: some View {
        if model.running {
            Button("İptal", role: .cancel) { model.cancel() }
                .controlSize(.large)
        } else {
            Button { model.start() } label: { Label("Ölçümü başlat", systemImage: "play.fill") }
                .buttonStyle(.pocketPrimary)
                .controlSize(.large)
        }
    }
}

/// Elapsed time while networkQuality runs (it reports only at the end).
private struct SpeedTestProgress: View {
    let startedAt: Date?

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            ProgressView().controlSize(.small)
            Text("Ölçülüyor…").font(.callout.weight(.medium))
            if let startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
        }
        .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
    }
}

extension SpeedTestOptions.Mode {
    var title: String {
        switch self {
        case .parallel: String(localized: "Birlikte")
        case .sequential: String(localized: "Sırayla")
        case .downloadOnly: String(localized: "Yalnız indirme")
        case .uploadOnly: String(localized: "Yalnız yükleme")
        }
    }

    var symbol: String {
        switch self {
        case .parallel: "arrow.up.arrow.down"
        case .sequential: "arrow.down.to.line"
        case .downloadOnly: "arrow.down"
        case .uploadOnly: "arrow.up"
        }
    }

    var detail: String {
        switch self {
        case .parallel: String(localized: "İndirme ve yükleme aynı anda ölçülür; gerçek kullanıma en yakın sonuç ve yanıt verme puanı bu modda çıkar.")
        case .sequential: String(localized: "Önce indirme, sonra yükleme ölçülür; her yön boş hatta ayrı ayrı test edilir.")
        case .downloadOnly: String(localized: "Yalnız indirme hızı ölçülür; daha kısa sürer ve daha az veri harcar.")
        case .uploadOnly: String(localized: "Yalnız yükleme hızı ölçülür.")
        }
    }
}
