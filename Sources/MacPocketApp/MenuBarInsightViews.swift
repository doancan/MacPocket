import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    /// Switches the grouped popover to another tab; a no-op in a separate item's popover.
    @Entry var selectMenuBarTab: @MainActor (MenuBarModule) -> Void = { _ in }
}

// MARK: - Overview

/// The grouped popover's first page: health at a glance and one tile per everyday metric, each opening its tab.
struct OverviewMenuDetail: View {
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    let binary: Bool
    @Environment(\.selectMenuBarTab) private var select

    var body: some View {
        let system = model.system
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            if let system {
                HealthSummary(report: MenuBarInsights.shared.health(system, processes: model.processes)) { select(.health) }
                Grid(horizontalSpacing: PocketSpacing.s, verticalSpacing: PocketSpacing.s) {
                    GridRow {
                        tile(.cpu, value: percent(system.cpuTotalPercent),
                             series: history.samples.compactMap { $0.cpuTotal.map { $0 / 100 } })
                        tile(.memory, value: percent(system.usedMemoryBytes.map { Double($0) / Double(max(1, system.physicalMemoryBytes)) * 100 }),
                             series: history.samples.compactMap(\.memoryFraction))
                    }
                    GridRow {
                        tile(.disk, value: diskFree(system), series: [], fill: diskUsed(system))
                        tile(.network, value: "↓ " + MenuBarFormatter.rate(system.network?.receivedBytesPerSecond, binary: binary),
                             series: normalized(history.samples.map { $0.networkDown ?? 0 }))
                    }
                }
                RecentEvents { select(.timeline) }
                VStack(spacing: PocketSpacing.xs + 1) {
                    if let hottest = system.temperatures.flatMap(TemperatureSummary.hottest) {
                        InfoRow(title: "En sıcak sensör", value: pocketCelsius(hottest.celsius))
                    }
                    InfoRow(title: "Çalışma süresi", value: pocketDuration(system.uptimeSeconds))
                }
                .menuBarSection()
            } else {
                PocketProgressRow(message: "Ölçümler alınıyor…").menuBarSection()
            }
        }
    }

    /// Every tile has the same parts (title, value, a graphic) so the grid's rows line up.
    private func tile(_ module: MenuBarModule, value: String, series: [Double], fill: Double? = nil) -> some View {
        Button { select(module) } label: {
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                HStack(spacing: PocketSpacing.xs + 2) {
                    PocketIconTile(symbol: module.symbol, tint: module.tint, size: 18)
                    Text(module.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(value).font(.title2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                Group {
                    if let fill {
                        CapacityBar(fraction: fill, tint: module.tint).frame(maxHeight: .infinity, alignment: .bottom)
                    } else if series.count > 1 {
                        PocketSparkline(values: series, color: module.tint, ceiling: 1, floor: 0)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .menuBarSection()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(module.title): \(value)"))
        .accessibilityHint("Ayrıntıları göster")
    }

    private func diskUsed(_ system: SystemSnapshot) -> Double? {
        guard let startup = system.volumes.first(where: { $0.path == "/" }) ?? system.volumes.first, startup.totalBytes > 0 else { return nil }
        return 1 - Double(startup.availableBytes) / Double(startup.totalBytes)
    }

    private func percent(_ value: Double?) -> String { value.map { MenuBarFormatter.percent($0, decimals: false) } ?? "—" }

    private func diskFree(_ system: SystemSnapshot) -> String {
        guard let startup = system.volumes.first(where: { $0.path == "/" }) ?? system.volumes.first else { return "—" }
        return MenuBarFormatter.bytes(Double(startup.availableBytes), binary: binary)
    }

    private func normalized(_ values: [Double]) -> [Double] {
        let ceiling = max(65_536, values.max() ?? 0)
        return values.map { $0 / ceiling }
    }
}

/// The last few events, opening the Events page; nothing when there are none yet.
private struct RecentEvents: View {
    let open: () -> Void
    private let insights = MenuBarInsights.shared

    var body: some View {
        let recent = Array(insights.events.events.suffix(3).reversed())
        if !recent.isEmpty {
            Button(action: open) {
                VStack(alignment: .leading, spacing: PocketSpacing.xs + 2) {
                    HStack {
                        SectionTitle(title: "Son olaylar")
                        Image(systemName: "chevron.right").font(.callout).foregroundStyle(.tertiary)
                    }
                    ForEach(recent) { event in
                        HStack(spacing: PocketSpacing.s) {
                            Image(systemName: event.kind.symbol).foregroundStyle(event.kind.tint).frame(width: 18)
                            Text(event.kind.title).font(.callout)
                            Spacer(minLength: PocketSpacing.s)
                            Text(event.date, format: .relative(presentation: .named)).font(.callout).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .menuBarSection()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Score ring and the most serious issue; opens the Health page.
private struct HealthSummary: View {
    let report: HealthReport
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: PocketSpacing.m) {
                HealthGauge(score: report.score).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.verdict).font(.headline)
                    Text(report.issues.first.map(\.title) ?? String(localized: "Her şey yolunda"))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.callout).foregroundStyle(.tertiary)
            }
            .menuBarSection()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Sağlık ayrıntılarını göster")
    }
}

private struct HealthGauge: View {
    let score: Int
    var body: some View {
        Gauge(value: Double(score), in: 0...100) {
            EmptyView()
        } currentValueLabel: {
            Text("\(score)").font(.callout.weight(.semibold)).monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(HealthReport.color(score))
        .accessibilityLabel("Sağlık puanı")
        .accessibilityValue("\(score) / 100")
    }
}

// MARK: - Health

/// "Why is my Mac slow?": the score, then each issue with what it means and one action that addresses it.
struct HealthMenuDetail: View {
    var model: PocketModel
    @Environment(\.selectMenuBarTab) private var select
    @Environment(\.closeMenuBarPopover) private var close

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            if let system = model.system {
                let report = MenuBarInsights.shared.health(system, processes: model.processes)
                HStack(spacing: PocketSpacing.m) {
                    HealthGauge(score: report.score).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.verdict).font(.title3.weight(.semibold))
                        Text(report.issues.isEmpty ? String(localized: "Mac’i yavaşlatan bir şey görünmüyor.")
                                                   : String(localized: "\(report.issues.count) konu dikkat istiyor."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(report.issues) { issue in issueRow(issue) }
                if report.issues.isEmpty {
                    Label("İşlemci, bellek, ısı ve disk normal aralıkta.", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green).menuBarSection()
                }
            } else {
                PocketProgressRow(message: "Ölçümler alınıyor…").menuBarSection()
            }
        }
    }

    private func issueRow(_ issue: HealthIssue) -> some View {
        HStack(alignment: .top, spacing: PocketSpacing.s + 2) {
            Image(systemName: issue.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.title3).foregroundStyle(issue.severity == .critical ? Color.red : Color.orange)
                .accessibilityLabel(issue.severity == .critical ? "Kritik" : "Uyarı")
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.body.weight(.semibold))
                Text(issue.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(issue.actionTitle) { act(issue) }.buttonStyle(.link).font(.callout)
            }
            Spacer(minLength: 0)
        }
        .menuBarSection()
    }

    private func act(_ issue: HealthIssue) {
        switch issue.kind {
        case .cpuBusy: select(.cpu)
        case .memoryPressure, .swap: select(.memory)
        case .thermal: select(.power)
        case .diskFillingSoon: select(.disk)
        case .diskLow:
            close()
            model.navigation.select(.cleanup)
            model.openMainWindow?()
        }
    }
}

extension HealthReport {
    var verdict: String {
        switch score {
        case 85...: String(localized: "Sağlıklı")
        case 60..<85: String(localized: "Dikkat")
        default: String(localized: "Sorunlu")
        }
    }

    static func color(_ score: Int) -> Color { score >= 85 ? .green : score >= 60 ? .orange : .red }
}

extension HealthIssue {
    var title: String {
        switch kind {
        case .cpuBusy: String(localized: "İşlemci yoğun")
        case .memoryPressure: String(localized: "Bellek baskısı yüksek")
        case .swap: String(localized: "Takas alanı büyüdü")
        case .thermal: String(localized: "Mac ısınıyor")
        case .diskLow: String(localized: "Başlangıç diskinde yer az")
        case .diskFillingSoon: String(localized: "Disk dolmak üzere")
        }
    }

    var explanation: String {
        switch kind {
        case .cpuBusy:
            if let subject { String(localized: "Çalışmayı bekleyen iş çekirdek sayısını aşıyor; en çok \(subject) kullanıyor.") }
            else { String(localized: "Çalışmayı bekleyen iş çekirdek sayısını aşıyor.") }
        case .memoryPressure: String(localized: "macOS belleği sıkıştırıyor; uygulamalar yavaşlayabilir.")
        case .swap:
            String(localized: "Diske takas edilen bellek: \(MenuBarFormatter.bytes(value ?? 0, binary: true)). Ağır uygulamaları kapatmak yardımcı olur.")
        case .thermal: String(localized: "Sistem ısıyı düşürmek için işlemciyi yavaşlatıyor olabilir.")
        case .diskLow:
            String(localized: "Boş alan %\(Int(((value ?? 0) * 100).rounded())); güncellemeler ve takas alanı için yer gerekir.")
        case .diskFillingSoon:
            String(localized: "Son haftanın hızıyla yaklaşık \(Int((value ?? 0).rounded())) gün içinde dolacak.")
        }
    }

    var actionTitle: String {
        switch kind {
        case .cpuBusy: String(localized: "Süreçleri göster")
        case .memoryPressure, .swap: String(localized: "Bellek kullanımını göster")
        case .thermal: String(localized: "Güç ve fanı göster")
        case .diskLow: String(localized: "Temizliği aç")
        case .diskFillingSoon: String(localized: "Diski göster")
        }
    }
}

// MARK: - Timeline

/// What happened to the Mac recently, newest first, grouped by day.
struct TimelineMenuDetail: View {
    private let insights = MenuBarInsights.shared

    var body: some View {
        let events = Array(insights.events.events.reversed().prefix(60))
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            if events.isEmpty {
                VStack(spacing: PocketSpacing.s) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Henüz olay yok").font(.headline)
                    Text("Uyku ve uyanma, ağ kopmaları, ısınma, bellek baskısı ve disk takılıp çıkarılması burada listelenir.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PocketSpacing.l)
            } else {
                ForEach(groupedByDay(events), id: \.day) { group in
                    VStack(alignment: .leading, spacing: PocketSpacing.xs + 2) {
                        SectionTitle(title: LocalizedStringKey(group.title))
                        ForEach(group.events) { event in row(event) }
                    }
                    .menuBarSection()
                }
            }
        }
    }

    private func row(_ event: SystemEvent) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: event.kind.symbol).font(.body).foregroundStyle(event.kind.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.kind.title).font(.callout)
                if let detail = event.detail { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: PocketSpacing.s)
            Text(event.date.formatted(date: .omitted, time: .shortened)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private struct DayGroup { let day: Date; let title: String; let events: [SystemEvent] }

    private func groupedByDay(_ events: [SystemEvent]) -> [DayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [SystemEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(event)
        }
        return order.map { day in
            let title = calendar.isDateInToday(day) ? String(localized: "Bugün")
                : calendar.isDateInYesterday(day) ? String(localized: "Dün")
                : day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(pocketLocale))
            return DayGroup(day: day, title: title, events: byDay[day] ?? [])
        }
    }
}

extension SystemEvent.Kind {
    var title: String {
        switch self {
        case .sleep: String(localized: "Uyku")
        case .wake: String(localized: "Uyandı")
        case .networkLost: String(localized: "İnternet bağlantısı koptu")
        case .networkRestored: String(localized: "İnternet bağlantısı geri geldi")
        case .thermalRaised: String(localized: "Isı yükseldi")
        case .thermalNormal: String(localized: "Isı normale döndü")
        case .memoryPressureCritical: String(localized: "Bellek baskısı kritik")
        case .memoryPressureNormal: String(localized: "Bellek baskısı düştü")
        case .diskMounted: String(localized: "Disk takıldı")
        case .diskUnmounted: String(localized: "Disk çıkarıldı")
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.fill"
        case .wake: "sun.max.fill"
        case .networkLost: "wifi.slash"
        case .networkRestored: "wifi"
        case .thermalRaised: "thermometer.high"
        case .thermalNormal: "thermometer.medium"
        case .memoryPressureCritical, .memoryPressureNormal: "memorychip"
        case .diskMounted: "externaldrive.badge.plus"
        case .diskUnmounted: "externaldrive.badge.minus"
        }
    }

    var tint: Color {
        switch self {
        case .sleep: .indigo
        case .wake: .orange
        case .networkLost, .memoryPressureCritical, .thermalRaised: .red
        case .networkRestored, .thermalNormal, .memoryPressureNormal: .green
        case .diskMounted, .diskUnmounted: .blue
        }
    }
}

// MARK: - Launcher

/// One favorite: an app, a folder, a file or a web address.
struct LauncherItem: Codable, Identifiable, Equatable {
    var id = UUID()
    let url: URL
}

/// Favorites, kept in user defaults in the order the user added them.
@MainActor @Observable
final class LauncherStore {
    static let shared = LauncherStore()
    private static let key = "MacPocket.menubar.launcher"
    /// A grid the popover shows without scrolling: four rows of four.
    static let capacity = 16

    private(set) var items: [LauncherItem]

    init(defaults: UserDefaults = .standard) {
        items = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([LauncherItem].self, from: $0) } ?? []
    }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url))
        let new = urls.filter { !known.contains($0) }.map { LauncherItem(url: $0) }
        items = Array((items + new).prefix(Self.capacity))
        save()
    }

    func remove(_ item: LauncherItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Favorite apps, folders and web addresses one click away. Add with the button or by dropping from Finder.
struct LauncherMenuDetail: View {
    private let store = LauncherStore.shared
    @Environment(\.closeMenuBarPopover) private var close
    @State private var dropTargeted = false
    @State private var addingLink = false
    @State private var link = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PocketSpacing.s), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s + 2) {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: PocketSpacing.s) {
                        Image(systemName: "star").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Favori ekle").font(.headline)
                        Text("Uygulama, klasör veya dosyaları buraya sürükle ya da Ekle ile seç.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PocketSpacing.l)
                } else {
                    LazyVGrid(columns: columns, spacing: PocketSpacing.m) {
                        ForEach(store.items) { item in tile(item) }
                    }
                }
            }
            .menuBarSection()
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                store.add(urls)
                return !urls.isEmpty
            } isTargeted: { dropTargeted = $0 }
            HStack {
                Button("Ekle…", systemImage: "plus") { choose() }
                Button("Bağlantı ekle…", systemImage: "link") { addingLink = true }
                    .popover(isPresented: $addingLink) { linkForm }
                Spacer()
                Text("\(store.items.count)/\(LauncherStore.capacity)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.items.count >= LauncherStore.capacity)
        }
    }

    private func tile(_ item: LauncherItem) -> some View {
        Button {
            close()
            NSWorkspace.shared.open(item.url)
        } label: {
            VStack(spacing: PocketSpacing.xs) {
                if item.url.isFileURL {
                    PocketAppIcon(url: item.url, size: 40)
                } else {
                    Image(systemName: "globe").font(.title).foregroundStyle(Color.accentColor).frame(width: 40, height: 40)
                }
                Text(verbatim: name(item)).font(.caption).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.url.isFileURL ? item.url.path : item.url.absoluteString)
        .contextMenu {
            if item.url.isFileURL {
                Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            }
            Button("Favorilerden Kaldır", role: .destructive) { store.remove(item) }
        }
    }

    private var linkForm: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text("Web adresi").font(.headline)
            TextField("https://", text: $link).frame(width: 240).onSubmit(addLink)
            HStack {
                Spacer()
                Button("Vazgeç") { addingLink = false }
                Button("Ekle", action: addLink).keyboardShortcut(.defaultAction).disabled(validLink == nil)
            }
        }
        .padding(PocketSpacing.m)
    }

    /// Accepts only web addresses; anything else (a typo, a file path) is not added.
    private var validLink: URL? {
        let text = link.trimmingCharacters(in: .whitespaces)
        let candidate = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil else { return nil }
        return url
    }

    private func addLink() {
        guard let url = validLink else { return }
        store.add([url])
        link = ""
        addingLink = false
    }

    private func name(_ item: LauncherItem) -> String {
        guard item.url.isFileURL else { return item.url.host() ?? item.url.absoluteString }
        return FileManager.default.displayName(atPath: item.url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Favorilere Ekle")
        close()
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        store.add(panel.urls)
    }
}
