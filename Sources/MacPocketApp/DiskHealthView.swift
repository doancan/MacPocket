import MacPocketCore
import SwiftUI

@MainActor
final class DiskHealthModel: ObservableObject {
    @Published private(set) var readings: [DiskHealthReading] = []
    @Published private(set) var loaded = false
    @Published private(set) var refreshing = false
    @Published private(set) var updatedAt: Date?

    func refresh() async {
        guard !refreshing, !Task.isCancelled else { return }
        refreshing = true
        defer { refreshing = false }
        let latest = await Task.detached(priority: .utility) { DiskHealthReader.read() }.value
        guard !Task.isCancelled else { return }
        readings = latest
        updatedAt = Date()
        loaded = true
    }

    /// SMART counters move slowly; temperature is the only value worth watching live.
    func run() async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
        }
    }
}

struct DiskHealthView: View {
    @StateObject private var model = DiskHealthModel()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Disk Sağlığı",
                              subtitle: "SSD’nin kendi bildirdiği yıpranma, yazılan veri, sıcaklık ve hata sayaçları (NVMe SMART).",
                              icon: "internaldrive.fill") {
                Button { Task { await model.refresh() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if model.refreshing { PocketProgressRow(message: "Disk sağlığı okunuyor…") }
                    if model.readings.isEmpty, model.loaded {
                        ContentUnavailableView("SMART verisi okunamadı", systemImage: "internaldrive",
                                               description: Text("Bu Mac’teki diskler NVMe SMART bilgisi yayınlamıyor."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .pocketCard()
                    } else {
                        ForEach(model.readings) { DiskHealthCard(reading: $0) }
                    }
                    if let updatedAt = model.updatedAt {
                        Text("Son okuma: \(updatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Değerler diskin kendi ölçümleridir ve 10 saniyede bir okunur. Harici USB kutuları SMART verisini genellikle iletmez; bu yüzden yalnız dahili ve doğrudan bağlı NVMe diskler listelenir.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .task { await model.run() }
    }
}

private struct DiskHealthCard: View {
    let reading: DiskHealthReading
    private var health: NVMeHealth { reading.health }
    private var assessment: DiskHealthAssessment { health.assessment }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(alignment: .center, spacing: PocketSpacing.m) {
                Image(systemName: "internaldrive").font(.title2).foregroundStyle(tone.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: reading.model).font(.headline)
                    Text(verbatim: details).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PocketStatusBadge(text: assessment.title, systemImage: tone.symbol, tone: tone)
            }
            lifeBar
            if !assessment.findings.isEmpty {
                VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                    ForEach(assessment.findings, id: \.self) { PocketMessage($0, tone: tone) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: PocketSpacing.m)], alignment: .leading,
                      spacing: PocketSpacing.m) {
                metric("Sıcaklık", health.temperatureCelsius.map { "\($0.formatted(.number.precision(.fractionLength(0))))°C" } ?? "—",
                       symbol: "thermometer.medium")
                metric("Yazılan veri", bytes(health.bytesWritten), symbol: "square.and.pencil")
                metric("Okunan veri", bytes(health.bytesRead), symbol: "book")
                metric("Açık kalma süresi", String(localized: "\(health.powerOnHours.formatted()) saat"), symbol: "clock")
                metric("Açılış sayısı", health.powerCycles.formatted(), symbol: "power")
                metric("Beklenmedik kapanma", health.unsafeShutdowns.formatted(), symbol: "bolt.slash")
                metric("Yedek blok", "%\(health.availableSpare)", symbol: "square.stack.3d.up")
                metric("Veri hatası", health.mediaErrors.formatted(), symbol: "exclamationmark.triangle",
                       tint: health.mediaErrors > 0 ? .orange : .secondary)
            }
        }
        .pocketCard()
    }

    private var lifeBar: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            HStack {
                Text("Kalan ömür").font(.callout.weight(.semibold))
                Spacer()
                Text(verbatim: "%\(health.lifeRemaining)").font(.title3.weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: Double(health.lifeRemaining), total: 100).tint(tone.color)
            Text("Üreticinin öngördüğü yazma ömrünün %\(health.percentageUsed) kadarı kullanıldı. Bu değer dolduktan sonra da disk genellikle çalışmaya devam eder, ama yedeğini güncel tut.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var details: String {
        [reading.capacityBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) },
         reading.firmware.map { String(localized: "Yazılım \($0)") }].compactMap { $0 }.joined(separator: " · ")
    }

    private var tone: PocketTone {
        switch assessment.level {
        case .good: .success
        case .attention: .warning
        case .critical: .critical
        }
    }

    private func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, Double(Int64.max))), countStyle: .decimal)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, symbol: String, tint: Color = .secondary) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: value).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
    }
}
