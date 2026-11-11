import Charts
import MacPocketCore
import SwiftUI

// MARK: - Sleep blockers

struct PowerBlockersPanel: View {
    var center: PowerCenterModel
    @State private var onlyBlockers = true

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            summary
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                PocketSectionHeader("Güç onayları (assertions)", icon: "list.bullet.rectangle") {
                    Toggle("Yalnızca uykuyu engelleyenler", isOn: $onlyBlockers).toggleStyle(.switch).controlSize(.small)
                }
                if let error = center.assertionsError, center.assertions == nil {
                    PocketMessage(error, error: true)
                } else if let report = center.assertions {
                    let rows = (onlyBlockers ? report.sleepBlockers : report.assertions)
                        .sorted { ($0.effect, -($0.ageSeconds ?? 0)) < ($1.effect, -($1.ageSeconds ?? 0)) }
                    if rows.isEmpty {
                        ContentUnavailableView("Uykuyu engelleyen süreç yok", systemImage: "moon.zzz",
                                               description: Text("Mac boşta kaldığında ayarlara göre uyuyabilir."))
                            .frame(maxWidth: .infinity)
                    } else {
                        header
                        Divider()
                        ForEach(rows) { row in
                            assertionRow(row)
                            Divider()
                        }
                    }
                } else {
                    HStack(spacing: PocketSpacing.s) {
                        ProgressView().controlSize(.small)
                        Text("pmset -g assertions okunuyor…").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .pocketCard()
            if let kernel = center.assertions?.kernelAssertions, !kernel.isEmpty {
                VStack(alignment: .leading, spacing: PocketSpacing.m) {
                    PocketSectionHeader("Çekirdek onayları", icon: "cpu")
                    ForEach(kernel) { item in
                        HStack(alignment: .firstTextBaseline) {
                            PocketStatusBadge(text: item.type.isEmpty ? "—" : item.type, tone: .neutral)
                            Text(item.owner).font(.callout)
                            Spacer()
                            Text(item.detail).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Sürücülerin tuttuğu onaylar (USB, ağ ile uyandırma). Genellikle uykuyu engellemez, uyanma kaynağı olabilir.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .pocketCard()
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: PocketSpacing.l) {
            PocketMetricTile(title: "Sistem uykusu", value: center.assertions.map { $0.preventsIdleSystemSleep ? "Engelli" : "Serbest" } ?? "—",
                             detail: "Boşta kalınca otomatik uyku", icon: "moon.fill",
                             color: center.assertions?.preventsIdleSystemSleep == true ? .orange : PocketTheme.disk)
            PocketMetricTile(title: "Ekran uykusu", value: center.assertions.map { $0.preventsIdleDisplaySleep ? "Engelli" : "Serbest" } ?? "—",
                             detail: "Boşta kalınca ekranın kapanması", icon: "display",
                             color: center.assertions?.preventsIdleDisplaySleep == true ? .orange : PocketTheme.disk)
            PocketMetricTile(title: "Engelleyen süreç", value: center.assertions.map { "\(Set($0.sleepBlockers.map(\.pid)).count)" } ?? "—",
                             detail: center.live.map { $0.sleepPreventedBy.isEmpty ? "pmset engel bildirmiyor" : "\($0.sleepPreventedBy.joined(separator: ", "))" } ?? "",
                             icon: "hand.raised.fill", color: PocketTheme.power)
        }
    }

    private var header: some View {
        HStack(spacing: PocketSpacing.m) {
            Text("Süreç").frame(width: 170, alignment: .leading)
            Text("Tür").frame(width: 190, alignment: .leading)
            Text("Ad").frame(maxWidth: .infinity, alignment: .leading)
            Text("Süre").frame(width: 80, alignment: .trailing)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func assertionRow(_ row: PMAssertion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                Circle().fill(color(row.effect)).frame(width: 8, height: 8).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.process).font(.callout.weight(.medium)).lineLimit(1)
                    Text("PID \(row.pid)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(width: 170, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(pmAssertionTypeTitle(row.type)).font(.callout).lineLimit(1)
                Text(row.effect.title).font(.caption2).foregroundStyle(color(row.effect))
            }
            .frame(width: 190, alignment: .leading)
            .help(row.type)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).font(.callout).lineLimit(2).textSelection(.enabled)
                if let timeout = row.timeoutSeconds {
                    Text("\(timeout) sn sonra sona erecek").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.details.joined(separator: "\n"))
            Text(row.ageSeconds.map(age) ?? "—").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, PocketSpacing.xs)
        .background(row.effect.blocksSleep ? color(row.effect).opacity(0.06) : .clear)
        .accessibilityElement(children: .combine)
    }

    private func color(_ effect: PMAssertionEffect) -> Color {
        switch effect {
        case .preventsSystemSleep: .orange
        case .preventsDisplaySleep: .yellow
        case .userActivity: PocketTheme.accent
        case .other: .secondary
        }
    }

    private func age(_ seconds: Int) -> String {
        if seconds < 60 { return String(localized: "\(seconds) sn") }
        return pocketDuration(Double(seconds))
    }
}

// MARK: - Energy

struct PowerEnergyRow: View {
    let process: ProcessEnergyUsage
    let maximum: Double
    var compact = false

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketAppIcon(url: powerAppBundle(for: process.executablePath), size: compact ? 20 : 24)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                HStack {
                    Text(displayName).font(.callout.weight(.medium)).lineLimit(1)
                    if !compact { Text("PID \(process.pid)").font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
                }
                GeometryReader { proxy in
                    Capsule().fill(PocketTheme.power.opacity(0.85))
                        .frame(width: max(2, proxy.size.width * min(1, process.milliwatts / max(maximum, 1))))
                }
                .frame(height: 4)
            }
            Spacer(minLength: PocketSpacing.s)
            if !compact {
                Text(pocketProcessCPU(process.cpuPercent)).frame(width: 64, alignment: .trailing)
                Text(process.wakeupsPerSecond.formatted(.number.precision(.fractionLength(0)).locale(pocketLocale)))
                    .frame(width: 70, alignment: .trailing)
            }
            Text(powerMilliwatts(process.milliwatts)).fontWeight(.semibold).frame(width: 80, alignment: .trailing)
        }
        .font(.callout).monospacedDigit()
        .help(process.executablePath)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayName)
        .accessibilityValue(Text("\(powerMilliwatts(process.milliwatts)), işlemci \(pocketProcessCPU(process.cpuPercent))"))
    }

    private var displayName: String {
        powerAppBundle(for: process.executablePath).map { $0.deletingPathExtension().lastPathComponent }
            .map { $0 == process.name ? $0 : "\($0) · \(process.name)" } ?? process.name
    }
}

struct PowerEnergyPanel: View {
    var center: PowerCenterModel
    @State private var totals: [PowerWattSample] = []
    @State private var showMinor = false
    @State private var visibleCount = Self.pageSize

    private static let pageSize = 12
    private static let chartRowCount = 8
    /// CPU share below which a process is "idle" for this list.
    private static let minorCPUPercent = 0.1
    private static let minorCPULabel = (minorCPUPercent / 100).formatted(.percent.precision(.fractionLength(1)).locale(pocketLocale))

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            if let sample = center.energy {
                let processes = sample.processes.filter { showMinor || $0.cpuPercent >= Self.minorCPUPercent }
                HStack(alignment: .top, spacing: PocketSpacing.l) {
                    topCard(processes)
                    trendCard(sample)
                }
                .fixedSize(horizontal: false, vertical: true)
                list(sample, processes)
            } else if let error = center.energyError {
                PocketMessage(error, error: true)
            } else {
                PocketProgressRow(message: "Enerji sayaçları ölçülüyor… (ilk sonuç birkaç saniye içinde)")
            }
        }
        .onChange(of: center.energy?.capturedAt) { _, _ in
            guard let sample = center.energy else { return }
            totals.append(PowerWattSample(date: sample.capturedAt, watts: sample.totalMilliwatts / 1000))
            if totals.count > 60 { totals.removeFirst(totals.count - 60) }
        }
        .onChange(of: showMinor) { _, _ in visibleCount = Self.pageSize }
    }

    private func topCard(_ processes: [ProcessEnergyUsage]) -> some View {
        let top = Array(processes.prefix(Self.chartRowCount))
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Enerji etkisi", icon: "chart.bar.xaxis") { Text("Ortalama güç") }
            if top.isEmpty {
                Text("Bu aralıkta ölçülebilir enerji kullanımı yok.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(top) { process in
                    PowerEnergyRow(process: process, maximum: top.first?.milliwatts ?? 1, compact: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func trendCard(_ sample: ProcessEnergySample) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Toplam süreç gücü", icon: "waveform.path.ecg") {
                Text(powerMilliwatts(sample.totalMilliwatts))
            }
            if totals.count > 1 {
                Chart(totals) { point in
                    AreaMark(x: .value(Text("Zaman"), point.date), y: .value(Text(verbatim: "W"), point.watts))
                        .foregroundStyle(LinearGradient(colors: [PocketTheme.power.opacity(0.3), PocketTheme.power.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value(Text("Zaman"), point.date), y: .value(Text(verbatim: "W"), point.watts))
                        .foregroundStyle(PocketTheme.power).interpolationMethod(.monotone)
                }
                .chartYAxis { AxisMarks { value in
                    AxisGridLine(); AxisValueLabel { if let watts = value.as(Double.self) { Text(powerWatts(watts)) } }
                } }
                .frame(minHeight: 150, maxHeight: .infinity)
                .accessibilityLabel("Toplam süreç gücü grafiği")
            } else {
                Text("Eğilim birkaç ölçümden sonra görünür.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let system = center.wattHistory.last?.watts {
                PowerFactRow(title: "Tüm sistem (giriş)", value: "\(powerWatts(system))",
                             help: "Ekran, GPU ve çevre birimleri dahil Mac’in çektiği toplam güç")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func list(_ sample: ProcessEnergySample, _ processes: [ProcessEnergyUsage]) -> some View {
        let shown = processes.prefix(visibleCount)
        let hiddenMinor = sample.processes.count - sample.processes.filter { $0.cpuPercent >= Self.minorCPUPercent }.count
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Süreçler", icon: "list.number") {
                HStack(spacing: PocketSpacing.m) {
                    Text("\(Int(sample.interval.rounded())) sn aralık · \(processes.count) süreç")
                    Toggle(isOn: $showMinor) { Text("\(Self.minorCPULabel) altındakileri göster") }
                        .toggleStyle(.switch).controlSize(.small)
                        .help("İşlemci kullanımı çok düşük olan süreçleri de listeler (\(hiddenMinor) süreç gizli).")
                }
            }
            HStack(spacing: PocketSpacing.m) {
                Text("Süreç").frame(maxWidth: .infinity, alignment: .leading)
                Text("İşlemci").frame(width: 64, alignment: .trailing)
                Text("Uyanma/sn").frame(width: 70, alignment: .trailing)
                Text("Güç").frame(width: 80, alignment: .trailing)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            if processes.isEmpty {
                Text("Ölçüm aralığında enerji kullanan süreç yok.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(shown) { process in
                PowerEnergyRow(process: process, maximum: processes.first?.milliwatts ?? 1)
                Divider()
            }
            if processes.count > visibleCount {
                Button("Daha fazla göster (\(processes.count - visibleCount))") { visibleCount += Self.pageSize }
                    .buttonStyle(.pocketSecondary).frame(maxWidth: .infinity)
            } else if visibleCount > Self.pageSize && processes.count > Self.pageSize {
                Button("Daha az göster") { visibleCount = Self.pageSize }
                    .buttonStyle(.pocketSecondary).frame(maxWidth: .infinity)
            }
            PocketMessage("Güç, çekirdeğin süreç başına tuttuğu enerji sayacından (ri_energy_nj) hesaplanır. Sistem süreçlerinin \(sample.unreadableCount) tanesi yönetici izni gerektirdiği için okunamadı; yalnızca senin süreçlerin gösterilir.",
                          tone: .neutral)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }
}

// MARK: - History

struct PowerHistoryPanel: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tümü", sleepWake = "Uyku ve uyanma", display = "Ekran"
        var id: String { rawValue }
        var localizedTitle: LocalizedStringKey {
            switch self {
            case .all: "Tümü"
            case .sleepWake: "Uyku ve uyanma"
            case .display: "Ekran"
            }
        }
    }

    var center: PowerCenterModel
    var model: PocketModel
    @State private var filter = Filter.sleepWake

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            timeline
            localHistory
        }
        // Read the (large) system log once per page visit, as soon as this tab opens.
        .task { if center.logEvents == nil, !center.logLoading { center.loadLog() } }
    }

    private var items: [PowerTimelineItem] {
        PowerTimeline.merge(log: center.logEvents ?? [], local: model.powerHistory).filter { item in
            switch filter {
            case .all: true
            case .sleepWake: [.sleep, .wake, .darkWake, .start, .shutdown, .restart, .failure].contains(item.kind)
            case .display: item.kind == .displayOn || item.kind == .displayOff
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Uyku ve uyanma geçmişi", icon: "moon.stars") {
                HStack(spacing: PocketSpacing.s) {
                    Picker("Filtre", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                        .pocketMenuPicker()
                    Button { center.loadLog() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Sistem güç günlüğünü yeniden oku")
                        .disabled(center.logLoading)
                        .accessibilityLabel("Yenile")
                }
            }
            if center.logLoading {
                PocketProgressRow(message: "Sistem güç günlüğü (pmset -g log) okunuyor; bu birkaç saniye sürebilir…")
            }
            if let error = center.logError { PocketMessage(error, error: true) }
            let rows = items
            let lastDay = rows.filter { $0.date > Date().addingTimeInterval(-86_400) }
            HStack(spacing: PocketSpacing.l) {
                PocketStatusBadge(text: "24 saatte \(lastDay.filter { $0.kind == .sleep }.count) uyku" as LocalizedStringKey, systemImage: "moon.fill", tone: .neutral)
                PocketStatusBadge(text: "\(lastDay.filter { $0.kind == .wake }.count) uyanma" as LocalizedStringKey, systemImage: "sun.max.fill", tone: .neutral)
                PocketStatusBadge(text: "\(lastDay.filter { $0.kind == .darkWake }.count) arka plan uyanması" as LocalizedStringKey, systemImage: "moon.haze", tone: .neutral)
            }
            if rows.isEmpty && !center.logLoading {
                ContentUnavailableView("Kayıtlı olay yok", systemImage: "clock",
                                       description: Text("Mac son açılıştan beri uyumamış olabilir. Uyku olayları burada nedenleriyle listelenir."))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows.prefix(80)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.m) {
                            Image(systemName: icon(item.kind)).foregroundStyle(tint(item.kind)).frame(width: 18)
                                .accessibilityHidden(true)
                            Text(item.date.formatted(.dateTime.locale(pocketLocale).day().month(.abbreviated).hour().minute().second()))
                                .monospacedDigit().frame(width: 150, alignment: .leading)
                            Text(item.kind.title).fontWeight(.medium).frame(width: 150, alignment: .leading)
                            Text(item.detail ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(item.detail ?? "")
                            if let charge = item.chargePercent { Text(verbatim: pocketPercent(Double(charge))).monospacedDigit().foregroundStyle(.secondary) }
                            if item.origin == .local {
                                PocketStatusBadge(text: "MacPocket", tone: .accent)
                            }
                        }
                        .font(.callout)
                        .padding(.vertical, PocketSpacing.s)
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private var localHistory: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Yerel güç kaydı", icon: "clock.arrow.circlepath") { Text("Dakikada bir") }
            if let error = model.powerHistoryError { PocketMessage(error, error: true) }
            let recent = model.powerHistory.suffix(720)
            let charged = recent.filter { $0.chargePercent != nil }
            if model.powerHistory.isEmpty {
                ContentUnavailableView("İlk ölçüm bekleniyor", systemImage: "clock",
                                       description: Text("Güç kaynağı, termal durum ve pil yüzdesi dakikada bir kaydedilir."))
                    .frame(maxWidth: .infinity)
            } else {
                if charged.count > 1 {
                    Chart(Array(charged)) { entry in
                        LineMark(x: .value(Text("Zaman"), entry.date), y: .value(Text("Şarj"), entry.chargePercent ?? 0))
                            .foregroundStyle(PocketTheme.disk).interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 120)
                    .accessibilityLabel("Şarj geçmişi grafiği")
                }
                let thermalCounts = Dictionary(grouping: recent, by: \.thermalState).mapValues(\.count)
                HStack(spacing: PocketSpacing.s) {
                    Text("Son \(recent.count) ölçüm:").font(.callout).foregroundStyle(.secondary)
                    ForEach(thermalCounts.sorted { $0.value > $1.value }, id: \.key) { state, count in
                        PocketStatusBadge(text: "\(pocketThermalTitle(state)) \(count)" as LocalizedStringKey, tone: pocketThermalTone(state))
                    }
                    if recent.contains(where: \.lowPower) {
                        PocketStatusBadge(text: "Düşük güç \(recent.filter(\.lowPower).count)" as LocalizedStringKey, tone: .warning)
                    }
                }
                Text("Kayıt tarihi: \(model.powerHistory.first?.date.formatted(date: .abbreviated, time: .shortened) ?? "—") – \(model.powerHistory.last?.date.formatted(date: .abbreviated, time: .shortened) ?? "—")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func icon(_ kind: PMLogEventKind) -> String {
        switch kind {
        case .sleep: "moon.fill"
        case .wake: "sun.max.fill"
        case .darkWake: "moon.haze.fill"
        case .start: "power"
        case .shutdown: "power.circle"
        case .restart: "arrow.clockwise.circle"
        case .failure: "exclamationmark.triangle.fill"
        case .displayOn: "display"
        case .displayOff: "powersleep"
        }
    }

    private func tint(_ kind: PMLogEventKind) -> Color {
        switch kind {
        case .sleep: .indigo
        case .wake: .orange
        case .darkWake: .purple
        case .failure: .red
        default: .secondary
        }
    }
}
