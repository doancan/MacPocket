import AppKit
import MacPocketCore
import SwiftUI
import SystemConfiguration

struct OverviewView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var files: FileWorkspaceModel
    @ObservedObject var applications: ApplicationWorkspaceModel
    let navigation: PocketNavigation

    /// The computer name only changes from System Settings; reading it per render is wasted IPC.
    private static let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? String(localized: "Mac’in")
    private static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.xl) {
                PocketPageHeading(title: "Genel Bakış", subtitle: "Mac’inin durumu, bakım işlemleri ve günlük araçların.",
                                  icon: PocketPage.overview.icon)
                if let error = model.error { PocketMessage(error, tone: .critical) }
                deviceCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: PocketSpacing.l, alignment: .top)],
                          alignment: .leading, spacing: PocketSpacing.l) {
                    storagePanel
                    applicationsPanel
                    powerPanel
                    toolsPanel
                }
            }
            .padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task { if !applications.loaded { await applications.load() } }
    }

    // MARK: Device

    /// One-sentence health verdict, the way CleanMyMac leads with a single status instead of a wall of numbers.
    private var health: (title: String, detail: String, symbol: String) {
        guard let system = model.system else {
            return (String(localized: "Mac’in inceleniyor"), String(localized: "İlk ölçüm birkaç saniye içinde gelir."), "hourglass")
        }
        var issues: [String] = []
        if let volume = system.volumes.first, volume.totalBytes > 0,
           Double(volume.availableBytes) / Double(volume.totalBytes) < 0.1 { issues.append(String(localized: "disk neredeyse dolu")) }
        if let used = system.usedMemoryBytes, Double(used) / Double(max(1, system.physicalMemoryBytes)) > 0.9 {
            issues.append(String(localized: "bellek baskı altında"))
        }
        if ["serious", "critical"].contains(system.thermalState) { issues.append(String(localized: "sistem ısınıyor")) }
        if (system.cpuTotalPercent ?? 0) > 85 { issues.append(String(localized: "işlemci yoğun")) }
        if issues.isEmpty {
            return (String(localized: "Mac’in iyi durumda"),
                    String(localized: "Kaynaklar dengeli; \(pocketDuration(system.uptimeSeconds)) kesintisiz çalışıyor."), "checkmark.seal.fill")
        }
        let list = issues.joined(separator: ", ")
        return (String(localized: "Dikkat: \(list)"), String(localized: "Ayrıntılar için Sistem İzleme’yi aç."), "exclamationmark.triangle.fill")
    }

    private var deviceCard: some View {
        let system = model.system
        let volume = system?.volumes.first
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: PocketSpacing.xl) {
                heroText
                Spacer(minLength: PocketSpacing.l)
                rings(system, volume)
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xl) {
                heroText
                rings(system, volume)
            }
        }
        .padding(PocketSpacing.xl + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            ZStack {
                shape.fill(PocketTheme.brandGradient)
                // Soft highlights give the hero depth without an illustration asset.
                shape.fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 420))
                shape.fill(RadialGradient(colors: [Color(hex: 0x00D4FF).opacity(0.25), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380))
            }
            .clipShape(shape)
            .shadow(color: PocketTheme.brand.opacity(0.35), radius: 22, y: 10)
        }
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.75) }
    }

    private var heroText: some View {
        let system = model.system
        let verdict = health
        return VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text(Self.computerName.uppercased())
                .font(.caption.weight(.semibold)).tracking(1.2).opacity(0.75)
            Label { Text(verbatim: verdict.title) } icon: { Image(systemName: verdict.symbol) }
                .font(.system(size: 28, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: verdict.detail).font(.callout).opacity(0.85)
            Text([Self.osVersion, system?.hardwareModel, system.map { String(localized: "\($0.logicalCPUCount) çekirdek · \(pocketBytes($0.physicalMemoryBytes))") }]
                    .compactMap { $0 }.joined(separator: "  ·  ") as String)
                .font(.subheadline).opacity(0.7)
            HStack(spacing: PocketSpacing.s) {
                Button { navigation.select(.performance) } label: {
                    Label("Sistem İzleme", systemImage: "waveform.path.ecg").padding(.horizontal, 4)
                }
                .buttonStyle(HeroButtonStyle(prominent: true))
                Button { navigation.select(.cleanup) } label: { Label("Temizlik", systemImage: "sparkles") }
                    .buttonStyle(HeroButtonStyle(prominent: false))
                if model.awakeSession?.active == true {
                    Label("Uyanık tutuluyor", systemImage: "cup.and.saucer.fill").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            .padding(.top, PocketSpacing.s)
        }
    }

    private func rings(_ system: SystemSnapshot?, _ volume: VolumeSnapshot?) -> some View {
        let memoryFraction = system.flatMap { snapshot in
            snapshot.usedMemoryBytes.map { Double($0) / Double(max(1, snapshot.physicalMemoryBytes)) }
        }
        let diskFraction = volume.map { Double(max(0, $0.totalBytes - $0.availableBytes)) / Double(max(1, $0.totalBytes)) }
        return HStack(spacing: PocketSpacing.l) {
            HeroRing(title: "CPU", value: model.cpuLabel, fraction: system?.cpuTotalPercent.map { $0 / 100 })
            HeroRing(title: "Bellek", value: memoryFraction.map { pocketPercent($0 * 100) } ?? "—", fraction: memoryFraction)
            HeroRing(title: "Disk", value: diskFraction.map { pocketPercent($0 * 100) } ?? "—", fraction: diskFraction)
        }
        .padding(PocketSpacing.l)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
    }

    // MARK: Panels

    private var storagePanel: some View {
        OverviewPanel(title: "Depolama", icon: PocketPage.storage.icon, tint: PocketPage.storage.tint,
                      action: "Disk Analizini Aç", perform: { navigation.select(.storage) }) {
            if let volume = model.system?.volumes.first {
                Text("\(pocketBytes(volume.availableBytes)) boş").font(.title2.weight(.semibold)).monospacedDigit()
                ProgressView(value: Double(max(0, volume.totalBytes - volume.availableBytes)), total: Double(max(1, volume.totalBytes)))
                    .tint(PocketTheme.disk)
                    .accessibilityLabel("\(volume.name) doluluk")
                Text("\(volume.name) · \(pocketBytes(volume.totalBytes)) toplam").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Disk bilgisi okunuyor…").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Temizlik").font(.callout.weight(.medium))
                    Text(files.junk.report.map { "\($0.itemCount.formatted()) öğe · \(pocketBytes($0.bytes)) temizlenebilir" }
                         ?? "Önbellek ve günlükleri inceleyerek başla.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("İncele") { navigation.select(.cleanup) }.controlSize(.small)
            }
        }
    }

    private var applicationsPanel: some View {
        OverviewPanel(title: "Uygulamalar", icon: PocketPage.applications.icon, tint: PocketPage.applications.tint,
                      action: "Uygulamaları Yönet", perform: { navigation.select(.applications) }) {
            if applications.loaded {
                Text("\(applications.applications.count) kurulu uygulama").font(.title2.weight(.semibold))
            } else if let failure = applications.failure {
                Text(verbatim: failure).font(.callout).foregroundStyle(.orange)
            } else {
                HStack(spacing: PocketSpacing.s) { ProgressView().controlSize(.small); Text("Uygulamalar inceleniyor…") }
                    .foregroundStyle(.secondary)
            }
            Text("Sürümleri ve kurulum kanallarını gör; kaldırmadan önce ilişkili dosyaları incele.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text(applications.updatesCheckedAt == nil ? "Güncellemeler henüz kontrol edilmedi"
                     : applications.updates.isEmpty ? "Homebrew uygulamaları güncel" : "\(applications.updates.count) Homebrew güncellemesi")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Güncellemeler") { applications.showUpdates = true; navigation.select(.applications) }.controlSize(.small)
            }
        }
    }

    private var powerPanel: some View {
        let power = model.system?.power
        return OverviewPanel(title: "Güç", icon: PocketPage.power.icon, tint: PocketPage.power.tint,
                             action: "Güç Merkezini Aç", perform: { navigation.select(.power) }) {
            Text(power?.batteryPresent == true
                 ? (power?.chargePercent.map { "Pil \(pocketPercent($0))" } ?? "Pil seviyesi okunuyor")
                 : "Prizden çalışıyor")
                .font(.title2.weight(.semibold))
            Text(power?.batteryPresent == true ? "Pil, termal durum ve uyku yönetimi."
                 : "Bu Mac’te dahili pil yok. Uyku yönetimi ve güç geçmişi kullanılabilir.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack {
                Label(model.awakeSession?.active == true ? "Uyanık tutma etkin" : "Otomatik uyku normal",
                      systemImage: model.awakeSession?.active == true ? "cup.and.saucer.fill" : "moon.zzz")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if model.awakeSession?.active == true {
                    Button("Durdur") { Task { await model.stopAwake() } }.controlSize(.small)
                } else {
                    Button("30 dk Uyanık Tut") { Task { await model.startAwake() } }.controlSize(.small)
                }
            }
        }
    }

    private var toolsPanel: some View {
        OverviewPanel(title: "Araç Kutusu", icon: PocketPage.tools.icon, tint: PocketPage.tools.tint,
                      action: "Tüm Araçları Aç", perform: { navigation.select(.tools) }) {
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                shortcut("Görev Yöneticisi", icon: "list.bullet.rectangle") { navigation.open(.taskManager) }
                shortcut("Sistem Raporları", icon: "doc.text.magnifyingglass") { navigation.open(.diagnostics) }
                shortcut("Yinelenen Dosyalar", icon: "doc.on.doc") { model.storage.scope = .duplicates; navigation.select(.storage) }
                shortcut("Pencere Geçişi", icon: "macwindow.on.rectangle") { navigation.open(.windowSwitcher) }
            }
        }
    }

    private func shortcut(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, PocketSpacing.xxs)
        }
        .buttonStyle(.plain)
    }
}

private struct OverviewPanel<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
    let action: LocalizedStringKey
    let perform: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                PocketIconTile(symbol: icon, tint: tint, size: 30)
                Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: perform) {
                    Label(action, systemImage: "arrow.up.right").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(Text(action))
                .accessibilityLabel(Text(action))
            }
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .pocketCard()
    }
}

private struct HeroRing: View {
    let title: LocalizedStringKey
    let value: String
    let fraction: Double?

    var body: some View {
        VStack(spacing: PocketSpacing.s) {
            ZStack {
                PocketRing(fraction: fraction ?? 0, color: .white, lineWidth: 8)
                    .environment(\.colorScheme, .dark)
                Text(verbatim: value).font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6).padding(PocketSpacing.s)
            }
            .frame(width: 78, height: 78)
            Text(title).font(.caption.weight(.semibold)).opacity(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: value))
    }
}

/// White-on-gradient buttons for the hero card.
private struct HeroButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(prominent ? PocketTheme.brand : .white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)), in: Capsule())
            .overlay { if !prominent { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.75) } }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}
