import AppKit
import MacPocketCore
import SwiftUI
import SystemConfiguration

/// Genel Bakış: a dashboard of twelve equal tiles mixing live readings with small controls.
/// Twelve divides evenly into 2, 3 and 4 columns, so every row is full at any window width.
struct OverviewView: View {
    @ObservedObject private var modules = PocketModuleRuntime.shared
    @ObservedObject var model: PocketModel
    @ObservedObject var files: FileWorkspaceModel
    @ObservedObject var applications: ApplicationWorkspaceModel
    let navigation: PocketNavigation
    @State private var width: CGFloat = 0

    /// The computer name only changes from System Settings; reading it per render is wasted IPC.
    private static let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? String(localized: "Mac’in")
    private static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
    }()

    private var columnCount: Int { width >= 1180 ? 4 : width >= 840 ? 3 : 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Genel Bakış", subtitle: "\(Self.computerName) · \(Self.osVersion)", icon: PocketPage.overview.icon) {
                    healthBadge
                }
                if let error = model.error { PocketMessage(error, tone: .critical) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: PocketSpacing.l, alignment: .top), count: columnCount),
                          spacing: PocketSpacing.l) {
                    CPUTile(model: model, open: { navigation.select(.performance) })
                    MemoryTile(model: model, open: { navigation.select(.performance) })
                    DiskTile(model: model, open: { navigation.select(.storage) })
                    NetworkTile(model: model, open: { navigation.select(.performance) })
                    PowerTile(model: model, open: { navigation.select(.power) })
                    SystemTile(model: model, verdict: health, open: { navigation.select(.performance) })
                    KeepAwakeTile(model: model, open: { navigation.select(.power) })
                    if modules.available.contains(.clipboard) {
                        ClipboardTile(open: { navigation.open(.clipboard) })
                    } else {
                        DashboardTile(title: "Pano Geçmişi", icon: "doc.on.clipboard", tint: PocketTheme.brandSecondary,
                                      open: { navigation.open(.clipboard) }) {
                            TileValue(value: String(localized: "Modül kapalı"), caption: String(localized: "Ayarların ve geçmişin korunuyor"))
                        } bottom: {
                            Button("Modülü Aç") { modules.setAvailable(.clipboard, true) }
                        }
                    }
                    SpeedTestTile(open: { navigation.open(.speedTest) })
                    CleanupTile(cleanup: files.junk, open: { navigation.select(.cleanup) })
                    ApplicationsTile(applications: applications, open: { navigation.select(.applications) },
                                     openUpdates: { applications.showUpdates = true; navigation.select(.applications) })
                    QuickSettingsTile(open: { navigation.open(.quickActions) })
                }
            }
            .padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width - PocketSpacing.page * 2 }
                        .onChange(of: proxy.size.width) { _, value in width = value - PocketSpacing.page * 2 }
                }
            }
        }
        .task { if !applications.loaded { await applications.load() } }
    }

    // MARK: Health

    struct Verdict {
        let title: String
        let symbol: String
        let tone: PocketTone
    }

    /// One glanceable verdict instead of a wall of numbers.
    private var health: Verdict {
        guard let system = model.system else {
            return Verdict(title: String(localized: "İnceleniyor"), symbol: "hourglass", tone: .neutral)
        }
        var issues: [String] = []
        if let volume = system.volumes.first, volume.totalBytes > 0,
           Double(volume.availableBytes) / Double(volume.totalBytes) < 0.1 { issues.append(String(localized: "disk neredeyse dolu")) }
        if let used = system.usedMemoryBytes, Double(used) / Double(max(1, system.physicalMemoryBytes)) > 0.9 {
            issues.append(String(localized: "bellek baskı altında"))
        }
        if ["serious", "critical"].contains(system.thermalState) { issues.append(String(localized: "sistem ısınıyor")) }
        if (system.cpuTotalPercent ?? 0) > 85 { issues.append(String(localized: "işlemci yoğun")) }
        guard !issues.isEmpty else { return Verdict(title: String(localized: "Mac’in iyi durumda"), symbol: "checkmark.seal.fill", tone: .success) }
        return Verdict(title: String(localized: "Dikkat: \(issues.joined(separator: ", "))"), symbol: "exclamationmark.triangle.fill", tone: .warning)
    }

    private var healthBadge: some View {
        let verdict = health
        return PocketStatusBadge(text: verdict.title, systemImage: verdict.symbol, tone: verdict.tone)
            .font(.callout)
            .contentTransition(.opacity)
    }
}

// MARK: - Tile chrome

/// The one tile layout every dashboard box uses: header, a large value, a caption and a bottom band
/// of fixed height (graph, bar or controls), all at the same size.
private struct DashboardTile<Accessory: View, Value: View, Bottom: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
    let open: () -> Void
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var value: () -> Value
    @ViewBuilder var bottom: () -> Bottom
    @State private var hovering = false
    @PocketReduceMotion private var reduceMotion

    static var height: CGFloat { 196 }
    static var bottomHeight: CGFloat { 40 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PocketSpacing.s) {
                Button(action: open) {
                    HStack(spacing: PocketSpacing.s) {
                        PocketIconTile(symbol: icon, tint: tint, size: 24)
                        Text(title).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                            .opacity(hovering ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("\(Text(title)) ayrıntılarını aç"))
                Spacer(minLength: PocketSpacing.s)
                accessory()
            }
            .frame(height: 28)
            Spacer(minLength: PocketSpacing.s)
            value()
            Spacer(minLength: PocketSpacing.s)
            bottom()
                .frame(maxWidth: .infinity, minHeight: Self.bottomHeight, maxHeight: Self.bottomHeight, alignment: .bottomLeading)
        }
        .padding(PocketSpacing.l)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .pocketCard(padding: 0)
        .overlay {
            RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
                .strokeBorder(tint.opacity(hovering ? 0.45 : 0), lineWidth: 1)
        }
        .scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

extension DashboardTile where Accessory == EmptyView {
    init(title: LocalizedStringKey, icon: String, tint: Color, open: @escaping () -> Void,
         @ViewBuilder value: @escaping () -> Value, @ViewBuilder bottom: @escaping () -> Bottom) {
        self.init(title: title, icon: icon, tint: tint, open: open, accessory: { EmptyView() }, value: value, bottom: bottom)
    }
}

/// Large number plus a one-line caption. Values that change rarely roll when they change; live readings that
/// update every refresh don't animate (measured: the rolling animation on every tick took the dashboard from
/// ~8 % to 40–55 % CPU).
private struct TileValue: View {
    let value: String
    let caption: String
    var tint: Color = .primary
    var rolls = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(rolls ? .numericText() : .identity)
                .animation(rolls ? .snappy(duration: 0.35) : nil, value: value)
            Text(verbatim: caption)
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TileBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient)
                    .frame(width: max(8, proxy.size.width * min(1, max(0, fraction))))
                    .animation(.snappy(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var color: Color { fraction > 0.9 ? .red : fraction > 0.8 ? .orange : tint }
}

// MARK: - Monitoring tiles

private struct CPUTile: View {
    @ObservedObject var model: PocketModel
    let open: () -> Void

    var body: some View {
        let system = model.system
        let caption = system.flatMap { snapshot in
            snapshot.cpuUserPercent.flatMap { user in snapshot.cpuSystemPercent.map { String(localized: "Kullanıcı \(pocketPercent(user)) · Sistem \(pocketPercent($0))") } }
        } ?? String(localized: "\(system?.logicalCPUCount ?? 0) çekirdek")
        DashboardTile(title: "İşlemci", icon: "cpu", tint: PocketPage.performance.tint, open: open) {
            TileValue(value: model.cpuLabel, caption: caption)
        } bottom: {
            PocketSparkline(values: model.samples.suffix(60).map(\.cpuTotal), color: PocketPage.performance.tint)
        }
    }
}

private struct MemoryTile: View {
    @ObservedObject var model: PocketModel
    let open: () -> Void

    var body: some View {
        let system = model.system
        let used = system?.usedMemoryBytes
        let fraction = used.map { Double($0) / Double(max(1, system?.physicalMemoryBytes ?? 1)) }
        DashboardTile(title: "Bellek", icon: "memorychip", tint: PocketTheme.memory, open: open) {
            TileValue(value: fraction.map { pocketPercent($0 * 100) } ?? "—",
                      caption: used.map { String(localized: "\(pocketBytes($0)) / \(pocketBytes(system?.physicalMemoryBytes ?? 0)) kullanılıyor") }
                          ?? String(localized: "Ölçülüyor…"))
        } bottom: {
            PocketSparkline(values: model.samples.suffix(60).compactMap { $0.memoryUsedFraction.map { $0 * 100 } }, color: PocketTheme.memory)
        }
    }
}

private struct DiskTile: View {
    @ObservedObject var model: PocketModel
    let open: () -> Void

    var body: some View {
        let volume = model.system?.volumes.first { $0.path == "/" } ?? model.system?.volumes.first
        let used = volume.map { Double(max(0, $0.totalBytes - $0.availableBytes)) / Double(max(1, $0.totalBytes)) }
        DashboardTile(title: "Disk", icon: "internaldrive", tint: PocketTheme.disk, open: open) {
            TileValue(value: volume.map { pocketDiskBytes($0.availableBytes) } ?? "—",
                      caption: volume.map { String(localized: "\($0.name) · \(pocketDiskBytes($0.totalBytes)) içinde boş") } ?? String(localized: "Okunuyor…"))
        } bottom: {
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                TileBar(fraction: used ?? 0, tint: PocketTheme.disk)
                Text(used.map { String(localized: "\(pocketPercent($0 * 100)) dolu") } ?? " ")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

private struct NetworkTile: View {
    @ObservedObject var model: PocketModel
    @ObservedObject private var history = MenuBarHistory.shared
    let open: () -> Void

    var body: some View {
        let network = model.system?.network
        let down = MenuBarFormatter.rate(network?.receivedBytesPerSecond, binary: true)
        let up = MenuBarFormatter.rate(network?.sentBytesPerSecond, binary: true)
        let address = network?.localIPv4.map { " · \($0)" } ?? ""
        DashboardTile(title: "Ağ", icon: "arrow.up.arrow.down", tint: MenuBarModule.network.tint, open: open) {
            TileValue(value: "↓ " + down, caption: "↑ " + up + address)
        } bottom: {
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                PocketSparkline(values: history.graph(for: .network, settings: MenuBarModuleSettings(value: .networkCombined), count: 60)
                                    .map { $0 * 100 }, color: MenuBarModule.network.tint)
                Text(network.map { String(localized: "Bu oturumda ↓ \(pocketBytes($0.totalReceivedBytes)) · ↑ \(pocketBytes($0.totalSentBytes))") } ?? " ")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
        }
    }
}

private struct PowerTile: View {
    @ObservedObject var model: PocketModel
    let open: () -> Void

    var body: some View {
        let system = model.system
        let power = system?.power
        let fastest = system?.fans?.max { $0.rpm < $1.rpm }
        let value: String = power?.batteryPresent == true ? (power?.chargePercent.map { pocketPercent($0) } ?? "—")
            : fastest.map { MenuBarFormatter.number($0.rpm, fractionDigits: 0) + " " + MenuBarFormatter.rpmUnit } ?? pocketPowerSourceTitle(power?.source)
        let thermal = pocketThermalTitle(system?.thermalState)
        let caption = power?.batteryPresent == true ? String(localized: "Pil · ısı \(thermal)")
            : fastest != nil ? String(localized: "En hızlı fan · ısı \(thermal)") : String(localized: "Isı \(thermal)")
        DashboardTile(title: "Güç ve Isı", icon: "bolt.fill", tint: PocketPage.power.tint, open: open) {
            TileValue(value: value, caption: caption)
        } bottom: {
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                TileBar(fraction: power?.batteryPresent == true ? (power?.chargePercent ?? 0) / 100 : fastest?.fraction ?? 0,
                        tint: PocketPage.power.tint)
                Text(power?.batteryPresent == true ? String(localized: "Şarj") : fastest != nil ? String(localized: "Azami fan hızına oran") : " ")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SystemTile: View {
    @ObservedObject var model: PocketModel
    let verdict: OverviewView.Verdict
    let open: () -> Void

    var body: some View {
        let system = model.system
        DashboardTile(title: "Sistem", icon: "desktopcomputer", tint: PocketTheme.brand, open: open) {
            TileValue(value: system.map { pocketDuration($0.uptimeSeconds) } ?? "—",
                      caption: [system?.hardwareModel, system.map { String(localized: "\($0.logicalCPUCount) çekirdek · \(pocketBytes($0.physicalMemoryBytes))") }]
                          .compactMap { $0 }.joined(separator: " · "))
        } bottom: {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: verdict.symbol).foregroundStyle(verdict.tone.color)
                Text(verbatim: verdict.title).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                if let load = system?.loadAverages?.first {
                    Text("Yük \(MenuBarFormatter.number(load, fractionDigits: 2))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Control tiles

private struct KeepAwakeTile: View {
    @ObservedObject var model: PocketModel
    let open: () -> Void

    var body: some View {
        let session = model.awakeSession?.active == true ? model.awakeSession : nil
        DashboardTile(title: "Uyanık Tut", icon: "cup.and.saucer.fill", tint: Color(hex: 0xA0703C), open: open) {
            if let session {
                VStack(alignment: .leading, spacing: 2) {
                    if let end = session.endsAt {
                        Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                            .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    } else {
                        Text("Süresiz").font(.system(size: 30, weight: .semibold, design: .rounded))
                    }
                    Text(session.keepDisplayAwake ? "Mac ve ekran uyanık" : "Mac uyanık tutuluyor").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                TileValue(value: String(localized: "Kapalı"), caption: String(localized: "Otomatik uyku normal çalışıyor"))
            }
        } bottom: {
            if session != nil {
                Button("Durdur", role: .destructive) { Task { await model.stopAwake() } }
                    .controlSize(.regular)
            } else {
                HStack(spacing: PocketSpacing.xs) {
                    awake("30 dk", 1800)
                    awake("1 sa", 3600)
                    awake("2 sa", 7200)
                    awake("∞", nil)
                }
            }
        }
    }

    private func awake(_ title: LocalizedStringKey, _ seconds: Double?) -> some View {
        Button { Task { await model.startAwake(duration: seconds) } } label: { Text(title).frame(maxWidth: .infinity) }
            .controlSize(.regular)
            .help(seconds == nil ? Text("Durdurana kadar uyanık tut") : Text("\(Text(title)) uyanık tut"))
    }
}

private struct ClipboardTile: View {
    @ObservedObject private var service = ClipboardService.shared
    let open: () -> Void

    var body: some View {
        DashboardTile(title: "Pano Geçmişi", icon: "doc.on.clipboard", tint: PocketTheme.brandSecondary, open: open) {
            Toggle("Pano geçmişi", isOn: $service.settings.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
        } value: {
            TileValue(value: service.settings.enabled ? String(localized: "\(service.history.items.count) öğe") : String(localized: "Kapalı"),
                      caption: service.settings.enabled ? String(localized: "\(service.settings.shortcut.displayName) ile panel")
                                                        : String(localized: "Kopyaladıkların kaydedilmiyor"), rolls: true)
        } bottom: {
            HStack(spacing: PocketSpacing.s) {
                Button { service.togglePanel() } label: { Label("Paneli aç", systemImage: "rectangle.and.text.magnifyingglass").frame(maxWidth: .infinity) }
                    .disabled(!service.settings.enabled)
                Button { service.clearSystemClipboard() } label: { Image(systemName: "xmark.bin") }
                    .help("Sistem panosunu boşalt")
                    .accessibilityLabel("Sistem panosunu boşalt")
            }
        }
    }
}

private struct SpeedTestTile: View {
    @ObservedObject private var model = SpeedTestModel.shared
    let open: () -> Void

    var body: some View {
        let latest = model.latest
        DashboardTile(title: "Ağ Hızı", icon: "speedometer", tint: Color(hex: 0x00A6C8), open: open) {
            if model.running, let started = model.startedAt {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timerInterval: started...Date.distantFuture, countsDown: false)
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Ölçülüyor…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                TileValue(value: "↓ " + SpeedFormatter.bitRate(latest?.downloadBitsPerSecond),
                          caption: latest.map { "↑ " + SpeedFormatter.bitRate($0.uploadBitsPerSecond) + ($0.responsivenessRPM.map { " · \(Int($0)) RPM" } ?? "") }
                              ?? String(localized: "Henüz ölçüm yok"), rolls: true)
            }
        } bottom: {
            if model.running {
                HStack(spacing: PocketSpacing.s) {
                    ProgressView().controlSize(.small)
                    Spacer()
                    Button("İptal") { model.cancel() }
                }
            } else {
                Button { model.start() } label: { Label("Hızı ölç", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.pocketPrimary)
            }
        }
    }
}

private struct CleanupTile: View {
    @ObservedObject var cleanup: CleanupModel
    let open: () -> Void

    var body: some View {
        DashboardTile(title: "Temizlik", icon: "sparkles", tint: PocketPage.cleanup.tint, open: open) {
            if cleanup.scanning {
                TileValue(value: cleanup.progress.map { pocketDiskBytes($0.measuredBytes) } ?? "…", caption: String(localized: "Taranıyor…"), rolls: true)
            } else if let report = cleanup.report {
                TileValue(value: pocketDiskBytes(report.bytes), caption: String(localized: "\(report.itemCount.formatted()) öğe temizlenebilir"), rolls: true)
            } else {
                TileValue(value: "—", caption: String(localized: "Önbellek ve günlükleri tara"), rolls: true)
            }
        } bottom: {
            HStack(spacing: PocketSpacing.s) {
                Button { cleanup.scan() } label: {
                    Label(cleanup.report == nil ? "Tara" : "Yeniden tara", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .disabled(cleanup.busy)
                Button("İncele", action: open).disabled(cleanup.report == nil)
            }
        }
    }
}

private struct ApplicationsTile: View {
    @ObservedObject var applications: ApplicationWorkspaceModel
    let open: () -> Void
    let openUpdates: () -> Void

    var body: some View {
        DashboardTile(title: "Uygulamalar", icon: "app.badge", tint: PocketPage.applications.tint, open: open) {
            TileValue(value: applications.loaded ? "\(applications.applications.count)" : "…",
                      caption: applications.updatesCheckedAt == nil ? String(localized: "Güncellemeler denetlenmedi")
                          : applications.availableUpdateCount == 0 ? String(localized: "Kaynak sonuçlarını incele")
                          : String(localized: "\(applications.availableUpdateCount) güncelleme hazır"), rolls: true)
        } bottom: {
            HStack(spacing: PocketSpacing.s) {
                Button { Task { await applications.checkUpdates() } } label: {
                    if applications.checkingUpdates {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label("Denetle", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                }
                .disabled(applications.checkingUpdates || applications.busy || applications.updatingToken != nil || applications.updateSettings.sources.isEmpty)
                Button("Güncellemeler", action: openUpdates)
            }
        }
    }
}

/// A few switches people flip often: hidden files (Finder restarts), window layout shortcuts, the menu bar item.
private struct QuickSettingsTile: View {
    @ObservedObject private var modules = PocketModuleRuntime.shared
    @ObservedObject private var menuBar = MenuBarSettingsStore.shared
    @ObservedObject private var quickActions = QuickActionService.shared
    @State private var hiddenFiles = HiddenSettingsService().state(of: Self.hiddenFilesSetting).value == .bool(true)
    @State private var applying = false
    let open: () -> Void

    private static let hiddenFilesSetting = HiddenSetting.setting(id: "finder.AppleShowAllFiles")!

    var body: some View {
        DashboardTile(title: "Hızlı Ayarlar", icon: "switch.2", tint: PocketPage.tools.tint, open: open) {
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                row("Gizli dosyalar", icon: "eye", isOn: Binding(get: { hiddenFiles }, set: setHiddenFiles))
                    .disabled(applying)
                if modules.available.contains(.windowLayout) {
                    DashboardWindowLayoutToggle()
                } else {
                    Button("Pencere Yerleşimi Modülünü Aç") { modules.setAvailable(.windowLayout, true) }
                        .font(.callout)
                }
                row("Menü çubuğu simgesi", icon: "menubar.rectangle", isOn: $menuBar.preferences.visible)
            }
        } bottom: {
            Menu {
                ForEach(QuickAction.allCases.filter { !$0.needsConfirmation }) { action in
                    Button { quickActions.perform(action) } label: { Label(action.title, systemImage: action.symbol) }
                }
                Divider()
                Button("Tüm hızlı işlemler…", action: open)
            } label: {
                Label("Hızlı işlemler", systemImage: "bolt.circle")
            }
            .menuStyle(.borderedButton)
            .fixedSize()
            .help("Gizli dosyalar Finder’ı yeniden başlatır.")
        }
    }

    private func row(_ title: LocalizedStringKey, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Label(title, systemImage: icon).font(.callout)
            Spacer(minLength: PocketSpacing.s)
            Toggle(isOn: isOn) { Text(title) }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private func setHiddenFiles(_ isOn: Bool) {
        hiddenFiles = isOn
        applying = true
        Task {
            _ = try? await HiddenSettingsService().apply([.set(id: Self.hiddenFilesSetting.id, value: .bool(isOn))])
            hiddenFiles = HiddenSettingsService().state(of: Self.hiddenFilesSetting).value == .bool(true)
            applying = false
        }
    }
}

private struct DashboardWindowLayoutToggle: View {
    @ObservedObject private var service = WindowLayoutService.shared
    var body: some View {
        Toggle(isOn: $service.settings.enabled) { Label("Pencere yerleşimi", systemImage: "rectangle.split.2x1") }
            .font(.callout).toggleStyle(.switch).controlSize(.small)
    }
}
