import AppKit
import MacPocketCore
import SwiftUI

// MARK: - Shared visuals

extension StorageCategory {
    var color: Color {
        switch self {
        case .applications: Color(hex: 0x7B5CFF)
        case .documents: Color(hex: 0x0A84FF)
        case .developer: Color(hex: 0xFF9F0A)
        case .appData: Color(hex: 0x5E5CE6)
        case .caches: Color(hex: 0xE8458B)
        case .logs: Color(hex: 0xA2845E)
        case .downloads: Color(hex: 0x30B0C7)
        case .photos: Color(hex: 0xFFC300)
        case .media: Color(hex: 0xFF453A)
        case .otherUser: Color(hex: 0x34C1A6)
        case .trash: Color(hex: 0x8E8E93)
        case .system: Color(light: 0xC4C7CE, dark: 0x5A5D66)
        }
    }
}

/// Indeterminate scan ring: a rotating arc around a glyph. Static when Reduce Motion is on.
struct PocketScanRing: View {
    var tint: Color
    var symbol: String
    var size: CGFloat = 132
    var active: Bool
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(active ? 0.14 : 0.85), lineWidth: size * 0.075)
            // A separate view so its spin state starts fresh every time scanning starts.
            if active { SpinningArc(tint: tint, lineWidth: size * 0.075) }
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.22), tint.opacity(0.04)], center: .center, startRadius: 0, endRadius: size * 0.42))
                .padding(size * 0.12)
            Image(systemName: symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: active)
        .accessibilityHidden(true)
    }
}

private struct SpinningArc: View {
    let tint: Color
    let lineWidth: CGFloat
    @State private var spin = false
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: reduceMotion ? 1 : 0.28)
            .stroke(AngularGradient(colors: [tint.opacity(reduceMotion ? 0.6 : 0), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

/// Short description of live scan progress.
@MainActor
func pocketScanProgressText(_ snapshot: StorageScanControl.Snapshot?) -> String {
    guard let snapshot, snapshot.visitedEntries > 0 else { return String(localized: "Hazırlanıyor…") }
    var text = String(localized: "\(snapshot.visitedEntries) öğe · \(pocketBytes(snapshot.measuredBytes))")
    if !snapshot.currentName.isEmpty { text += " · \(snapshot.currentName)" }
    return text
}

// MARK: - Page

struct StorageView: View {
    @ObservedObject var model: FileWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Disk Analizi", subtitle: subtitle, icon: "internaldrive") {
                Picker("Bölüm", selection: $model.storageTab) {
                    ForEach(StorageTab.allCases) { tab in
                        Label(tab.localizedTitle, systemImage: tab.symbol).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            switch model.storageTab {
            case .overview:
                StorageOverviewPanel(model: model.overview) { url in
                    model.storageTab = .lens
                    model.lens.scan(url)
                }
            case .lens: SpaceLensView(model: model.lens)
            case .files: FileWorkspaceView(model: model)
            }
        }
        .pocketPage()
    }

    private var subtitle: LocalizedStringKey {
        switch model.storageTab {
        case .overview: "Diskindeki alanın kategorilere göre dağılımı."
        case .lens: "Bir klasörün alanını haritada keşfet, büyük öğeleri bul."
        case .files: "Büyük, eski ve yinelenen dosyaları bul."
        }
    }
}

// MARK: - Volume overview

struct StorageOverviewPanel: View {
    @ObservedObject var model: StorageOverviewModel
    let openInLens: (URL) -> Void
    @State private var hovered: StorageCategory?
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                capacityCard
                if let failure = model.failure { PocketMessage(failure, tone: .critical) }
                if let report = model.report {
                    categoryGrid(report)
                } else if !model.scanning {
                    ContentUnavailableView {
                        Label("Kategorileri ölç", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("Uygulamalar, belgeler, önbellekler ve geliştirici verilerinin diskte gerçekte kapladığı alanı ölçer. Dosyalar değiştirilmez.")
                    } actions: {
                        Button("Ölçmeyi Başlat") { model.scan() }.buttonStyle(.pocketPrimary)
                    }
                    .padding(.vertical, PocketSpacing.xl)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, PocketSpacing.l)
        }
        .scrollIndicators(.automatic)
        .onAppear { model.loadIfNeeded() }
    }

    // MARK: Capacity

    private var capacityCard: some View {
        let volume = model.report?.volume ?? model.volume
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(volume?.name ?? "Disk").font(.headline)
                    if let volume {
                        Text("\(pocketBytes(volume.usedBytes)) kullanımda · \(pocketBytes(volume.totalBytes)) toplam")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: PocketSpacing.m)
                if let volume {
                    VStack(alignment: .trailing, spacing: PocketSpacing.xxs) {
                        Text(pocketBytes(volume.availableBytes)).font(.title.weight(.bold)).monospacedDigit()
                        Text("boş").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            capacityBar(volume)
                .frame(height: 22)
            if let report = model.report { legend(report) }
            Divider()
            statusRow(volume)
        }
        .pocketCard()
    }

    private func capacityBar(_ volume: VolumeCapacity?) -> some View {
        GeometryReader { proxy in
            let total = Double(max(1, volume?.totalBytes ?? 1))
            let segments: [(StorageCategory?, Int64)] = model.report.map { report in report.segments.map { ($0.category, $0.bytes) } }
                ?? [(nil, volume?.usedBytes ?? 0)]
            // Measured sizes can exceed used space (APFS clones are counted per copy); scale to fit.
            let used = max(Double(segments.reduce(0) { $0 + $1.1 }), 1)
            let usedFraction = min(1, Double(volume?.usedBytes ?? 0) / total)
            let scale = proxy.size.width * usedFraction / used
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let width = max(0, Double(segment.1) * scale - 1.5)
                    if width >= 1 {
                        Rectangle()
                            .fill(segment.0?.color ?? PocketPage.storage.tint)
                            .opacity(hovered == nil || hovered == segment.0 ? 1 : 0.35)
                            .frame(width: width)
                            .help(segment.0.map { Text(verbatim: "\($0.title): \(pocketBytes(segment.1))") } ?? Text("Kullanılan: \(pocketBytes(segment.1))"))
                            .onHover { inside in if inside { hovered = segment.0 } else if hovered == segment.0 { hovered = nil } }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(PocketTheme.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk doluluğu")
        .accessibilityValue(volume.map { Text("\(pocketBytes($0.usedBytes)) kullanımda, \(pocketBytes($0.availableBytes)) boş") } ?? Text(verbatim: ""))
    }

    private func legend(_ report: StorageOverviewReport) -> some View {
        // Wide enough for the longest category name ("Diğer Kullanıcı Dosyaları") plus its size.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: PocketSpacing.l, alignment: .leading)],
                  alignment: .leading, spacing: PocketSpacing.xs) {
            ForEach(report.segments, id: \.category) { segment in
                HStack(spacing: PocketSpacing.s) {
                    Circle().fill(segment.category.color).frame(width: 9, height: 9)
                    Text(segment.category.title).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: PocketSpacing.xs)
                    Text(pocketBytes(segment.bytes)).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.callout)
                .padding(.vertical, 2).padding(.horizontal, PocketSpacing.xs)
                .background(hovered == segment.category ? segment.category.color.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: PocketRadius.small))
                .onHover { inside in if inside { hovered = segment.category } else if hovered == segment.category { hovered = nil } }
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ volume: VolumeCapacity?) -> some View {
        HStack(spacing: PocketSpacing.m) {
            if model.scanning {
                ProgressView().controlSize(.small)
                Text(pocketScanProgressText(model.progress))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                Spacer(minLength: PocketSpacing.s)
                Button("İptal Et", role: .cancel) { model.cancel() }
            } else {
                if let report = model.report {
                    Label("Son ölçüm \(report.scannedAt.formatted(.relative(presentation: .named).locale(pocketLocale)))",
                          systemImage: "clock")
                        .help(Text("\(report.scannedAt.formatted(date: .complete, time: .standard)) · \(Int(report.duration.rounded())) sn"))
                    if report.isPartial {
                        PocketStatusBadge(text: "Kısmi sonuç", systemImage: PocketTone.warning.symbol, tone: .warning)
                            .help(partialHelp(report))
                    }
                } else {
                    Label("Kategoriler henüz ölçülmedi", systemImage: "clock")
                }
                if let volume, volume.purgeableBytes > 0 {
                    Text("· \(pocketBytes(volume.purgeableBytes)) temizlenebilir alan macOS tarafından gerektiğinde boşaltılır")
                        .lineLimit(1).truncationMode(.tail)
                        .help("Boşaltılabilir (purgeable) veri: iCloud’da da bulunan dosyalar, anlık görüntüler ve önbellekler.")
                }
                Spacer(minLength: PocketSpacing.s)
                Button(model.report == nil ? ("Ölç" as LocalizedStringKey) : "Yenile") { model.scan() }
                    .help("Kategorileri yeniden ölç")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func partialHelp(_ report: StorageOverviewReport) -> String {
        var lines: [String] = []
        if report.limitReached { lines.append(String(localized: "Süre veya öğe sınırına ulaşıldı.")) }
        for usage in report.categories where usage.measurement.inaccessibleCount > 0 {
            lines.append(String(localized: "\(usage.category.title): \(usage.measurement.inaccessibleCount) öğeye erişilemedi."))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Categories

    private func categoryGrid(_ report: StorageOverviewReport) -> some View {
        let used = Double(max(1, report.volume.usedBytes))
        let measured = report.categories.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Kategoriler", icon: "square.grid.2x2") {
                Text("Diskte kapladığı gerçek alan (ayrılmış boyut)")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: PocketSpacing.m, alignment: .top)],
                      alignment: .leading, spacing: PocketSpacing.m) {
                ForEach(measured) { usage in
                    StorageCategoryCard(usage: usage, share: Double(usage.bytes) / used, highlighted: hovered == usage.category,
                                        openInLens: openInLens)
                        .onHover { inside in if inside { hovered = usage.category } else if hovered == usage.category { hovered = nil } }
                }
                systemCard(report, share: Double(report.systemAndOtherBytes) / used)
            }
        }
    }

    private func systemCard(_ report: StorageOverviewReport, share: Double) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: StorageCategory.system.symbol, tint: Color(hex: 0x8E8E93), size: 34)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(StorageCategory.system.title).font(.headline)
                    Text("\(pocketPercent(share * 100)) kullanılan alanın").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(pocketBytes(report.systemAndOtherBytes)).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Text(verbatim: StorageCategory.system.detail + " " + String(localized: "Kullanılan alandan ölçülen kategoriler çıkarılarak hesaplanır."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard(padding: PocketSpacing.m)
    }
}

private struct StorageCategoryCard: View {
    let usage: StorageCategoryUsage
    let share: Double
    let highlighted: Bool
    let openInLens: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: usage.category.symbol, tint: usage.category.color, size: 34)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    HStack(spacing: PocketSpacing.xs) {
                        Text(usage.category.title).font(.headline)
                        if !usage.measurement.complete {
                            Image(systemName: PocketTone.warning.symbol).foregroundStyle(PocketTone.warning.color).font(.subheadline)
                                .help(usage.measurement.inaccessibleCount > 0
                                      ? Text("\(usage.measurement.inaccessibleCount) öğeye erişilemedi; boyut eksik olabilir.")
                                      : Text("Ölçüm sınıra ulaştı; boyut eksik olabilir."))
                        }
                    }
                    Text("\(usage.measurement.fileCount) dosya · \(pocketPercent(share * 100)) kullanılan alanın")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: PocketSpacing.s)
                Text(pocketBytes(usage.bytes)).font(.title3.weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: min(1, max(0, share))).tint(usage.category.color)
                .accessibilityHidden(true)
            if !usage.largestItems.isEmpty {
                VStack(spacing: PocketSpacing.xxs) {
                    ForEach(usage.largestItems.prefix(4)) { item in
                        StorageItemRow(item: item)
                    }
                }
            }
            HStack(spacing: PocketSpacing.s) {
                if let root = usage.measuredRoots.first {
                    Button {
                        openInLens(URL(fileURLWithPath: root))
                    } label: { Label("Space Lens", systemImage: "square.grid.3x3.square") }
                        .help("\((root as NSString).abbreviatingWithTildeInPath) klasörünü Space Lens’te aç")
                }
                if let root = usage.measuredRoots.first {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: root))
                    } label: { Label("Finder", systemImage: "folder") }
                        .help("Finder’da aç")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard(padding: PocketSpacing.m)
        .overlay {
            RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
                .strokeBorder(usage.category.color.opacity(highlighted ? 0.6 : 0), lineWidth: 1.5)
        }
        .help(usage.category.detail)
    }
}

private struct StorageItemRow: View {
    let item: StorageItemUsage

    var body: some View {
        let url = URL(fileURLWithPath: item.path)
        HStack(spacing: PocketSpacing.s) {
            Image(nsImage: PocketIconCache.icon(for: url)).resizable().scaledToFit().frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(FileManager.default.displayName(atPath: item.path)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: PocketSpacing.s)
            Text(pocketBytes(item.allocatedBytes)).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
        .contentShape(Rectangle())
        .help(item.path)
        .contextMenu {
            Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}
