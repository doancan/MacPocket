import AppKit
import Charts
import MacPocketCore
import SwiftUI

// MARK: - Building blocks

/// Dense inset surface used inside popovers (lighter than `pocketCard`, no shadow).
private struct MenuBarSection: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PocketSpacing.s + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous).strokeBorder(PocketTheme.line, lineWidth: 0.5)
            }
    }
}

extension View {
    fileprivate func menuBarSection() -> some View { modifier(MenuBarSection()) }
}

private struct ModuleHeader<Trailing: View>: View {
    let module: MenuBarModule
    let value: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.s + 2) {
            PocketIconTile(symbol: module.symbol, tint: module.tint, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: PocketSpacing.s)
            VStack(alignment: .trailing, spacing: 2) { trailing() }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(module.title): \(value). \(subtitle)")
    }
}

private struct InfoRow: View {
    let title: LocalizedStringKey
    let value: String
    var dot: Color?

    var body: some View {
        HStack(spacing: PocketSpacing.xs + 2) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: PocketSpacing.s)
            Text(value).monospacedDigit().foregroundStyle(.primary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey
    var trailing: String?
    var body: some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Spacer()
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Horizontal capacity bar; the fill color turns orange/red as it approaches full.
private struct CapacityBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient)
                    .frame(width: max(height, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var color: Color { fraction > 0.95 ? .red : fraction > 0.85 ? .orange : tint }
}

/// Stacked segments (e.g. memory composition).
private struct SegmentBar: View {
    let segments: [(value: Double, color: Color)]
    var body: some View {
        GeometryReader { proxy in
            let total = max(1, segments.reduce(0) { $0 + $1.value })
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle().fill(segment.color.gradient)
                        .frame(width: max(0, proxy.size.width * CGFloat(segment.value / total) - 1))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Compact time-series chart for the popovers.
private struct HistoryChart: View {
    struct Series { let name: String; let color: Color; let values: [(Date, Double)] }
    let series: [Series]
    var ceiling: Double?
    var stacked = false
    var height: CGFloat = 64
    var axisLabel: (Double) -> String = { MenuBarFormatter.percent($0, decimals: false) }

    var body: some View {
        let points = series.flatMap { item in item.values.map { (item.name, $0.0, $0.1) } }
        if points.count < 2 {
            Text("Örnekler toplanıyor…")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: height)
        } else {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Zaman", point.1), y: .value("Değer", point.2),
                             stacking: stacked ? .standard : .unstacked)
                        .foregroundStyle(by: .value("Seri", point.0))
                        .interpolationMethod(.monotone)
                        .opacity(stacked ? 0.85 : 0.35)
                    if !stacked {
                        LineMark(x: .value("Zaman", point.1), y: .value("Değer", point.2))
                            .foregroundStyle(by: .value("Seri", point.0))
                            .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...max(ceiling ?? 0, (points.map(\.2).max() ?? 0) * 1.1, 1))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { if let number = value.as(Double.self) { Text(axisLabel(number)).font(.system(size: 8)) } }
                }
            }
            .chartLegend(series.count > 1 ? .visible : .hidden)
            .chartLegend(position: .top, alignment: .leading, spacing: 4)
            .frame(height: height)
            .accessibilityHidden(true)
        }
    }
}

private struct TopProcessList: View {
    enum Metric { case cpu, memory }
    let processes: [ProcessEntry]
    let metric: Metric

    var body: some View {
        let sorted: [ProcessEntry] = switch metric {
        case .cpu: Array(processes.filter(\.cpuSampleAvailable).sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        case .memory: Array(processes.filter(\.memorySampleAvailable).sorted { $0.residentBytes > $1.residentBytes }.prefix(5))
        }
        VStack(alignment: .leading, spacing: PocketSpacing.xs + 1) {
            SectionTitle(title: metric == .cpu ? "En çok CPU kullananlar" : "En çok bellek kullananlar")
            if sorted.isEmpty {
                HStack(spacing: PocketSpacing.s) {
                    ProgressView().controlSize(.mini)
                    Text("Süreçler ölçülüyor…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(sorted) { process in
                    HStack(spacing: PocketSpacing.s) {
                        ProcessIcon(command: process.command)
                        Text(process.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: PocketSpacing.s)
                        Text(value(process)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func value(_ process: ProcessEntry) -> String {
        switch metric {
        case .cpu: pocketProcessCPU(process.cpuPercent)
        case .memory: MenuBarFormatter.bytes(Double(process.residentBytes), binary: MenuBarSettingsStore.shared.preferences.binaryUnits)
        }
    }
}

/// App icon when the executable lives inside an app bundle, otherwise a generic glyph.
private struct ProcessIcon: View {
    let command: String
    var body: some View {
        if let range = command.range(of: ".app/") {
            PocketAppIcon(url: URL(fileURLWithPath: String(command[..<range.lowerBound]) + ".app"), size: 16)
        } else {
            Image(systemName: "gearshape.2").font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 16, height: 16).accessibilityHidden(true)
        }
    }
}

// MARK: - Module views

/// Detail view for one module, as shown in a popover (tab content or a separate item's popover):
/// the module's name with its own Temel / Gelişmiş switch, then the content for that level.
struct MenuBarModuleDetail: View {
    let module: MenuBarModule
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    let binaryUnits: Bool
    @AppStorage private var level: PocketDetailLevel

    init(module: MenuBarModule, model: PocketModel, history: MenuBarHistory, binaryUnits: Bool) {
        self.module = module
        self.model = model
        self.history = history
        self.binaryUnits = binaryUnits
        _level = AppStorage(wrappedValue: .defaultValue, PocketDetailLevel.key("menubar.\(module.rawValue)"))
    }

    var body: some View {
        let advanced = level == .advanced
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            HStack {
                Text(module.title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: PocketSpacing.s)
                if module != .weather && module != .aiUsage { PocketDetailLevelSwitch(level: $level).controlSize(.small) }
            }
            switch module {
            case .cpu: CPUDetail(model: model, history: history, advanced: advanced)
            case .gpu: GPUDetail(model: model, history: history, binary: binaryUnits, advanced: advanced)
            case .memory: MemoryDetail(model: model, history: history, binary: binaryUnits, advanced: advanced)
            case .disk: DiskDetail(model: model, history: history, binary: binaryUnits, advanced: advanced)
            case .network: NetworkDetail(model: model, history: history, binary: binaryUnits, advanced: advanced)
            case .power: PowerDetail(model: model, advanced: advanced)
            case .weather: WeatherDetail()
            case .aiUsage: AIUsageDetailView()
            }
        }
    }
}

private func percentText(_ value: Double?, decimals: Bool = false) -> String {
    value.map { MenuBarFormatter.percent($0, decimals: decimals) } ?? "—"
}

private struct CPUDetail: View {
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    let advanced: Bool
    private let module = MenuBarModule.cpu

    var body: some View {
        let system = model.system
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            ModuleHeader(module: module, value: percentText(system?.cpuTotalPercent, decimals: true),
                         subtitle: cpuSubtitle(system)) {
                Text("Kullanıcı \(percentText(system?.cpuUserPercent, decimals: true))")
                Text("Sistem \(percentText(system?.cpuSystemPercent, decimals: true))")
            }
            HistoryChart(series: [
                .init(name: String(localized: "Sistem"), color: PocketTheme.brandSecondary, values: history.samples.compactMap { s in s.cpuSystem.map { (s.date, $0) } }),
                .init(name: String(localized: "Kullanıcı"), color: module.tint, values: history.samples.compactMap { s in s.cpuUser.map { (s.date, $0) } }),
            ], ceiling: 100, stacked: true)
            .menuBarSection()

            if advanced, let cores = system?.cpuCorePercents, !cores.isEmpty {
                VStack(alignment: .leading, spacing: PocketSpacing.xs + 2) {
                    SectionTitle(title: "Çekirdekler", trailing: "\(cores.count)")
                    HStack(alignment: .bottom, spacing: cores.count > 16 ? 1.5 : 3) {
                        ForEach(Array(cores.enumerated()), id: \.offset) { _, value in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.primary.opacity(0.08))
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(LinearGradient(colors: [module.tint, PocketTheme.brandSecondary], startPoint: .bottom, endPoint: .top))
                                    .frame(height: max(2, 40 * CGFloat(value / 100)))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Çekirdek kullanımı")
                    .accessibilityValue(cores.enumerated().map { index, value in
                        let number = index + 1, text = percentText(value)
                        return String(localized: "Çekirdek \(number): \(text)")
                    }.joined(separator: ", "))
                }
                .menuBarSection()
            }

            if advanced {
                VStack(spacing: PocketSpacing.xs + 1) {
                    InfoRow(title: "Yük ortalaması", value: system?.loadAverages.map { values in
                        values.map { MenuBarFormatter.number($0, fractionDigits: 2) }.joined(separator: "  ")
                    } ?? "—")
                    InfoRow(title: "Çalışma süresi", value: system.map { pocketDuration($0.uptimeSeconds) } ?? "—")
                    InfoRow(title: "Mantıksal çekirdek", value: system.map { "\($0.logicalCPUCount)" } ?? "—")
                }
                .menuBarSection()
            }

            TopProcessList(processes: model.processes, metric: .cpu).menuBarSection()
        }
    }

    private func cpuSubtitle(_ system: SystemSnapshot?) -> String {
        let user = percentText(system?.cpuUserPercent), kernel = percentText(system?.cpuSystemPercent)
        return String(localized: "Kullanıcı \(user), Sistem \(kernel)")
    }
}

private struct GPUDetail: View {
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    let binary: Bool
    let advanced: Bool
    private let module = MenuBarModule.gpu

    var body: some View {
        let gpu = model.system?.gpu
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            ModuleHeader(module: module, value: percentText(gpu?.utilizationPercent, decimals: true),
                         subtitle: gpu?.model ?? String(localized: "Grafik işlemci")) {
                if let renderer = gpu?.rendererPercent { Text("İşleyici \(percentText(renderer))") }
                if let tiler = gpu?.tilerPercent { Text("Döşeyici \(percentText(tiler))") }
            }
            if gpu == nil {
                Text("Bu Mac grafik işlemci istatistiği yayınlamıyor.").font(.callout).foregroundStyle(.secondary).menuBarSection()
            } else {
                HistoryChart(series: [
                    .init(name: String(localized: "Kullanım"), color: module.tint, values: history.samples.compactMap { s in s.gpu.map { (s.date, $0) } }),
                    .init(name: String(localized: "İşleyici"), color: PocketTheme.brandSecondary, values: history.samples.compactMap { s in s.gpuRenderer.map { (s.date, $0) } }),
                ], ceiling: 100, height: 72)
                .menuBarSection()
                VStack(alignment: .leading, spacing: PocketSpacing.xs + 2) {
                    SectionTitle(title: "Bellek", trailing: gpu?.memoryInUseBytes.map { MenuBarFormatter.bytes(Double($0), binary: binary) })
                    if let used = gpu?.memoryInUseBytes, let total = model.system?.physicalMemoryBytes, total > 0 {
                        CapacityBar(fraction: Double(used) / Double(total), tint: module.tint)
                        Text("Birleşik belleğin \(percentText(Double(used) / Double(total) * 100)) kadarı grafik işlemcide.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .menuBarSection()
                if advanced {
                    VStack(spacing: PocketSpacing.xs + 1) {
                        InfoRow(title: "Model", value: gpu?.model ?? "—")
                        InfoRow(title: "GPU çekirdeği", value: gpu?.coreCount.map { "\($0)" } ?? "—")
                        InfoRow(title: "İşleyici (fragment)", value: percentText(gpu?.rendererPercent))
                        InfoRow(title: "Döşeyici (geometri)", value: percentText(gpu?.tilerPercent))
                    }
                    .menuBarSection()
                }
            }
        }
    }
}

private struct MemoryDetail: View {
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    let binary: Bool
    let advanced: Bool
    private let module = MenuBarModule.memory

    private func bytes(_ value: UInt64?) -> String {
        value.map { MenuBarFormatter.bytes(Double($0), binary: binary) } ?? "—"
    }

    var body: some View {
        let system = model.system
        let total = system?.physicalMemoryBytes ?? 0
        let used = system?.usedMemoryBytes
        let fraction = used.map { Double($0) / Double(max(1, total)) }
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            ModuleHeader(module: module, value: percentText(fraction.map { $0 * 100 }),
                         subtitle: String(localized: "\(bytes(used)) / \(bytes(total)) kullanılıyor")) {
                Text("\(bytes(used)) kullanılıyor")
                Text("\(bytes(total)) toplam")
            }

            let (pressureTitle, pressureTone) = pressure(system?.memoryPressureLevel)
            VStack(alignment: .leading, spacing: PocketSpacing.xs + 2) {
                HStack {
                    SectionTitle(title: "Bellek baskısı")
                    PocketStatusBadge(text: pressureTitle, tone: pressureTone)
                }
                CapacityBar(fraction: (system?.memoryPressurePercent ?? 0) / 100,
                            tint: pressureTone == .neutral ? module.tint : pressureTone.color)
            }
            .menuBarSection()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bellek baskısı")
            .accessibilityValue("\(pressureTitle), \(percentText(system?.memoryPressurePercent))")

            if advanced {
                VStack(alignment: .leading, spacing: PocketSpacing.xs + 1) {
                    let app = Double(system?.appMemoryBytes ?? 0), wired = Double(system?.wiredMemoryBytes ?? 0)
                    let compressed = Double(system?.compressedMemoryBytes ?? 0), cached = Double(system?.cachedFilesBytes ?? 0)
                    SegmentBar(segments: [(app, module.tint), (wired, .orange), (compressed, .yellow), (cached, .teal),
                                          (max(0, Double(total) - app - wired - compressed - cached), .clear)])
                        .padding(.bottom, 2)
                    InfoRow(title: "Uygulama belleği", value: bytes(system?.appMemoryBytes), dot: module.tint)
                    InfoRow(title: "Kalıcı bellek", value: bytes(system?.wiredMemoryBytes), dot: .orange)
                    InfoRow(title: "Sıkıştırılmış", value: bytes(system?.compressedMemoryBytes), dot: .yellow)
                    InfoRow(title: "Önbellekteki dosyalar", value: bytes(system?.cachedFilesBytes), dot: .teal)
                    InfoRow(title: "Kullanılan takas alanı", value: swap(system))
                }
                .menuBarSection()
            }

            HistoryChart(series: [.init(name: String(localized: "Kullanılan"), color: module.tint,
                                        values: history.samples.compactMap { s in s.memoryFraction.map { (s.date, $0 * 100) } })],
                         ceiling: 100)
                .menuBarSection()

            TopProcessList(processes: model.processes, metric: .memory).menuBarSection()
        }
    }

    private func swap(_ system: SystemSnapshot?) -> String {
        guard let used = system?.swapUsedBytes else { return "—" }
        guard let total = system?.swapTotalBytes, total > 0 else { return bytes(used) }
        return "\(bytes(used)) / \(bytes(total))"
    }

    private func pressure(_ level: Int?) -> (String, PocketTone) {
        switch level {
        case 1: (String(localized: "Normal"), .success)
        case 2: (String(localized: "Uyarı"), .warning)
        case 4: (String(localized: "Kritik"), .critical)
        default: (String(localized: "Bilinmiyor"), .neutral)
        }
    }
}

private struct DiskDetail: View {
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    let binary: Bool
    let advanced: Bool
    private let module = MenuBarModule.disk

    var body: some View {
        let system = model.system
        let volumes = system?.volumes ?? []
        let startup = volumes.first { $0.path == "/" } ?? volumes.first
        let read = system?.diskIO?.readBytesPerSecond, write = system?.diskIO?.writeBytesPerSecond
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            ModuleHeader(module: module,
                         value: startup.map { volume in
                             let free = MenuBarFormatter.bytes(Double(volume.availableBytes), binary: binary)
                             return String(localized: "\(free) boş")
                         } ?? "—",
                         subtitle: startup?.name ?? "") {
                Label(MenuBarFormatter.rate(read, binary: binary), systemImage: "arrow.down.doc").labelStyle(.titleAndIcon)
                Label(MenuBarFormatter.rate(write, binary: binary), systemImage: "arrow.up.doc").labelStyle(.titleAndIcon)
            }

            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                SectionTitle(title: "Birimler", trailing: "\(volumes.count)")
                if volumes.isEmpty {
                    Text("Bağlı disk bulunamadı.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(volumes, id: \.path) { volume in
                    let total = Double(max(1, volume.totalBytes)), free = Double(max(0, volume.availableBytes))
                    let usedFraction = min(1, max(0, (total - free) / total))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: volume.path == "/" ? "internaldrive.fill" : "externaldrive.fill")
                                .foregroundStyle(module.tint).font(.caption)
                            Text(volume.name).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text(percentText(usedFraction * 100)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        }
                        CapacityBar(fraction: usedFraction, tint: module.tint)
                        Text("\(MenuBarFormatter.bytes(free, binary: binary)) boş · \(MenuBarFormatter.bytes(total, binary: binary)) toplam")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(volume.name)
                    .accessibilityValue("\(percentText(usedFraction * 100)) dolu, \(MenuBarFormatter.bytes(free, binary: binary)) boş")
                }
            }
            .menuBarSection()

            if advanced {
                VStack(alignment: .leading, spacing: PocketSpacing.xs + 2) {
                    SectionTitle(title: "Etkinlik")
                    HistoryChart(series: [
                        .init(name: String(localized: "Okuma"), color: module.tint, values: history.samples.compactMap { s in s.diskRead.map { (s.date, $0) } }),
                        .init(name: String(localized: "Yazma"), color: .orange, values: history.samples.compactMap { s in s.diskWrite.map { (s.date, $0) } }),
                    ], axisLabel: { MenuBarFormatter.rate($0, binary: binary) })
                    InfoRow(title: "Okuma", value: MenuBarFormatter.rate(read, binary: binary), dot: module.tint)
                    InfoRow(title: "Yazma", value: MenuBarFormatter.rate(write, binary: binary), dot: .orange)
                }
                .menuBarSection()
            }
        }
    }
}

private struct NetworkDetail: View {
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    let binary: Bool
    let advanced: Bool
    private let module = MenuBarModule.network

    var body: some View {
        let network = model.system?.network
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            HStack(spacing: PocketSpacing.s) {
                rate(title: "Alma", symbol: "arrow.down", value: network?.receivedBytesPerSecond, color: module.tint)
                rate(title: "Gönderme", symbol: "arrow.up", value: network?.sentBytesPerSecond, color: .pink)
            }

            HistoryChart(series: [
                .init(name: String(localized: "Alma"), color: module.tint, values: history.samples.compactMap { s in s.networkDown.map { (s.date, $0) } }),
                .init(name: String(localized: "Gönderme"), color: .pink, values: history.samples.compactMap { s in s.networkUp.map { (s.date, $0) } }),
            ], height: 76, axisLabel: { MenuBarFormatter.rate($0, binary: binary) })
            .menuBarSection()

            connectionStatus(model.system?.connectivity).menuBarSection()

            if advanced {
                VStack(spacing: PocketSpacing.xs + 1) {
                    InfoRow(title: "Birincil arayüz", value: network?.primaryInterface ?? String(localized: "Bağlantı yok"))
                    InfoRow(title: "Yerel IP adresi", value: network?.localIPv4 ?? "—")
                    InfoRow(title: "Bu oturumda alınan", value: network.map { MenuBarFormatter.bytes(Double($0.totalReceivedBytes), binary: binary) } ?? "—")
                    InfoRow(title: "Bu oturumda gönderilen", value: network.map { MenuBarFormatter.bytes(Double($0.totalSentBytes), binary: binary) } ?? "—")
                }
                .menuBarSection()

                Label("Dış IP adresi gizlilik nedeniyle sorgulanmaz. Gecikme ölçümü yalnız menü çubuğunda ping seçiliyken 1.1.1.1’e tek paket gönderir.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func connectionStatus(_ connectivity: ConnectivitySnapshot?) -> some View {
        VStack(spacing: PocketSpacing.xs + 1) {
            let online = connectivity?.online
            InfoRow(title: "İnternet", value: online == nil ? "—" : online == true ? String(localized: "Bağlı") : String(localized: "Bağlantı yok"),
                    dot: online == nil ? nil : online == true ? PocketTheme.disk : .red)
            InfoRow(title: "Bağlantı türü", value: linkTitle(connectivity?.link))
            if let rssi = connectivity?.wifiRSSI {
                InfoRow(title: "Wi-Fi sinyali", value: "\(rssi) dBm · \(WiFiSignalQuality(rssi: rssi).title)")
            }
            InfoRow(title: "VPN", value: connectivity?.vpnActive == true ? String(localized: "Bağlı") : String(localized: "Kapalı"),
                    dot: connectivity?.vpnActive == true ? PocketTheme.disk : nil)
            if let connectivity, connectivity.pingMilliseconds != nil || connectivity.pingFailed {
                InfoRow(title: "Gecikme (1.1.1.1)", value: connectivity.pingMilliseconds.map { MenuBarFormatter.number($0, fractionDigits: 0) + " ms" }
                        ?? String(localized: "Yanıt yok"))
            }
        }
    }

    private func linkTitle(_ link: ConnectivitySnapshot.Link?) -> String {
        switch link ?? ConnectivitySnapshot.Link.none {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .other: String(localized: "Diğer")
        case .none: String(localized: "Yok")
        }
    }

    private func rate(title: LocalizedStringKey, symbol: String, value: Double?, color: Color) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(MenuBarFormatter.rate(value, binary: binary))
                    .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .menuBarSection()
        .accessibilityElement(children: .combine)
    }
}

/// One fan: a spinning glyph, its speed and how far it is toward its maximum.
private struct FanRow: View {
    let number: Int
    let fan: FanSnapshot
    let tint: Color
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        let speed = MenuBarFormatter.number(fan.rpm, fractionDigits: 0) + " " + MenuBarFormatter.rpmUnit
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            HStack(spacing: PocketSpacing.xs + 2) {
                Image(systemName: "fan")
                    .foregroundStyle(tint)
                    .modifier(FanSpin(active: !reduceMotion && fan.rpm > 0))
                Text("Fan \(number)").foregroundStyle(.secondary)
                Spacer(minLength: PocketSpacing.s)
                Text(speed).monospacedDigit()
                if let fraction = fan.fraction {
                    Text(percentText(fraction * 100)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
            .font(.callout)
            CapacityBar(fraction: fan.fraction ?? 0, tint: tint, height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Fan \(number)"))
        .accessibilityValue(fan.fraction.map { Text("\(speed), azami hızın \(percentText($0 * 100))") }
                            ?? Text(speed))
    }
}

/// Continuous rotation of the fan glyph.
private struct FanSpin: ViewModifier {
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        content.symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: active)
    }
}

private struct PowerDetail: View {
    var model: PocketModel
    let advanced: Bool
    private let module = MenuBarModule.power

    var body: some View {
        let system = model.system
        let power = system?.power
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            if let power, power.batteryPresent {
                HStack(spacing: PocketSpacing.m) {
                    ZStack {
                        PocketRing(fraction: (power.chargePercent ?? 0) / 100, color: batteryColor(power), lineWidth: 6)
                        Image(systemName: MenuBarRenderer.symbol(for: .power, snapshot: system))
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(batteryColor(power))
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pil").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(percentText(power.chargePercent))
                            .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(batteryStatus(power)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .menuBarSection()
                .accessibilityElement(children: .combine)
            } else {
                ModuleHeader(module: module, value: pocketPowerSourceTitle(power?.source), subtitle: String(localized: "Pil yok")) {
                    EmptyView()
                }
            }

            VStack(spacing: PocketSpacing.xs + 1) {
                InfoRow(title: "Güç kaynağı", value: pocketPowerSourceTitle(power?.source))
                HStack {
                    Text("Termal durum").foregroundStyle(.secondary)
                    Spacer()
                    PocketStatusBadge(text: pocketThermalTitle(system?.thermalState), tone: pocketThermalTone(system?.thermalState))
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                if advanced {
                    InfoRow(title: "Düşük güç modu", value: power.map { $0.lowPowerMode ? String(localized: "Açık") : String(localized: "Kapalı") } ?? "—")
                    if let watts = system?.systemPowerWatts { InfoRow(title: "Sistem gücü", value: powerWatts(watts)) }
                    if let watts = system?.powerInputWatts { InfoRow(title: "DC giriş gücü", value: powerWatts(watts)) }
                }
            }
            .menuBarSection()

            if advanced, let readings = system?.temperatures {
                temperatures(readings).menuBarSection()
            }

            if advanced, let fans = system?.fans, !fans.isEmpty {
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    SectionTitle(title: "Fanlar")
                    ForEach(Array(fans.enumerated()), id: \.offset) { index, fan in
                        FanRow(number: index + 1, fan: fan, tint: module.tint)
                    }
                }
                .menuBarSection()
            }

            keepAwake.menuBarSection()
        }
    }

    private func temperatures(_ readings: [TemperatureReading]) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs + 1) {
            SectionTitle(title: "Sıcaklıklar", trailing: String(localized: "\(readings.count) sensör"))
            ForEach(TemperatureSummary.groups(readings)) { summary in
                let maximum = pocketCelsius(summary.maximum), average = pocketCelsius(summary.average)
                InfoRow(title: "\(summary.group.title)",
                        value: summary.count == 1 ? maximum : String(localized: "en yüksek \(maximum) · ort. \(average)"))
            }
            DisclosureGroup("Tüm sensörler") {
                PocketRawSensorList(readings: readings).padding(.top, PocketSpacing.xs)
            }
            .font(.callout)
        }
    }

    @ViewBuilder private var keepAwake: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            SectionTitle(title: "Uyanık tut")
            if let session = model.awakeSession, session.active {
                HStack(spacing: PocketSpacing.s) {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(module.tint)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Mac uyanık tutuluyor").font(.callout.weight(.medium))
                        if let end = session.endsAt {
                            Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        } else {
                            Text("Süresiz").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Durdur", role: .destructive) { Task { await model.stopAwake() } }
                        .controlSize(.small)
                }
            } else {
                HStack(spacing: PocketSpacing.xs + 2) {
                    awakeButton("30 dk", spoken: "30 dk uyanık tut", seconds: 1800)
                    awakeButton("1 sa", spoken: "1 sa uyanık tut", seconds: 3600)
                    awakeButton("2 sa", spoken: "2 sa uyanık tut", seconds: 7200)
                    awakeButton("Süresiz", spoken: "Süresiz uyanık tut", seconds: nil)
                }
            }
            if let error = model.awakeError {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func awakeButton(_ title: LocalizedStringKey, spoken: LocalizedStringKey, seconds: Double?) -> some View {
        Button { Task { await model.startAwake(duration: seconds) } } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        // The popover is already glass on macOS 26; a glass button here would be glass on glass.
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(spoken)
    }

    private func batteryColor(_ power: PowerSnapshot) -> Color {
        if power.isCharging == true { return PocketTheme.disk }
        switch power.chargePercent ?? 100 {
        case ..<10: return .red
        case ..<20: return .orange
        default: return power.lowPowerMode ? .yellow : PocketTheme.disk
        }
    }

    private func batteryStatus(_ power: PowerSnapshot) -> String {
        let state: String
        if power.isCharging == true { state = String(localized: "Şarj oluyor") }
        else if power.source == "AC Power" {
            state = (power.chargePercent ?? 0) >= 99 ? String(localized: "Tam dolu") : String(localized: "Şarj beklemede")
        } else { state = String(localized: "Pil kullanılıyor") }
        guard let minutes = power.minutesRemaining else { return state }
        let remaining = pocketDuration(Double(minutes) * 60)
        return power.isCharging == true ? String(localized: "\(state) · dolmasına \(remaining)")
                                        : String(localized: "\(state) · \(remaining) kaldı")
    }
}
