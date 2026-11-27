import MacPocketCore
import SwiftUI

/// `spellsOutZero: false` keeps an empty value as "0 bytes" instead of "Zero KB".
private func byteText(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file, spellsOutZero: false)) }

private func signedByteText(_ bytes: Int64) -> String {
    (bytes >= 0 ? "+" : "−") + byteText(abs(bytes))
}

extension SystemDataSafety {
    var tone: PocketTone {
        switch self { case .safe: .success; case .review: .warning; case .manual: .neutral }
    }
}

extension Color {
    /// Secondary text for this page. The system's `.secondary` measures 3.95:1 on the card in light mode,
    /// short of the 4.5:1 WCAG AA asks for at caption and callout size; this one measures above it in both
    /// appearances.
    static var readableSecondary: Color { Color(nsColor: .labelColor).opacity(0.72) }
}

extension PocketTone {
    /// The tone's color darkened (light mode) or lightened (dark mode) toward the label color, so
    /// caption-size badge text reaches the 4.5:1 contrast WCAG AA asks for. The plain tone colors measure 2.1
    /// to 3.0:1 on their tinted badge.
    var readableTextColor: Color { color.mix(with: .primary, by: 0.55) }
}

/// Like `PocketStatusBadge`, with text that stays legible at caption size.
struct SystemDataBadge: View {
    let text: String
    var tone: PocketTone = .neutral

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tone.readableTextColor)
            .padding(.horizontal, PocketSpacing.s)
            .padding(.vertical, PocketSpacing.xxs + 1)
            .background(tone.color.opacity(0.12), in: Capsule())
    }
}

struct SystemDataView: View {
    @State private var model: SystemDataViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SystemDataViewModel.rememberChangesKey) private var rememberChanges = true

    init(model: SystemDataViewModel) { _model = State(initialValue: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Disk Röntgeni",
                              subtitle: "macOS’un “Sistem Verisi” dediği kovanın içini aç: her kalemin gerçek boyutunu, ne olduğunu ve silmenin neye mal olacağını gör.",
                              icon: "scope") {
                HStack(spacing: PocketSpacing.m) { headingActions }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    FullDiskAccessBanner(consequence: "Uygulama kapsayıcıları, Mail ve Safari verileri Tam Disk Erişimi olmadan ölçülemez; tarama eksik kalır.")
                    if case .scanning(let text) = model.phase {
                        ScanProgressCard(text: text, progress: model.scanProgress, found: model.items.count)
                    }
                    if let message = model.statusMessage { PocketMessage(message) }
                    if model.snapshotsMayHoldSpace {
                        HStack(alignment: .top, spacing: PocketSpacing.m) {
                            PocketMessage("Boş alan beklenen kadar artmadı: yerel Time Machine anlık görüntüleri silinen dosyaların alanını hâlâ tutuyor olabilir.", tone: .warning)
                            VStack(spacing: PocketSpacing.xs) {
                                Button("Anlık Görüntüleri Sil…") { model.removeSnapshots() }.buttonStyle(.pocketPrimary)
                                Button("Kapat") { model.dismissSnapshotNotice() }.buttonStyle(.link)
                            }
                        }
                    }
                    if let error = model.errorMessage { PocketMessage(error, error: true) }
                    if model.report == nil, !model.isScanning, model.items.isEmpty {
                        IntroCard { model.startScan() }
                    } else if model.report != nil, !model.isScanning, model.items.isEmpty {
                        ContentUnavailableView("Sistem Verisi temiz görünüyor", systemImage: "checkmark.seal",
                                               description: Text("Bilinen konumlarda ve büyük klasörlerde temizlenebilecek bir şey bulunmadı."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        SystemDataOverview(model: model)
                        // The page's sections, in the standard full-width tab bar under the summary.
                        GlassTabBar(tabs: [GlassTab(id: SystemDataViewModel.Tab.items, title: "Öğeler", symbol: "list.bullet"),
                                           GlassTab(id: .projects, title: "Projeler", symbol: "folder"),
                                           GlassTab(id: .history, title: "Geçmiş", symbol: "clock"),
                                           GlassTab(id: .automation, title: "Otomasyon", symbol: "gearshape.2")],
                                    selection: $model.tab)
                            .accessibilityLabel("Görünüm")
                        switch model.tab {
                        case .items: SystemDataItemsTab(model: model, searchFocus: $searchFocused)
                        case .projects: SystemDataProjectsTab(model: model)
                        case .history: SystemDataHistoryTab(model: model, rememberChanges: $rememberChanges)
                        case .automation: SystemDataAutomationTab(rememberChanges: rememberChanges)
                        }
                    }
                }
                .padding(.bottom, PocketSpacing.l)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // The confirmation lives in the page, docked where the selection summary was, so the list
                // stays in view.
                if let preview = model.pendingPreview {
                    SystemDataConfirmation(preview: preview, onCancel: { model.cancelRemoval() }) { Task { await model.confirmRemoval() } }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                } else {
                    SelectionTray(model: model)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: model.pendingPreview?.id)
        }
        .pocketPage()
        .background {
            // ⌘F jumps to the search field from any tab.
            Button("Ara") { model.tab = .items; searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .onChange(of: rememberChanges) { _, value in Task { await model.setRememberChanges(value) } }
        .task {
            if let tab = SystemDataRouting.consumeRequestedTab() { model.tab = tab }
            await model.loadArchives()
            if model.report == nil, !model.isScanning { model.startScan() }
        }
    }

    @ViewBuilder private var headingActions: some View {
        if model.isScanning {
            Button("Taramayı Durdur") { model.cancelScan() }
                .keyboardShortcut(".", modifiers: .command)
        } else {
            if let scannedAt = model.report?.scannedAt {
                // Results survive leaving the page; say how fresh they are instead of rescanning on every
                // visit.
                TimelineView(.everyMinute) { _ in
                    Text("Son tarama \(scannedAt.formatted(.relative(presentation: .named)))")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Button { model.startScan() } label: {
                Label(model.report == nil ? "Taramayı Başlat" : "Yeniden Tara", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.pocketPrimary)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.removing || model.shrinkingID != nil || model.archivingID != nil)
        }
    }
}

extension SystemDataRemovalPreview: Identifiable {
    public var id: String { lines.map(\.id).joined(separator: "|") + mode.rawValue }
}

// MARK: - Intro and overview

private struct IntroCard: View {
    let start: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Text("Sistem Verisi neyle doluyor?").font(.headline)
            Text("Depolama ayarlarındaki “Sistem Verisi” çoğu geliştirici Mac’inde en büyük satırdır ve içine bakılamaz. Disk Röntgeni simülatörleri, Xcode önbelleklerini, paket yöneticilerini, Docker’ı, yapay zekâ modellerini, günlükleri ve proje derleme klasörlerini tek tek ölçer. Hiçbir şeyi sen seçip onaylamadan silmez.")
                .foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
            Button("Taramayı Başlat", action: start).buttonStyle(.pocketPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

/// Lays children out in as many equal columns as fit (at least one, at most one per child), filling the whole
/// width.
struct TileRow: Layout {
    var minimumWidth: CGFloat
    var spacing: CGFloat

    /// SwiftUI probes layouts with infinite, zero and even NaN widths; none of them may reach an integer
    /// conversion.
    static func columnCount(width: CGFloat, count: Int, minimumWidth: CGFloat, spacing: CGFloat) -> Int {
        guard count > 0 else { return 1 }
        guard width.isFinite, width > 0, minimumWidth.isFinite else { return count }
        let fit = ((width + spacing) / (minimumWidth + spacing)).rounded(.down)
        guard fit.isFinite else { return count }
        // Capped before converting: a huge finite width would overflow Int otherwise.
        return max(1, Int(min(fit, CGFloat(count))))
    }

    private func columns(width: CGFloat, count: Int) -> Int {
        Self.columnCount(width: width, count: count, minimumWidth: minimumWidth, spacing: spacing)
    }

    private func heights(_ subviews: Subviews, columns: Int, columnWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start ..< min(start + columns, subviews.count)].map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimumWidth * CGFloat(max(1, subviews.count))
        let count = columns(width: width, count: subviews.count)
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let rows = heights(subviews, columns: count, columnWidth: columnWidth)
        return CGSize(width: width, height: rows.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(width: bounds.width, count: subviews.count)
        let columnWidth = (bounds.width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let rows = heights(subviews, columns: count, columnWidth: columnWidth)
        var y = bounds.minY
        for (rowIndex, start) in stride(from: 0, to: subviews.count, by: count).enumerated() {
            for offset in 0 ..< min(count, subviews.count - start) {
                subviews[start + offset].place(at: CGPoint(x: bounds.minX + CGFloat(offset) * (columnWidth + spacing), y: y), anchor: .topLeading,
                                               proposal: ProposedViewSize(width: columnWidth, height: rows[rowIndex]))
            }
            y += rows[rowIndex] + spacing
        }
    }
}

private struct ScanProgressCard: View {
    let text: String
    let progress: SystemDataScanProgress?
    let found: Int

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.s) {
                ProgressView().controlSize(.small)
                Text(verbatim: text).font(.callout.weight(.medium))
                Spacer(minLength: PocketSpacing.m)
                Text("\(found) kalem").font(.callout).foregroundStyle(Color.readableSecondary).monospacedDigit()
            }
            ProgressView(value: progress?.fraction ?? 0)
            if let progress {
                HStack(spacing: PocketSpacing.m) {
                    Text("Aşama \(progress.phaseIndex)/\(SystemDataScanProgress.phaseCount)")
                    Text("\(progress.visitedEntries.formatted()) dosya tarandı").monospacedDigit()
                    if !progress.currentName.isEmpty {
                        Text(verbatim: progress.currentName).lineLimit(1).truncationMode(.middle)
                    }
                }
                .font(.caption).foregroundStyle(Color.readableSecondary)
            }
        }
        .pocketCard(padding: PocketSpacing.m)
        .accessibilityElement(children: .combine)
    }
}

private struct SystemDataOverview: View {
    let model: SystemDataViewModel

    var body: some View {
        let report = model.report
        let items = model.items
        let safe = items.filter { $0.safety == .safe && $0.isRemovable }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let review = items.filter { $0.safety == .review }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let manual = items.filter { $0.safety == .manual || !$0.isRemovable && $0.safety == .safe }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let total = max(1, safe + review + manual)
        let cleanable = model.isScanning ? [] : model.cleanableNow
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            // Three across while they fit, then fewer; the row always fills the width (no empty column on a
            // wide window).
            TileRow(minimumWidth: 250, spacing: PocketSpacing.m) {
                PocketMetricTile(title: "Sistem Verisi", value: "\(byteText(items.reduce(0) { $0 + $1.sizeBytes }))",
                                 detail: weeklyDetail, icon: "scope", color: PocketTheme.accent)
                PocketMetricTile(title: "Hemen boşaltılabilir", value: "\(byteText(safe))",
                                 detail: "Güvenli olarak işaretli kalemlerin toplamı", icon: "checkmark.shield", color: PocketTone.success.color)
                // Free space comes with the finished report; until then say so instead of showing a false "0
                // bytes".
                Group {
                    if let report {
                        PocketMetricTile(title: "Boş alan", value: "\(byteText(report.freeBytes))",
                                         detail: "macOS’un geri verebileceği tahmini \(byteText(report.purgeableBytes)) ayrıca var",
                                         icon: "internaldrive", color: PocketTheme.disk)
                    } else {
                        PocketMetricTile(title: "Boş alan", value: "—", detail: "Tarama bitince gösterilir",
                                         icon: "internaldrive", color: PocketTheme.disk)
                    }
                }
                    .help("Tahmini alan, macOS’un gerektiğinde geri verebileceği miktardır; planlayabileceğin gerçek boş alan değildir. Dosya yazdığında kullanılmayabilir ve kendiliğinden yeniden dolabilir.")
            }
            if !cleanable.isEmpty {
                HStack(spacing: PocketSpacing.m) {
                    VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                        Text("\(byteText(cleanable.reduce(0) { $0 + $1.sizeBytes })) parola istemeden tek dokunuşla temizlenebilir").font(.headline)
                        Text("\(cleanable.count) Güvenli kalem; her komut silmeden önce gösterilir ve onayını bekler.")
                            .font(.callout).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: PocketSpacing.m)
                    Button { model.cleanSafeNow() } label: { Label("Güvenlileri Temizle…", systemImage: "sparkles") }
                        .buttonStyle(.pocketPrimary).disabled(model.removing)
                }
                .pocketCard(padding: PocketSpacing.m)
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        segment(safe, total: total, width: proxy.size.width, color: PocketTone.success.color)
                        segment(review, total: total, width: proxy.size.width, color: PocketTone.warning.color)
                        segment(manual, total: total, width: proxy.size.width, color: .secondary)
                    }
                }
                .frame(height: 10).clipShape(Capsule())
                HStack(spacing: PocketSpacing.l) {
                    legend("Güvenli", byteText(safe), PocketTone.success.color)
                    legend("İncele", byteText(review), PocketTone.warning.color)
                    legend("Elle", byteText(manual), .secondary)
                }
                .font(.caption)
            }
            .accessibilityElement(children: .combine)
            if !model.isScanning, let report, report.isPartial {
                PocketMessage(report.complete
                              ? "\(report.unreadablePlaces) yer okunamadı (izin yok); bunların boyutu toplamlara dahil değil. Tam Disk Erişimi daha eksiksiz bir tarama sağlar."
                              : "Tarama süre sınırına ulaştı; liste eksik olabilir.", tone: .warning)
            }
        }
    }

    private var weeklyDetail: LocalizedStringKey {
        guard let change = model.weeklyChange else { return "Önceki taramalar biriktikçe haftalık değişim görünür" }
        return "Geçen haftaya göre \(signedByteText(change))"
    }

    @ViewBuilder private func segment(_ value: Int64, total: Int64, width: CGFloat, color: Color) -> some View {
        if value > 0 { Rectangle().fill(color).frame(width: max(2, width * CGFloat(value) / CGFloat(total))) }
    }

    private func legend(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        HStack(spacing: PocketSpacing.xs) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title).foregroundStyle(Color.readableSecondary)
            Text(verbatim: value).monospacedDigit()
        }
    }
}

// MARK: - Items

private struct SystemDataItemsTab: View {
    let model: SystemDataViewModel
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        let selection = model.selection
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketSearchField("Ada, açıklamaya veya gruba göre ara", text: Bindable(model).filter, focus: searchFocus)
                Picker("Sırala", selection: Bindable(model).sort) {
                    Text("Boyut").tag(SystemDataViewModel.Sort.size)
                    Text("Boşta kalma").tag(SystemDataViewModel.Sort.idle)
                    Text("Ad").tag(SystemDataViewModel.Sort.name)
                }
                .pickerStyle(.menu).fixedSize()
                .accessibilityLabel(Text("Sırala"))
                Menu {
                    ForEach(SystemDataViewModel.freeUpSizes, id: \.self) { size in
                        Button("\(size) GB") { model.freeUp(gigabytes: size) }
                    }
                } label: {
                    Label("Yer aç…", systemImage: "externaldrive.badge.minus")
                }
                .menuStyle(.button)
                .fixedSize().disabled(model.items.isEmpty)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Belirli bir miktarda yer aç"))
                .accessibilityHint(Text("İstediğin miktarı seç; en az endişe verici kalemler seçilir"))
                Button("Güvenlileri Seç") { model.toggleSafe() }.disabled(model.items.isEmpty)
            }
            if let note = model.freeUpNote { PocketMessage(note, tone: .accent) }
            ForEach(model.groups, id: \.group) { entry in
                GroupSection(model: model, group: entry.group, items: entry.items, bytes: entry.bytes, selection: selection)
            }
            if model.groups.isEmpty, model.report != nil {
                ContentUnavailableView("Eşleşen kalem yok", systemImage: "magnifyingglass",
                                       description: Text("Aramayı değiştir veya gizlenen kalemleri geri getir."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            if !model.hiddenIDs.isEmpty {
                Button("\(model.hiddenIDs.count) gizli kalemi geri getir") { model.unhideAll() }.buttonStyle(.link)
            }
        }
    }
}

private struct GroupSection: View {
    let model: SystemDataViewModel
    let group: SystemDataGroup
    let items: [SystemDataItem]
    let bytes: Int64
    let selection: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let expanded = model.expandedGroups.contains(group)
        let alert = model.growthAlerts.first { $0.group == group }
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    if expanded { model.expandedGroups.remove(group) } else { model.expandedGroups.insert(group) }
                }
            } label: {
                HStack(spacing: PocketSpacing.m) {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(Color.readableSecondary).frame(width: 12)
                    Image(systemName: group.symbol).foregroundStyle(PocketTheme.accent).frame(width: 22)
                    Text(group.localizedTitle).font(.headline)
                    Text("\(items.count)").font(.caption).foregroundStyle(Color.readableSecondary)
                    if let alert {
                        PocketStatusBadge(text: "Yakın zamanda büyüdü \(signedByteText(alert.growthBytes))", systemImage: "arrow.up.right", tone: .warning)
                    }
                    Spacer()
                    GroupBar(items: items, scale: model.largestGroupBytes)
                    Text(verbatim: byteText(bytes)).font(.headline).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(group.localizedTitle), \(byteText(bytes))"))
            .accessibilityHint(Text(expanded ? "Daralt" : "Genişlet"))
            if expanded {
                Divider().padding(.vertical, PocketSpacing.s)
                ForEach(items) { item in
                    SystemDataRow(model: model, item: item, selected: selection.contains(item.id))
                    if item.id != items.last?.id { Divider() }
                }
            }
        }
        .pocketCard(padding: PocketSpacing.m)
    }
}

private struct GroupBar: View {
    let items: [SystemDataItem]
    let scale: Int64

    var body: some View {
        let total = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let safe = items.filter { $0.safety == .safe && $0.isRemovable }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let review = items.filter { $0.safety == .review }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let width: CGFloat = 120
        let full = scale > 0 ? width * CGFloat(total) / CGFloat(scale) : 0
        HStack(spacing: 0) {
            Rectangle().fill(PocketTone.success.color).frame(width: pieces(safe, total, full))
            Rectangle().fill(PocketTone.warning.color).frame(width: pieces(review, total, full))
            Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: pieces(total - safe - review, total, full))
            Spacer(minLength: 0)
        }
        .frame(width: width, height: 6).background(Color.secondary.opacity(0.12)).clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func pieces(_ part: Int64, _ total: Int64, _ full: CGFloat) -> CGFloat {
        total > 0 ? full * CGFloat(part) / CGFloat(total) : 0
    }
}

private struct SystemDataRow: View {
    let model: SystemDataViewModel
    let item: SystemDataItem
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let expanded = model.expandedItems.contains(item.id)
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                Toggle(isOn: Binding(get: { selected }, set: { _ in model.toggle(item) })) { EmptyView() }
                    .toggleStyle(.checkbox).labelsHidden().disabled(!item.isRemovable)
                    .accessibilityLabel(Text(verbatim: item.title))
                    .accessibilityValue(Text(verbatim: "\(byteText(item.sizeBytes)), \(item.safety.localizedTitle), \(item.regeneration.localizedTitle)"))
                    .accessibilityHint(Text(verbatim: item.detail))
                // The whole text block is one big button (a row in Finder selects on click). The checkbox
                // already speaks for it, so VoiceOver skips this copy.
                Button { model.toggle(item) } label: {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    HStack(spacing: PocketSpacing.s) {
                        Text(verbatim: item.title).font(.body.weight(.medium)).lineLimit(2)
                        SystemDataBadge(text: item.safety.localizedTitle, tone: item.safety.tone)
                    }
                    Text(verbatim: item.detail).font(.callout).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
                    metaLine
                    if let warning = item.warning {
                        Label { Text(verbatim: warning) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!item.isRemovable)
                .accessibilityHidden(true)
                Spacer(minLength: PocketSpacing.m)
                trailing
            }
            if expanded { details }
        }
        .padding(.vertical, PocketSpacing.xs)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { actions }
        .accessibilityAction(named: Text("Ayrıntıları göster")) { toggleDetails() }
        .accessibilityAction(named: Text("Gizle")) { model.hide(item) }
    }

    private var metaLine: some View {
        HStack(spacing: PocketSpacing.m) {
            Text(item.regeneration.localizedTitle)
            if let days = item.idleDays(), days >= 14 { Text("\(days) gündür dokunulmadı") }
            if let change = model.change(of: item), abs(change) >= 50_000_000 {
                Text(verbatim: signedByteText(change) + " " + String(localized: "bu hafta")).foregroundStyle(change > 0 ? .orange : .secondary)
            }
        }
        .font(.caption).foregroundStyle(Color.readableSecondary)
    }

    private var trailing: some View {
        HStack(spacing: PocketSpacing.m) {
            let trend = model.trend(of: item)
            if trend.count > 2 {
                PocketSparkline(values: trend, color: PocketTheme.accent, ceiling: nil, floor: 0).frame(width: 56, height: 22)
            }
            // Always in the view tree so keyboard and VoiceOver users reach them; only shown (and clickable)
            // on hover.
            HStack(spacing: PocketSpacing.m) {
                Button { toggleDetails() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .help("En büyük girdileri göster").accessibilityLabel(Text("Ayrıntıları göster"))
                if !item.paths.isEmpty {
                    Button { model.reveal(item) } label: { Image(systemName: "magnifyingglass") }
                        .help("Finder’da göster").accessibilityLabel(Text("Finder’da göster"))
                }
                Button { model.hide(item) } label: { Image(systemName: "eye.slash") }
                    .help("Sonraki taramalarda gizle").accessibilityLabel(Text("Gizle"))
            }
            // Faint at rest, full on hover: always visible, so keyboard and VoiceOver users find them too.
            .opacity(hovering || expanded ? 1 : 0.4)
            Text(verbatim: item.sizeKnown ? byteText(item.sizeBytes) : "—")
                .font(.body.weight(.semibold)).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
            if model.shrinkingID == item.id {
                ProgressView().controlSize(.small).help("Sıkıştırılıyor…")
            } else if item.isShrinkable {
                Button { Task { await model.shrink([item]) } } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .help("Sil yerine sıkıştırılmış olarak sakla; hiçbir yol değişmez").accessibilityLabel(Text("Küçült"))
                    .opacity(hovering ? 1 : 0.4)
            }
            if model.archivingID == item.id {
                ProgressView().controlSize(.small).help("Arşivleniyor…")
            } else if item.isArchivable {
                Button { Task { await model.archive([item]) } } label: { Image(systemName: "archivebox") }
                    .help("Sil yerine sıkıştırılmış arşive al").accessibilityLabel(Text("Arşivle"))
                    .opacity(hovering ? 1 : 0.4)
            }
            if item.isRemovable {
                Button { model.requestRemoval(of: [item]) } label: { Image(systemName: "trash") }
                    .help("Sil…").accessibilityLabel(Text("Sil")).tint(.red)
            }
        }
        .buttonStyle(.borderless)
    }

    private var expanded: Bool { model.expandedItems.contains(item.id) }

    private func toggleDetails() {
        if expanded { model.expandedItems.remove(item.id) } else { model.expandedItems.insert(item.id) }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            if case .manual(let hint) = item.action {
                Text(verbatim: hint).font(.callout).textSelection(.enabled)
            } else if case .run(let command) = item.action {
                Text("Çalışacak komut").font(.caption).foregroundStyle(Color.readableSecondary)
                Text(verbatim: command.displayLine).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            if let entries = model.breakdowns[item.id] {
                ForEach(entries) { entry in
                    HStack {
                        Text(verbatim: entry.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(verbatim: byteText(entry.bytes)).monospacedDigit().foregroundStyle(Color.readableSecondary)
                    }
                    .font(.callout)
                }
            } else if !item.paths.isEmpty {
                ProgressView().controlSize(.small)
            }
            ForEach(item.paths, id: \.self) { path in
                Text(verbatim: path).font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.readableSecondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        }
        .padding(.leading, 28)
        .task { await model.loadBreakdown(for: item) }
    }

    @ViewBuilder private var actions: some View {
        if item.isRemovable { Button("Sil…") { model.requestRemoval(of: [item]) } }
        if item.isShrinkable { Button("Küçült (Sil Yerine Sıkıştır)") { Task { await model.shrink([item]) } } }
        if item.isArchivable { Button("Arşivle (Tek Dosyaya Al)") { Task { await model.archive([item]) } } }
        if !item.paths.isEmpty { Button("Finder’da Göster") { model.reveal(item) } }
        Button("Ayrıntıları Göster") { toggleDetails() }
        Button("Sonraki Taramalarda Gizle") { model.hide(item) }
    }
}

// MARK: - Projects

private struct SystemDataProjectsTab: View {
    let model: SystemDataViewModel
    @AppStorage(SystemDataExternalVolumes.defaultsKey) private var externalProjects = false

    var body: some View {
        let selection = model.selection
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack {
                Text("Her satır bir proje ve bağımlılık ile derleme klasörlerinin toplam maliyeti. Kaynak dosyalara dokunulmaz.")
                    .font(.callout).foregroundStyle(Color.readableSecondary)
                Spacer()
                Button("60 Gündür Boşta Olanları Seç") { model.selectIdleProjects() }
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Toggle("Harici disklerdeki projeleri de ara", isOn: $externalProjects)
                Text("Takılı disklerin en üstündeki Developer, Projects, Projeler, Code ve dev klasörlerine bakılır. Time Machine diskleri, ağ paylaşımları, salt okunur birimler ve Mac’in kendi diskleri taranmaz; diskin geri kalanına dokunulmaz. Değişiklik sonraki taramada geçerli olur.")
                    .font(.caption).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard(padding: PocketSpacing.m)
            ForEach(model.projects, id: \.path) { project in
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    HStack(spacing: PocketSpacing.m) {
                        Toggle(isOn: Binding(get: { Set(project.items.map(\.id)).isSubset(of: selection) },
                                             set: { _ in model.toggleProject(project.items) })) { EmptyView() }
                            .toggleStyle(.checkbox).labelsHidden().accessibilityLabel(Text(verbatim: project.name))
                        VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                            Text(verbatim: project.name).font(.headline)
                            Text(verbatim: project.path).font(.system(.caption, design: .monospaced)).foregroundStyle(Color.readableSecondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if let days = project.idleDays {
                            Text(days >= 60 ? "\(days) gündür boşta" : "Yakın zamanda çalışıldı").font(.caption)
                                .foregroundStyle(days >= 60 ? .orange : .secondary)
                        }
                        Text(verbatim: byteText(project.bytes)).font(.headline).monospacedDigit()
                        if project.items.contains(where: \.isShrinkable) {
                            Button { Task { await model.shrink(project.items) } } label: { Label("Küçült", systemImage: "arrow.down.right.and.arrow.up.left") }
                                .disabled(model.shrinkingID != nil || model.archivingID != nil)
                                .help("Bu projenin derleme klasörlerini sıkıştırılmış olarak sakla; yollar ve kaynak dosyalar değişmez")
                        }
                        if project.items.contains(where: \.isArchivable) {
                            Button { Task { await model.archive(project.items) } } label: { Label("Arşivle", systemImage: "archivebox") }
                                .disabled(model.archivingID != nil).help("Bu projenin derleme klasörlerini sıkıştırılmış arşive al; kaynak dosyalara dokunulmaz")
                        }
                    }
                    ForEach(project.items) { item in
                        HStack {
                            Text(verbatim: item.title.components(separatedBy: " — ").first ?? item.title).font(.callout)
                            Text(item.regeneration.localizedTitle).font(.caption).foregroundStyle(Color.readableSecondary)
                            Spacer()
                            Text(verbatim: byteText(item.sizeBytes)).font(.callout).monospacedDigit().foregroundStyle(Color.readableSecondary)
                        }
                        .padding(.leading, 28)
                    }
                }
                .pocketCard(padding: PocketSpacing.m)
            }
            if !model.archives.isEmpty {
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    Text("Arşivler").font(.headline)
                    ForEach(model.archives) { record in
                        HStack(spacing: PocketSpacing.m) {
                            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                                Text(verbatim: record.title).font(.callout.weight(.medium))
                                Text(verbatim: record.originalPath).font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.readableSecondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text("\(byteText(record.originalBytes)) → \(byteText(record.archiveBytes))").font(.caption).monospacedDigit().foregroundStyle(Color.readableSecondary)
                            Button("Geri Yükle") { Task { await model.restore(record) } }
                            Button("Arşivi Sil", role: .destructive) { Task { await model.deleteArchive(record) } }
                        }
                    }
                }
                .pocketCard(padding: PocketSpacing.m)
            }
            if model.projects.isEmpty {
                ContentUnavailableView("Proje derleme klasörü bulunmadı", systemImage: "folder.badge.gearshape",
                                       description: Text("Developer, Projects, Code, dev, Desktop ve Documents klasörlerinde 20 MB’tan büyük node_modules, .build, Pods, target gibi klasörler aranır."))
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }
}

// MARK: - History

private struct SystemDataHistoryTab: View {
    let model: SystemDataViewModel
    @Binding var rememberChanges: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                Toggle("Neyin değiştiğini hatırla", isOn: $rememberChanges)
                Text("Her tarama ve silme bu Mac’te küçük bir dosyada tutulur; kalemlerin boyut değişimi, trend çizgisi ve “geri geldi” bildirimi bundan üretilir. Kapatırsan dosya silinir. Hiçbir şey Mac’inden çıkmaz.")
                    .font(.caption).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .pocketCard(padding: PocketSpacing.m)
            if rememberChanges {
                section("Silinip geri gelenler") {
                    ForEach(model.returnedItems, id: \.itemID) { returned in
                        HStack {
                            Text(verbatim: returned.title)
                            Spacer()
                            Text("Silinen \(byteText(returned.deletedBytes)) → şimdi \(byteText(returned.currentBytes))")
                                .foregroundStyle(Color.readableSecondary).monospacedDigit()
                        }
                    }
                    if model.returnedItems.isEmpty { Text("Henüz geri gelen bir şey yok.").foregroundStyle(Color.readableSecondary) }
                }
                section("En çok büyüyenler") {
                    ForEach(model.growthAlerts, id: \.group) { alert in
                        HStack {
                            Label(alert.group.localizedTitle, systemImage: alert.group.symbol)
                            Spacer()
                            Text("Olağan \(byteText(alert.medianBytes)) → şimdi \(byteText(alert.currentBytes))")
                                .foregroundStyle(.orange).monospacedDigit()
                        }
                    }
                    if model.growthAlerts.isEmpty { Text("Olağandışı büyüyen bir grup yok.").foregroundStyle(Color.readableSecondary) }
                }
                section("Sildiklerin") {
                    ForEach(Array(model.history.deletions.suffix(20).reversed()), id: \.date) { deletion in
                        HStack {
                            Text(verbatim: deletion.title)
                            Spacer()
                            Text(verbatim: byteText(deletion.bytes)).monospacedDigit()
                            Text(deletion.date, format: .dateTime.day().month().hour().minute()).foregroundStyle(Color.readableSecondary)
                        }
                    }
                    if model.history.deletions.isEmpty { Text("Henüz silme yok.").foregroundStyle(Color.readableSecondary) }
                }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text(title).font(.headline)
            content().font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard(padding: PocketSpacing.m)
    }
}

// MARK: - Automation

private struct SystemDataAutomationTab: View {
    let rememberChanges: Bool
    @State private var settings = SystemDataAutomationSettings.load(from: .standard)
    @State private var state = SystemDataAutomationState.load(from: .standard)
    @State private var notificationsDenied = false
    @AppStorage(SimulatorShutdown.defaultsKey) private var shutdownSimulators = SimulatorShutdown.defaultEnabled
    @AppStorage(SystemDataMenuBarStyle.key) private var menuBarStyle = SystemDataMenuBarStyle.off.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Text("Hepsi isteğe bağlıdır ve kapalı başlar. MacPocket’ın kendiliğinden yaptığı tek şey, açarsan haftalık güvenli temizliktir.")
                .font(.callout).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                Toggle("Günde bir kez arka planda tara", isOn: $settings.dailyScan)
                Toggle("Boş alan azalınca uyar", isOn: $settings.lowSpaceAlert)
                if settings.lowSpaceAlert {
                    Picker("Uyarı eşiği", selection: $settings.lowSpaceGigabytes) {
                        ForEach(SystemDataAutomationSettings.allowedLowSpaceGigabytes, id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    .pickerStyle(.menu).fixedSize()
                    Text("Aşağı inerken bir kez uyarır; boş alan eşiğin üstüne çıkana kadar sessiz kalır.")
                        .font(.caption).foregroundStyle(Color.readableSecondary)
                }
                Toggle("Bir grup olağandışı büyüyünce uyar", isOn: $settings.growthAlert)
                Toggle("Haftalık özet gönder", isOn: $settings.weeklySummary)
                Divider()
                Toggle("Her hafta Güvenli öğeleri otomatik temizle", isOn: $settings.autoClean)
                Text("Yalnızca “Güvenli” olan, parola istemeyen ve sahibi uygulaması kapalı öğeler kaldırılır; “İncele” öğelerine hiç dokunulmaz. İzlediğin bir taramada çalışmaz.")
                    .font(.caption).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .pocketCard(padding: PocketSpacing.m)
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Picker("Menü çubuğunda göster", selection: $menuBarStyle) {
                    Text("Kapalı").tag(SystemDataMenuBarStyle.off.rawValue)
                    Text("Yalnız simge").tag(SystemDataMenuBarStyle.icon.rawValue)
                    Text("Sistem Verisi boyutu").tag(SystemDataMenuBarStyle.systemData.rawValue)
                    Text("Boş alan").tag(SystemDataMenuBarStyle.freeSpace.rawValue)
                }
                .pickerStyle(.menu).fixedSize()
                Text("Son taramanın değerlerini gösterir; kendiliğinden tarama yapmaz. Günlük tarama açıksa sayı kendini yeniler.")
                    .font(.caption).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard(padding: PocketSpacing.m)
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Toggle("Mac kapanırken açık simülatörleri hemen kapat", isOn: $shutdownSimulators)
                Text("Açık bir iOS simülatörü kapatma isteğini yok sayar ve macOS onu 33 saniye bekleyip sonlandırır. Kapanış başlayınca simülatörleri kapatmak bu beklemeyi kaldırır.")
                    .font(.caption).foregroundStyle(Color.readableSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard(padding: PocketSpacing.m)
            if (settings.growthAlert || settings.weeklySummary) && !rememberChanges {
                PocketMessage("Büyüme uyarısı ve haftalık özet için Geçmiş sekmesinde “Neyin değiştiğini hatırla” açık olmalı.", tone: .warning)
            }
            if notificationsDenied {
                PocketMessage("Bildirimler kapalı; uyarıları görmek için Sistem Ayarları’nda MacPocket’a izin ver.", tone: .warning)
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                lastRun("Son otomatik tarama", state.lastScan)
                lastRun("Son otomatik temizlik", state.lastAutoClean)
            }
            .font(.caption).foregroundStyle(Color.readableSecondary)
        }
        .onChange(of: settings) { old, new in
            new.save(to: .standard)
            let alertsTurnedOn = (new.lowSpaceAlert && !old.lowSpaceAlert) || (new.growthAlert && !old.growthAlert)
                || (new.weeklySummary && !old.weeklySummary) || (new.autoClean && !old.autoClean)
            if alertsTurnedOn { Task { _ = await PocketAlertNotifier.requestAuthorization(); notificationsDenied = await PocketAlertNotifier.authorizationDenied() } }
        }
        .task { notificationsDenied = await PocketAlertNotifier.authorizationDenied(); state = SystemDataAutomationState.load(from: .standard) }
    }

    @ViewBuilder private func lastRun(_ title: LocalizedStringKey, _ date: Date?) -> some View {
        HStack {
            Text(title)
            if let date { Text(date, format: .dateTime.day().month().hour().minute()) } else { Text("henüz yok") }
        }
    }
}

// MARK: - Selection tray and confirmation

private struct SelectionTray: View {
    let model: SystemDataViewModel

    var body: some View {
        if !model.selection.isEmpty {
            HStack(spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("\(model.selection.count) öğe seçili · \(byteText(model.selectedBytes))").font(.headline).monospacedDigit()
                    if model.selectedOffScreenCount > 0 {
                        Text("\(model.selectedOffScreenCount) seçili öğe filtre yüzünden görünmüyor").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("Seçimi Kaldır") { model.clearSelection() }
                Button { model.requestRemoval() } label: { Label("Seçilenleri Sil…", systemImage: "trash") }
                    .buttonStyle(.pocketPrimary).disabled(model.removing)
            }
            .padding(PocketSpacing.m)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

/// The confirmation, inline: every operation exactly as it will run, then the choice.
private struct SystemDataConfirmation: View {
    let preview: SystemDataRemovalPreview
    let onCancel: () -> Void
    let onConfirm: () -> Void
    /// Open for a short list; a long one starts folded so the page behind (the selected rows) stays in view.
    @State private var showsOperations: Bool

    init(preview: SystemDataRemovalPreview, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.preview = preview
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _showsOperations = State(initialValue: preview.lines.count <= 3)
    }

    var body: some View {
        let permanent = preview.mode == .deletePermanently
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(permanent ? "Seçilen öğeler kalıcı olarak silinsin mi?" : "Seçilen öğeler Çöp’e taşınsın mı?")
                        .font(.headline)
                    Text("\(preview.lines.count) öğe · toplam \(byteText(preview.totalBytes))").font(.callout).foregroundStyle(Color.readableSecondary).monospacedDigit()
                }
                Spacer()
                Button { showsOperations.toggle() } label: {
                    Label(showsOperations ? "Komutları Gizle" : "Komutları Göster", systemImage: showsOperations ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.borderless)
            }
            if !showsOperations {
                // Folded, the panel still says what is about to go.
                Text(verbatim: preview.lines.map(\.title).joined(separator: " · "))
                    .font(.caption).foregroundStyle(Color.readableSecondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if showsOperations {
                ScrollView {
                    VStack(alignment: .leading, spacing: PocketSpacing.s) {
                        ForEach(preview.lines) { line in
                            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                                HStack {
                                    Text(verbatim: line.title).font(.callout.weight(.semibold))
                                    SystemDataBadge(text: line.safety.localizedTitle, tone: line.safety.tone)
                                    Text(line.regeneration.localizedTitle).font(.caption).foregroundStyle(Color.readableSecondary)
                                    Spacer()
                                    Text(verbatim: byteText(line.sizeBytes)).monospacedDigit()
                                }
                                ForEach(line.operations, id: \.self) { operation in
                                    Text(verbatim: operation).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .padding(PocketSpacing.xs).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                }
                                if let warning = line.warning {
                                    Label { Text(verbatim: warning) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                if preview.networkBytes > 0 {
                    Text("Bunun \(byteText(preview.networkBytes)) kadarı geri gelmek için internet ister.").font(.caption).foregroundStyle(Color.readableSecondary)
                }
                if preview.requiresAdministrator {
                    Text("\(preview.administratorLineCount) işlem yönetici parolası ister; mümkün olan her şey tek istemde toplanır.")
                        .font(.caption).foregroundStyle(Color.readableSecondary)
                }
            }
            HStack {
                RemovalModePicker()
                Button("Planı Kopyala") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preview.copyText, forType: .string)
                }
                Spacer()
                // Permanent deletion cannot be undone, so Return cancels; deleting takes a click or ⌘⌫.
                // Moving to the Trash is recoverable, so there Return confirms as usual.
                Button("Vazgeç", action: onCancel).keyboardShortcut(permanent ? .defaultAction : .cancelAction)
                Button(permanent ? "Sil" : "Çöp’e Taşı", role: .destructive, action: onConfirm)
                    .keyboardShortcut(permanent ? KeyboardShortcut(.delete, modifiers: .command) : .defaultAction)
            }
        }
        .padding(PocketSpacing.m)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Silme onayı"))
    }
}
