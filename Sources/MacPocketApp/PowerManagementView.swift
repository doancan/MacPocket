import Charts
import MacPocketCore
import SwiftUI

/// Güç Merkezi: live power monitoring, sleep blockers, per-app energy, every pmset setting and history.
struct PowerManagementView: View {
    var model: PocketModel
    @State private var center = PowerCenterModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.xl) {
                PocketPageHeading(title: "Güç Merkezi",
                                  subtitle: "Güç kaynağı, pil, uyku engelleyiciler, uygulama enerjisi ve tüm güç ayarları.",
                                  icon: "battery.100percent.bolt") {
                    HStack(spacing: PocketSpacing.s) {
                        Button { center.openSystemSettings() } label: {
                            Label(center.hasBattery ? "Pil Ayarları" : "Enerji Ayarları", systemImage: "gear")
                        }
                        .help("Sistem Ayarları’nda ilgili bölümü açar")
                        Button { model.navigation.open(.diagnostics) } label: {
                            Label("Güç Raporları", systemImage: "doc.text.magnifyingglass")
                        }
                        .help("Uykuyu engelleyen süreçleri ve güç ayarlarını gösteren salt okunur raporlar")
                    }
                }
                PowerHeroCard(center: center, model: model)
                tabPicker
                Group {
                    switch center.tab {
                    case .overview: PowerOverviewPanel(center: center, model: model)
                    case .battery: PowerBatteryPanel(center: center, model: model)
                    case .blockers: PowerBlockersPanel(center: center)
                    case .energy: PowerEnergyPanel(center: center)
                    case .settings: PowerSettingsPanel(center: center)
                    case .history: PowerHistoryPanel(center: center, model: model)
                    }
                }
            }
            .padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task { await center.run() }
        .onChange(of: center.hasBattery) { _, hasBattery in
            if !hasBattery, center.tab == .battery { center.tab = .overview }
        }
        .sheet(item: $center.pendingChange) { change in
            PowerChangeConfirmation(center: center, change: change)
        }
    }

    private var tabPicker: some View {
        GlassTabBar(tabs: center.visibleTabs.map { GlassTab(id: $0, title: $0.localizedTitle, symbol: $0.icon) },
                    selection: $center.tab)
        .accessibilityLabel("Güç Merkezi bölümü")
    }
}

// MARK: - Formatting helpers

func powerWatts(_ watts: Double) -> String {
    "\(watts.formatted(.number.precision(.fractionLength(watts < 10 ? 2 : 1)).locale(pocketLocale))) W"
}

func powerMilliwatts(_ milliwatts: Double) -> String {
    milliwatts >= 1000 ? powerWatts(milliwatts / 1000)
        : "\(milliwatts.formatted(.number.precision(.fractionLength(0)).locale(pocketLocale))) mW"
}

func powerMinutes(_ minutes: Int) -> String {
    pocketDuration(Double(minutes) * 60)
}

/// The app bundle that contains an executable, for icons and grouping.
func powerAppBundle(for path: String) -> URL? {
    guard let range = path.range(of: ".app/") else { return nil }
    return URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
}

/// Label–value row used across the power panels.
/// Text parameters are localization keys; pass dynamic values by interpolation (`"\(value)"`).
struct PowerFactRow: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    var tone: PocketTone?
    var help: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: PocketSpacing.m)
            if let tone {
                PocketStatusBadge(text: value, tone: tone)
            } else {
                Text(value).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
            }
        }
        .font(.callout)
        .help(help ?? "")
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hero

struct PowerHeroCard: View {
    var center: PowerCenterModel
    var model: PocketModel
    @Environment(\.pocketTint) private var tint

    var body: some View {
        Group {
            if let overview = center.overview {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: PocketSpacing.xl) {
                        gauge(overview)
                        summary(overview).frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 110)
                        facts(overview).frame(width: 280)
                    }
                    VStack(alignment: .leading, spacing: PocketSpacing.l) {
                        HStack(spacing: PocketSpacing.l) { gauge(overview); summary(overview) }
                        facts(overview)
                    }
                }
            } else {
                HStack(spacing: PocketSpacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Güç bilgisi okunuyor…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            }
        }
        .pocketCard(padding: PocketSpacing.xl)
    }

    @ViewBuilder
    private func gauge(_ overview: PowerOverview) -> some View {
        if let battery = overview.internalBattery, let percent = battery.chargePercent {
            PocketRingMetric(title: battery.isCharging == true ? "Şarj oluyor" : (battery.isCharged == true ? "Dolu" : "Pil"),
                             value: "\(pocketPercent(percent))", fraction: percent / 100,
                             color: percent < 20 ? .red : (percent < 40 ? .orange : PocketTheme.disk), size: 110)
        } else if let watts = center.wattHistory.last?.watts {
            let peak = max(1, center.wattHistory.map(\.watts).max() ?? 1)
            PocketRingMetric(title: "Sistem girişi", value: "\(powerWatts(watts))",
                             fraction: watts / (peak * 1.25), color: tint, size: 110)
        } else if let energy = center.energy {
            // Desktop Macs often stop publishing whole-system telemetry; fall back to what is measurable
            // and say so, instead of showing a made-up system figure.
            let watts = energy.totalMilliwatts / 1000
            PocketRingMetric(title: "Süreç gücü", value: "\(powerWatts(watts))",
                             fraction: min(1, watts / 120), color: tint, size: 110)
                .help("Okunabilen süreçlerin tahmini toplam gücü. Ekran, GPU ve sistem süreçleri dahil değildir; bu Mac sistem geneli güç telemetrisi yayınlamıyor.")
        } else {
            PocketRingMetric(title: "Güç ölçülüyor", value: "—", fraction: nil, color: tint, size: 110)
        }
    }

    private func summary(_ overview: PowerOverview) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: sourceIcon(overview)).foregroundStyle(tint).accessibilityHidden(true)
                Text(sourceTitle(overview)).font(.title2.weight(.semibold))
            }
            Text(sourceDetail(overview))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PocketSpacing.s) {
                PocketStatusBadge(text: "Termal: \(pocketThermalTitle(overview.thermalState))" as LocalizedStringKey,
                                  systemImage: "thermometer.medium", tone: pocketThermalTone(overview.thermalState))
                if overview.lowPowerMode {
                    PocketStatusBadge(text: "Düşük Güç Modu", systemImage: "leaf", tone: .warning)
                }
                if let session = model.awakeSession, session.active {
                    PocketStatusBadge(text: "Uyanık tutuluyor", systemImage: "cup.and.saucer.fill", tone: .accent)
                }
                if let blockers = center.assertions?.sleepBlockers.count, blockers > 0 {
                    PocketStatusBadge(text: "\(blockers) uyku engeli" as LocalizedStringKey, systemImage: "moon.zzz", tone: .neutral)
                }
            }
            if center.wattHistory.count > 2 {
                PocketSparkline(values: center.wattHistory.map(\.watts), color: tint, ceiling: nil)
                    .frame(height: 28)
                    .frame(maxWidth: 360)
            }
        }
    }

    private func facts(_ overview: PowerOverview) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PowerFactRow(title: "Güç kaynağı", value: "\(pocketPowerSourceTitle(overview.providingSource))")
            if let adapter = overview.adapter, adapter.hasDetails {
                let adapterText = [adapter.watts.map { "\($0) W" }, adapter.name].compactMap { $0 }.joined(separator: " · ")
                PowerFactRow(title: "Adaptör", value: "\(adapterText)")
            }
            if let battery = overview.battery {
                if let milliwatts = battery.systemPowerInMilliwatts {
                    PowerFactRow(title: "Sistem girişi", value: "\(powerWatts(Double(milliwatts) / 1000))",
                                 help: "Mac’in güç girişinden çektiği anlık güç (PowerTelemetry)")
                }
                if let volts = battery.systemVoltageInMillivolts {
                    PowerFactRow(title: "Giriş gerilimi", value: "\(String(format: "%.2f V", Double(volts) / 1000))")
                }
            }
            PowerFactRow(title: "Düşük Güç Modu", value: overview.lowPowerMode ? "Açık" : "Kapalı",
                         tone: overview.lowPowerMode ? .warning : .neutral)
            if !overview.upsSources.isEmpty {
                PowerFactRow(title: "UPS", value: "\(overview.upsSources.count) bağlı")
            }
        }
    }

    private func sourceIcon(_ overview: PowerOverview) -> String {
        switch overview.providingSource {
        case "Battery Power": "battery.75percent"
        case "UPS Power": "powerplug.portrait"
        default: overview.hasBattery ? "battery.100percent.bolt" : "powerplug"
        }
    }

    private func sourceTitle(_ overview: PowerOverview) -> LocalizedStringKey {
        switch overview.providingSource {
        case "Battery Power": "Pilden çalışıyor"
        case "UPS Power": "UPS’ten çalışıyor"
        case "AC Power": "Prizden çalışıyor"
        default: "Güç kaynağı bilinmiyor"
        }
    }

    private func sourceDetail(_ overview: PowerOverview) -> LocalizedStringKey {
        if let battery = overview.internalBattery {
            if battery.isCharging == true {
                if let minutes = battery.timeToFullMinutes { return "Dolmasına \(powerMinutes(minutes)) kaldı." }
                return "Şarj ediliyor; süre hesaplanıyor."
            }
            if overview.providingSource == "Battery Power" {
                if let minutes = battery.timeToEmptyMinutes { return "Tahmini kalan süre \(powerMinutes(minutes))." }
                return "Kalan süre hesaplanıyor."
            }
            return battery.isCharged == true ? "Pil dolu; adaptörden çalışıyor." : "Adaptöre bağlı, şarj beklemede."
        }
        return "Bu Mac’te dahili pil yok. Anlık güç tüketimi ve uyku yönetimi aşağıda."
    }
}

// MARK: - Overview

/// Keeping awake, thermal limits, sensors, top energy users and schedules.
struct PowerOverviewPanel: View {
    var center: PowerCenterModel
    var model: PocketModel

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: PocketSpacing.l) { PowerKeepAwakeCard(model: model); statusCard }
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: PocketSpacing.l) { PowerKeepAwakeCard(model: model); statusCard }
            }
            PocketSensorsCard(system: model.system)
            if model.system?.fans?.isEmpty == false { FanControlCard() }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: PocketSpacing.l) { topEnergy; scheduleCard }
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: PocketSpacing.l) { topEnergy; scheduleCard }
            }
            if let ups = center.overview?.upsSources, !ups.isEmpty { upsCard(ups) }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Sistem durumu", icon: "waveform.path.ecg")
            if let overview = center.overview {
                PowerFactRow(title: "Termal durum", value: "\(pocketThermalTitle(overview.thermalState))",
                             tone: pocketThermalTone(overview.thermalState))
                if let thermal = center.thermal {
                    PowerFactRow(title: "CPU hız sınırı", value: thermal.cpuSpeedLimit.map { "\(pocketPercent(Double($0)))" } ?? "Sınır yok",
                                 tone: thermal.isThrottled ? .warning : .success,
                                 help: "pmset -g therm: işlemci hızının termal nedenle kısıldığı oran")
                    if let scheduler = thermal.schedulerLimit {
                        PowerFactRow(title: "Zamanlayıcı sınırı", value: "\(pocketPercent(Double(scheduler)))")
                    }
                    if let cpus = thermal.availableCPUs {
                        PowerFactRow(title: "Kullanılabilir çekirdek", value: "\(cpus)")
                    }
                } else {
                    PowerFactRow(title: "CPU hız sınırı", value: "Okunuyor…")
                }
                PowerFactRow(title: "Düşük Güç Modu", value: overview.lowPowerMode ? "Açık" : "Kapalı")
                if let live = center.live {
                    PowerFactRow(title: "Sistem uykusu", value: "\(live.value(.sleep)?.displayValue ?? "—")")
                    PowerFactRow(title: "Ekranı kapat", value: "\(live.value(.displaysleep)?.displayValue ?? "—")")
                }
                if let report = center.assertions {
                    PowerFactRow(title: "Boşta uyku", value: report.preventsIdleSystemSleep ? "Engelleniyor" : "Serbest",
                                 tone: report.preventsIdleSystemSleep ? .warning : .success)
                    Button("Uyku engelleyicileri göster") { center.tab = .blockers }
                        .buttonStyle(.link)
                } else if let error = center.assertionsError {
                    PocketMessage(error, error: true)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private var topEnergy: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("En çok enerji kullananlar", icon: "bolt.fill") {
                Button("Tümü") { center.tab = .energy }.buttonStyle(.link)
            }
            if let sample = center.energy {
                if sample.processes.isEmpty {
                    Text("Ölçüm aralığında enerji kullanan süreç yok.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(sample.processes.prefix(5)) { process in
                        PowerEnergyRow(process: process, maximum: sample.processes.first?.milliwatts ?? 1, compact: true)
                    }
                }
            } else {
                HStack(spacing: PocketSpacing.s) {
                    ProgressView().controlSize(.small)
                    Text("İlk ölçüm alınıyor…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Zamanlanmış güç olayları", icon: "calendar.badge.clock")
            if let error = center.scheduleError {
                PocketMessage(error, error: true)
            } else if let events = center.schedule {
                if events.isEmpty {
                    Text("Zamanlanmış uyanma, uyku veya kapanma yok.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.s) {
                            Image(systemName: event.repeating ? "repeat" : "clock")
                                .foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                                Text(event.typeTitle).font(.callout.weight(.medium))
                                if let owner = event.owner {
                                    Text(owner).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(event.date.map { $0.formatted(.dateTime.locale(pocketLocale).day().month().hour().minute()) } ?? event.when)
                                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Text("Olaylar Sistem Ayarları veya `pmset schedule` ile eklenir.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func upsCard(_ sources: [PowerSourceInfo]) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Kesintisiz güç kaynakları", icon: "powerplug.portrait")
            ForEach(sources) { ups in
                HStack(spacing: PocketSpacing.l) {
                    PocketRingMetric(title: "\(ups.name)", value: "\(ups.chargePercent.map { pocketPercent($0) } ?? "—")",
                                     fraction: ups.chargePercent.map { $0 / 100 }, color: PocketTheme.disk, size: 60)
                    VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                        PowerFactRow(title: "Durum", value: "\(pocketPowerSourceTitle(ups.state))")
                        if let transport = ups.transport { PowerFactRow(title: "Bağlantı", value: "\(transport)") }
                        if let minutes = ups.timeToEmptyMinutes { PowerFactRow(title: "Kalan süre", value: "\(powerMinutes(minutes))") }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }
}

// MARK: - Keep awake

struct PowerKeepAwakeCard: View {
    var model: PocketModel
    @AppStorage("MacPocket.power.awakeMinutes") private var minutes = 30.0
    @AppStorage(PocketModel.awakeDisplayKey) private var displayAwake = PocketModel.awakeDisplayDefault
    @State private var changing = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Uyanık tut", icon: "cup.and.saucer")
            if let session = model.awakeSession, session.active {
                HStack(spacing: PocketSpacing.m) {
                    Image(systemName: "cup.and.saucer.fill").font(.title2).foregroundStyle(PocketTheme.power)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                        Text(model.awakeIsAutomatic ? "Koşullu uyanık tutma etkin" : "Mac uyanık tutuluyor").font(.headline)
                        if let end = session.endsAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("\(remaining(until: end, now: context.date)) kaldı · bitiş \(end.formatted(date: .omitted, time: .shortened))")
                                    .monospacedDigit()
                            }
                            .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("Sen durdurana kadar").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(session.keepDisplayAwake ? "Ekran da açık tutuluyor." : "Ekran normal şekilde kararabilir.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(role: .destructive) { run { await model.stopAwake() } } label: {
                    Label("Uyanık Tutmayı Durdur", systemImage: "stop.circle")
                }
                .disabled(changing)
            } else {
                Picker("Süre", selection: $minutes) {
                    Text("5 dakika").tag(5.0); Text("15 dakika").tag(15.0); Text("30 dakika").tag(30.0)
                    Text("1 saat").tag(60.0); Text("2 saat").tag(120.0); Text("4 saat").tag(240.0)
                    Text("8 saat").tag(480.0)
                    Divider()
                    Text("Ben durdurana kadar").tag(0.0)
                }
                Toggle("Ekranı da açık tut", isOn: $displayAwake)
                Button { run { await model.startAwake(duration: minutes > 0 ? minutes * 60 : nil, display: displayAwake) } } label: {
                    Label("Uyanık Tutmayı Başlat", systemImage: "cup.and.saucer")
                }
                .buttonStyle(.pocketPrimary)
                .disabled(changing)
            }
            Text("Boşta uyku geçici olarak engellenir; süre dolunca veya MacPocket kapanınca sona erer. Kalıcı ayar değişmez.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.awakeError { PocketMessage(error, error: true) }
            Divider()
            AwakeAutomationView(service: model.awakeAutomation)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func remaining(until end: Date, now: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard !changing else { return }
        changing = true
        Task { await action(); changing = false }
    }
}

// MARK: - Battery

struct PowerBatteryPanel: View {
    var center: PowerCenterModel
    var model: PocketModel

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            if let overview = center.overview, overview.hasBattery {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: PocketSpacing.l) { healthCard(overview); electricalCard(overview) }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: PocketSpacing.l) { healthCard(overview); electricalCard(overview) }
                }
                chargeHistory
            } else {
                ContentUnavailableView("Bu Mac’te dahili pil yok", systemImage: "powerplug",
                                       description: Text("Pil sağlığı, döngü sayısı ve şarj bilgileri yalnızca dizüstü Mac’lerde gösterilir."))
                    .frame(maxWidth: .infinity)
                    .pocketCard()
            }
        }
    }

    private func healthCard(_ overview: PowerOverview) -> some View {
        let source = overview.internalBattery
        let registry = overview.battery
        let health = registry?.healthPercent ?? source?.maximumCapacityPercent.map(Double.init)
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Pil sağlığı", icon: "heart.text.square")
            HStack(spacing: PocketSpacing.l) {
                PocketRingMetric(title: "Maksimum kapasite", value: "\(health.map { pocketPercent(min($0, 100)) } ?? "—")",
                                 fraction: health.map { $0 / 100 },
                                 color: (health ?? 100) < 80 ? .orange : PocketTheme.disk, size: 88)
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    PowerFactRow(title: "Durum", value: "\(conditionTitle(source))", tone: conditionTone(source, registry))
                    if let cycles = registry?.cycleCount {
                        PowerFactRow(title: "Döngü sayısı",
                                     value: "\(registry?.designCycleCount.map { "\(cycles) / \($0)" } ?? "\(cycles)")")
                    }
                    if let max = registry?.maxCapacity, let design = registry?.designCapacity {
                        PowerFactRow(title: "Tam şarj / tasarım", value: "\(max) / \(design) mAh")
                    }
                }
            }
            Divider()
            if let optimized = source?.optimizedChargingEngaged {
                PowerFactRow(title: "Optimize şarj", value: optimized ? "Etkin (şarj bekletiliyor)" : "Beklemede")
            }
            if registry?.permanentFailure == true {
                PocketMessage("Pil kalıcı hata bildiriyor; servis önerilir.", tone: .critical)
            }
            if let serial = registry?.serial { PowerFactRow(title: "Seri numarası", value: "\(serial)") }
            if let device = registry?.deviceName { PowerFactRow(title: "Pil denetleyicisi", value: "\(device)") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func electricalCard(_ overview: PowerOverview) -> some View {
        let source = overview.internalBattery
        let registry = overview.battery
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Şarj ve elektrik", icon: "bolt.batteryblock")
            if let percent = source?.chargePercent { PowerFactRow(title: "Şarj", value: "\(pocketPercent(percent))") }
            PowerFactRow(title: "Şarj durumu", value: chargingTitle(source, registry))
            if let minutes = source?.timeToEmptyMinutes, overview.providingSource == "Battery Power" {
                PowerFactRow(title: "Kalan süre", value: "\(powerMinutes(minutes))")
            }
            if let minutes = source?.timeToFullMinutes, source?.isCharging == true {
                PowerFactRow(title: "Dolmasına", value: "\(powerMinutes(minutes))")
            }
            if let current = registry?.currentCapacity { PowerFactRow(title: "Mevcut kapasite", value: "\(current) mAh") }
            if let temperature = registry?.temperatureCelsius {
                PowerFactRow(title: "Sıcaklık", value: "\(String(format: "%.1f °C", temperature))",
                             tone: temperature > 40 ? .warning : nil)
            }
            if let volts = registry?.voltageMillivolts { PowerFactRow(title: "Gerilim", value: "\(String(format: "%.2f V", Double(volts) / 1000))") }
            if let amps = registry?.amperageMilliamps { PowerFactRow(title: "Akım", value: "\(amps) mA") }
            if let watts = registry?.batteryWatts {
                PowerFactRow(title: watts >= 0 ? "Pile giren güç" : "Pilden çekilen güç", value: "\(powerWatts(abs(watts)))")
            }
            if let adapter = overview.adapter, adapter.hasDetails {
                Divider()
                PowerFactRow(title: "Adaptör", value: adapter.name.map { "\($0)" } ?? "Bağlı")
                if let watts = adapter.watts { PowerFactRow(title: "Adaptör gücü", value: "\(watts) W") }
                if let manufacturer = adapter.manufacturer { PowerFactRow(title: "\(String(localized: "Power.manufacturer", defaultValue: "Üretici"))", value: "\(manufacturer)") }
                if let serial = adapter.serial { PowerFactRow(title: "Adaptör seri no.", value: "\(serial)") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private var chargeHistory: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Şarj geçmişi", icon: "chart.xyaxis.line") { Text("Son 12 saat · yerel kayıt") }
            let cutoff = Date().addingTimeInterval(-12 * 3600)
            let points = model.powerHistory.filter { $0.date >= cutoff && $0.chargePercent != nil }
            if points.count > 1 {
                Chart(points) { entry in
                    AreaMark(x: .value(Text("Zaman"), entry.date), y: .value(Text("Şarj"), entry.chargePercent ?? 0))
                        .foregroundStyle(LinearGradient(colors: [PocketTheme.disk.opacity(0.3), PocketTheme.disk.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value(Text("Zaman"), entry.date), y: .value(Text("Şarj"), entry.chargePercent ?? 0))
                        .foregroundStyle(PocketTheme.disk)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(); AxisValueLabel { if let number = value.as(Int.self) { Text(verbatim: pocketPercent(Double(number))) } }
                } }
                .frame(height: 170)
                .accessibilityLabel("Şarj geçmişi grafiği")
            } else {
                Text("Grafik için en az iki ölçüm gerekiyor; MacPocket dakikada bir kayıt alır.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func conditionTitle(_ source: PowerSourceInfo?) -> String {
        if let condition = source?.healthCondition, !condition.isEmpty {
            switch condition {
            case "Service Recommended", "Check Battery": return String(localized: "Servis önerilir")
            case "Permanent Battery Failure": return String(localized: "Kalıcı arıza")
            default: return condition
            }
        }
        switch source?.health {
        case "Good": return String(localized: "Normal")
        case "Fair": return String(localized: "Orta")
        case "Poor": return String(localized: "Zayıf")
        case let value?: return value
        case nil: return String(localized: "Bilinmiyor")
        }
    }

    private func conditionTone(_ source: PowerSourceInfo?, _ registry: BatteryRegistryInfo?) -> PocketTone {
        if registry?.permanentFailure == true || source?.healthCondition?.isEmpty == false { return .critical }
        switch source?.health {
        case "Good": return .success
        case "Fair": return .warning
        case "Poor": return .critical
        default: return .neutral
        }
    }

    private func chargingTitle(_ source: PowerSourceInfo?, _ registry: BatteryRegistryInfo?) -> LocalizedStringKey {
        if source?.isCharging == true || registry?.isCharging == true { return "Şarj oluyor" }
        if source?.isCharged == true || registry?.fullyCharged == true { return "Dolu" }
        if registry?.externalConnected == true { return "Adaptöre bağlı, şarj edilmiyor" }
        return "Pilden çalışıyor"
    }
}
