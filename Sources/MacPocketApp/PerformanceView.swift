import Charts
import MacPocketCore
import SwiftUI

struct PerformanceView: View {
    @ObservedObject var model: PocketModel
    @Environment(\.pocketTint) private var tint
    @AppStorage(PocketDetailLevel.key("performance")) private var level = PocketDetailLevel.defaultValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.xl) {
                PocketPageHeading(title: "Sistem İzleme", subtitle: "İşlemci, bellek, disk ve termal durumun canlı ölçümü.",
                                  icon: "waveform.path.ecg") {
                    HStack(spacing: PocketSpacing.s) {
                        PocketStatusBadge(text: model.paused ? "Duraklatıldı" : "Canlı · \(Int(model.refreshSeconds)) sn",
                                          systemImage: model.paused ? "pause.circle" : "dot.radiowaves.left.and.right",
                                          tone: model.paused ? .warning : .success)
                        PocketDetailLevelSwitch(level: $level)
                    }
                }
                ResourceStrip(model: model)
                cpuChart
                if level == .advanced {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: PocketSpacing.l) { memoryCard; systemCard }
                        VStack(spacing: PocketSpacing.l) { memoryCard; systemCard }
                    }
                    PocketSensorsCard(system: model.system)
                }
                Text("Grafikler yalnız bu oturumda toplanan son \(PocketModel.sampleCapacity) örneği gösterir. Bellek değerleri Activity Monitor’ün “Kullanılan Bellek” hesabıyla aynı bileşenlerden oluşur.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var cpuChart: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("İşlemci kullanımı", icon: "cpu") {
                if let system = model.system, let user = system.cpuUserPercent, let kernel = system.cpuSystemPercent {
                    Text("Kullanıcı \(pocketPercent(user, decimals: true)) · Sistem \(pocketPercent(kernel, decimals: true))")
                        .monospacedDigit()
                }
            }
            if model.samples.count < 2 {
                ContentUnavailableView("Örnekler toplanıyor", systemImage: "chart.xyaxis.line",
                                       description: Text("İlk ölçüm aralığından sonra grafik oluşur."))
                    .frame(height: 220)
            } else {
                let systemSeries = String(localized: "Sistem"), userSeries = String(localized: "Kullanıcı")
                Chart(model.samples) { sample in
                    AreaMark(x: .value(Text("Zaman"), sample.date), y: .value(Text("Kullanım"), sample.cpuSystem))
                        .foregroundStyle(by: .value(Text("Tür"), systemSeries))
                    AreaMark(x: .value(Text("Zaman"), sample.date), y: .value(Text("Kullanım"), sample.cpuUser))
                        .foregroundStyle(by: .value(Text("Tür"), userSeries))
                }
                .chartForegroundStyleScale([
                    userSeries: LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                    systemSeries: LinearGradient(colors: [PocketTheme.brandSecondary.opacity(0.9), PocketTheme.brandSecondary.opacity(0.35)],
                                             startPoint: .top, endPoint: .bottom),
                ])
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { if let number = value.as(Int.self) { Text(verbatim: pocketPercent(Double(number))) } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 220)
                .accessibilityLabel("İşlemci kullanım grafiği")
                .accessibilityValue(model.cpuLabel)
            }
        }
        .pocketCard()
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Bellek", icon: "memorychip") {
                if let system = model.system { Text("\(pocketBytes(system.physicalMemoryBytes)) fiziksel") }
            }
            if let system = model.system {
                let parts = memoryParts(system)
                Chart(parts, id: \.title) { part in
                    BarMark(x: .value(Text("Bayt"), part.bytes), stacking: .normalized)
                        .foregroundStyle(by: .value(Text("Bileşen"), part.title))
                }
                .chartForegroundStyleScale(domain: parts.map(\.title), range: parts.map(\.color))
                .chartXAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
                .accessibilityHidden(true)
                Grid(alignment: .leading, horizontalSpacing: PocketSpacing.l, verticalSpacing: PocketSpacing.s) {
                    ForEach(parts, id: \.title) { part in
                        GridRow {
                            Label { Text(part.title) } icon: { Circle().fill(part.color).frame(width: 8, height: 8) }
                            Text(pocketBytes(part.bytes)).monospacedDigit().gridColumnAlignment(.trailing)
                        }
                    }
                    if let swap = system.swapUsedBytes {
                        Divider().gridCellColumns(2)
                        GridRow {
                            Text("Swap kullanımı").foregroundStyle(.secondary)
                            Text(pocketBytes(swap)).monospacedDigit().gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.callout)
            } else {
                PocketProgressRow(message: "Bellek örneği bekleniyor…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Sistem", icon: "desktopcomputer")
            if let system = model.system {
                Grid(alignment: .leading, horizontalSpacing: PocketSpacing.l, verticalSpacing: PocketSpacing.s) {
                    row("Model", system.hardwareModel)
                    row("Mantıksal çekirdek", "\(system.logicalCPUCount)")
                    row("Açık kalma süresi", pocketDuration(system.uptimeSeconds))
                    row("Termal durum", pocketThermalTitle(system.thermalState))
                    row("Güç kaynağı", pocketPowerSourceTitle(system.power.source))
                    row("Düşük güç modu", system.power.lowPowerMode ? String(localized: "Açık") : String(localized: "Kapalı"))
                    ForEach(system.volumes, id: \.path) { volume in
                        row("\(volume.name)", "\(pocketBytes(volume.availableBytes)) boş / \(pocketBytes(volume.totalBytes))")
                    }
                }
                .font(.callout)
            } else {
                PocketProgressRow(message: "Sistem örneği bekleniyor…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private struct MemoryPart { let title: String; let bytes: UInt64; let color: Color }

    private func memoryParts(_ system: SystemSnapshot) -> [MemoryPart] {
        var parts: [MemoryPart] = []
        if let app = system.appMemoryBytes { parts.append(.init(title: String(localized: "Uygulama belleği"), bytes: app, color: PocketTheme.memory)) }
        parts.append(.init(title: String(localized: "Wired"), bytes: system.wiredMemoryBytes, color: .orange))
        parts.append(.init(title: String(localized: "Sıkıştırılmış"), bytes: system.compressedMemoryBytes, color: .yellow))
        let used = parts.reduce(UInt64(0)) { $0 &+ $1.bytes }
        let cached = system.physicalMemoryBytes > used ? system.physicalMemoryBytes - used : 0
        parts.append(.init(title: String(localized: "Önbellek ve boş"), bytes: cached, color: Color.secondary.opacity(0.35)))
        return parts
    }
}
