import AppKit
import MacPocketCore
import SwiftUI

/// Resolves cache folder names such as `com.example.App` to the installed app's name and icon.
@MainActor
private enum CleanupOwnerCache {
    private static var cache: [String: URL?] = [:]

    static func application(for name: String) -> URL? {
        if let cached = cache[name] { return cached }
        let url = name.contains(".") && !name.hasPrefix(".") ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) : nil
        cache[name] = url
        return url
    }
}

extension CleanupGroup {
    var symbol: String {
        switch self {
        case .system: "gearshape.2.fill"
        case .developer: "hammer.fill"
        case .packages: "shippingbox.fill"
        case .user: "person.crop.circle.fill"
        case .separate: "externaldrive.fill"
        case .trash: "trash.fill"
        }
    }
}

struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    @Environment(\.pocketTint) private var tint
    @State private var confirmClean = false
    @State private var confirmEmptyTrash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Temizlik", subtitle: "Önbellekleri, günlükleri ve geliştirici artıklarını bul; seçtiklerini Çöp’e taşı.",
                                  icon: "sparkles") {
                    HStack(spacing: PocketSpacing.s) {
                        Picker("Eski indirilenler", selection: $model.downloadsAgeDays) {
                            Text("30 günden eski").tag(30)
                            Text("90 günden eski").tag(90)
                            Text("180 günden eski").tag(180)
                            Text("1 yıldan eski").tag(365)
                        }
                        .fixedSize()
                        .disabled(model.busy)
                        .help("Eski İndirilenler bu süreden uzun süredir dokunulmamış öğeleri listeler. Tarama sırasında uygulanır.")
                        if model.report != nil, !model.busy {
                            Button("Yeniden Tara") { model.scan() }.help("Tüm konumları yeniden tara")
                        }
                    }
                }
                hero
                if let failure = model.failure { PocketMessage(failure, tone: .critical) }
                if let summary = model.summary { summaryCard(summary) }
                if let report = model.report, !model.scanning {
                    results(report)
                } else if !model.scanning {
                    catalogPreview
                }
            }
            .padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .alert("Seçilen öğeler Çöp’e taşınsın mı?", isPresented: $confirmClean) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp’e Taşı", role: .destructive) { model.clean() }
        } message: {
            Text(cleanConfirmationText)
        }
        .sheet(isPresented: $confirmEmptyTrash) {
            EmptyTrashConfirmation(itemCount: model.trashReport?.items.count ?? 0, bytes: model.trashReport?.bytes ?? 0) {
                confirmEmptyTrash = false
                model.emptyTrash()
            } cancel: { confirmEmptyTrash = false }
        }
    }

    private var cleanConfirmationText: String {
        var text = String(localized: "\(model.selectedItems.count) öğe · \(pocketBytes(model.selectedBytes)). Öğeler Çöp’e taşınır; Finder’daki Çöp’ten geri alabilirsin. Alan, Çöp boşaltılınca açılır.")
        if model.selectedWarnings > 0 {
            text += "\n\n" + String(localized: "\(model.selectedWarnings) öğenin uygulaması açık veya incelenmesi gerekiyor.")
        }
        return text
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: PocketSpacing.xl) {
            PocketScanRing(tint: tint, symbol: model.summary != nil ? "checkmark" : "sparkles", size: 128, active: model.busy)
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                if model.scanning {
                    Text("Taranıyor…").font(.title.weight(.bold))
                    Text(pocketScanProgressText(model.progress)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1)
                    if model.stalled {
                        Label("Bekleniyor: \(model.progress?.currentName ?? ""). macOS bir izin penceresi göstermiş olabilir; yanıt verince tarama sürer.",
                              systemImage: "hand.raised.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    Button("İptal Et", role: .cancel) { model.cancel() }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                } else if model.working {
                    Text("Temizleniyor…").font(.title.weight(.bold))
                    Text("Her öğe taşınmadan hemen önce yeniden doğrulanıyor.").font(.callout).foregroundStyle(.secondary)
                } else if let report = model.report {
                    Text(pocketBytes(report.bytes)).font(.system(size: 40, weight: .bold)).monospacedDigit()
                    Text("\(report.itemCount) öğe bulundu · \(pocketBytes(model.selectedBytes)) seçili")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    HStack(spacing: PocketSpacing.s) {
                        Button {
                            confirmClean = true
                        } label: {
                            Label(model.selectedBytes > 0 ? ("Temizle · \(pocketBytes(model.selectedBytes))" as LocalizedStringKey) : "Temizle", systemImage: "sparkles")
                                .padding(.horizontal, PocketSpacing.s)
                        }
                        .buttonStyle(.pocketPrimary)
                        .tint(tint)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selectedItems.isEmpty)
                        .help("Seçili öğeleri Çöp’e taşı")
                        if report.limitReached {
                            PocketStatusBadge(text: "Kısmi tarama", systemImage: PocketTone.warning.symbol, tone: .warning)
                                .help("Süre veya öğe sınırına ulaşıldı; bazı boyutlar eksik olabilir.")
                        }
                    }
                    Text("Tarama \(report.scannedAt.formatted(date: .omitted, time: .shortened)) · \(Int(report.duration.rounded())) sn")
                        .font(.subheadline).foregroundStyle(.tertiary)
                } else {
                    Text("Sistem Çöpü").font(.title.weight(.bold))
                    Text("Önbellekler, günlükler, Xcode verileri ve paket yöneticisi indirmeleri. Tarama hiçbir dosyayı değiştirmez.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.scan()
                    } label: {
                        Label("Tara", systemImage: "magnifyingglass").padding(.horizontal, PocketSpacing.m)
                    }
                    .buttonStyle(.pocketPrimary)
                    .tint(tint)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(PocketSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.2), lineWidth: 0.75) }
    }

    // MARK: Summary

    private func summaryCard(_ summary: CleanupSummary) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                Image(systemName: summary.itemCount > 0 ? "checkmark.seal.fill" : PocketTone.warning.symbol)
                    .font(.title2).foregroundStyle(summary.itemCount > 0 ? PocketTone.success.color : PocketTone.warning.color)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    switch summary.kind {
                    case .movedToTrash:
                        Text("\(summary.itemCount) öğe Çöp’e taşındı · \(pocketBytes(summary.bytes))").font(.headline)
                        Text("Geri alınabilir: Finder’daki Çöp’ten geri koyabilirsin. Disk alanı Çöp boşaltılınca açılır.")
                            .font(.callout).foregroundStyle(.secondary)
                    case .emptiedTrash:
                        Text("Çöp boşaltıldı: \(summary.itemCount) öğe · \(pocketBytes(summary.bytes))").font(.headline)
                        Text("Bu öğeler kalıcı olarak silindi ve geri alınamaz.").font(.callout).foregroundStyle(.secondary)
                    }
                    if let delta = summary.availableDelta {
                        (delta > 0 ? Text("Boş alan ölçümü: +\(pocketBytes(delta))") : Text("Boş alan ölçümü: değişmedi"))
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            .help("İşlemden önce ve sonra okunan boş disk alanı farkı. APFS anlık görüntüleri alanı bir süre tutabilir.")
                    }
                }
                Spacer(minLength: PocketSpacing.s)
                if summary.kind == .movedToTrash, let trash = model.trashReport, !trash.items.isEmpty {
                    Button("Çöpü Boşalt…") { confirmEmptyTrash = true }
                }
                Button { model.dismissSummary() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Özeti kapat")
            }
            if !summary.failures.isEmpty {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Taşınamayanlar").font(.callout.weight(.semibold))
                    ForEach(summary.failures, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
        }
        .pocketCard(padding: PocketSpacing.m)
    }

    // MARK: Before the first scan

    private var catalogPreview: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Taranacak konumlar", icon: "list.bullet")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: PocketSpacing.m, alignment: .top)], spacing: PocketSpacing.m) {
                ForEach(model.targets.filter { !$0.isTrash }) { target in
                    HStack(alignment: .top, spacing: PocketSpacing.m) {
                        PocketIconTile(symbol: target.symbol, tint: tint, size: 30)
                        VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                            HStack(spacing: PocketSpacing.xs) {
                                Text(target.title).font(.callout.weight(.semibold))
                                SafetyBadge(safety: target.safety)
                            }
                            Text(target.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
                }
            }
            Label("Eski indirilenler \(model.downloadsAgeDays) günden eski öğeleri kapsar.", systemImage: "calendar")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Results

    private func results(_ report: CleanupReport) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xl) {
            ForEach(CleanupGroup.allCases) { group in
                let targets = report.targets.filter { $0.target.group == group && $0.state != .missing }
                if !targets.isEmpty {
                    VStack(alignment: .leading, spacing: PocketSpacing.s) {
                        PocketSectionHeader(group.title, icon: group.symbol) {
                            HStack(spacing: PocketSpacing.s) {
                                if group == .separate { Text("Toplama dahil değil").font(.subheadline).foregroundStyle(.secondary) }
                                Text(pocketBytes(targets.reduce(0) { $0 + $1.bytes })).monospacedDigit()
                            }
                        }
                        ForEach(targets) { target in
                            if target.target.isTrash {
                                trashCard(target)
                            } else {
                                CleanupTargetCard(model: model, target: target)
                            }
                        }
                    }
                }
            }
            let missing = report.targets.filter { $0.state == .missing }
            if !missing.isEmpty {
                Label("Bu Mac’te bulunmayan konumlar: \(missing.map(\.target.title).formatted(.list(type: .and).locale(pocketLocale)))", systemImage: "minus.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func trashCard(_ target: CleanupTargetReport) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: target.target.symbol, tint: Color(hex: 0x8E8E93), size: 34)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(target.target.title).font(.headline)
                    Text(target.target.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: PocketSpacing.s)
                VStack(alignment: .trailing, spacing: PocketSpacing.xxs) {
                    Text(pocketBytes(target.bytes)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text("\(target.items.count) öğe").font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Çöpü Boşalt…", role: .destructive) { confirmEmptyTrash = true }
                    .disabled(target.items.isEmpty || model.busy)
                    .help("Çöp’teki öğeleri kalıcı olarak sil")
            }
            if case .inaccessible(let message) = target.state {
                accessMessage(message)
                Button("Çöp’ü Finder’da Aç") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
                }
                .controlSize(.small)
            } else if target.items.isEmpty {
                Label("Çöp Kutusu boş.", systemImage: "checkmark.circle").font(.callout).foregroundStyle(PocketTone.success.color)
            }
        }
        .pocketCard(padding: PocketSpacing.m)
    }
}

/// Grants access through System Settings when a location needs Full Disk Access.
@ViewBuilder
private func accessMessage(_ message: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.s) {
        Label(message, systemImage: "lock.fill").font(.callout).foregroundStyle(PocketTone.warning.color)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: PocketSpacing.s)
        Button("Ayarları Aç") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
        .controlSize(.small)
    }
}

private struct SafetyBadge: View {
    let safety: CleanupSafety
    var body: some View {
        PocketStatusBadge(text: safety.title, systemImage: safety == .safe ? "checkmark.shield" : "eye",
                          tone: safety == .safe ? .success : .warning)
            .help(safety == .safe ? Text("Uygulamalar bu öğeleri gerektiğinde yeniden oluşturur.")
                  : Text("Gerekli olabilecek veriler içerebilir; seçmeden önce incele."))
    }
}

// MARK: - Target card

private struct CleanupTargetCard: View {
    @ObservedObject var model: CleanupModel
    let target: CleanupTargetReport
    @Environment(\.pocketTint) private var tint
    @PocketReduceMotion private var reduceMotion

    private var expanded: Bool { model.expanded.contains(target.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(PocketSpacing.m)
            if expanded, !target.items.isEmpty {
                Divider()
                itemList
            }
        }
        .pocketCard(padding: 0, radius: PocketRadius.large)
    }

    private var header: some View {
        let state = model.selectionState(of: target)
        return VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                Toggle("", isOn: Binding(get: { state == .all }, set: { model.setTarget(target, selected: $0) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .disabled(target.items.isEmpty || model.busy)
                    .opacity(target.target.isManagedSeparately ? 0 : 1)
                    .allowsHitTesting(!target.target.isManagedSeparately)
                    .overlay {
                        if state == .some {
                            // Mixed state: AppKit draws a dash for NSControl.StateValue.mixed; mimic it.
                            RoundedRectangle(cornerRadius: 3).fill(Color.accentColor).frame(width: 14, height: 14)
                                .overlay(Rectangle().fill(.white).frame(width: 8, height: 2))
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("\(target.target.title) tümünü seç")
                PocketIconTile(symbol: target.target.symbol, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    HStack(spacing: PocketSpacing.xs) {
                        Text(target.target.title).font(.headline)
                        SafetyBadge(safety: target.target.safety)
                        if !target.complete {
                            Image(systemName: PocketTone.warning.symbol).font(.subheadline).foregroundStyle(PocketTone.warning.color)
                                .help("Bazı öğeler tam ölçülemedi.")
                        }
                    }
                    Text(target.target.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: PocketSpacing.s)
                VStack(alignment: .trailing, spacing: PocketSpacing.xxs) {
                    Text(pocketBytes(target.bytes)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text(detailLine).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { model.toggleExpanded(target.id) } } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(target.items.isEmpty)
                .accessibilityLabel(expanded ? Text("Öğeleri gizle") : Text("Öğeleri göster"))
                .help(expanded ? Text("Öğeleri gizle") : Text("Öğeleri göster"))
            }
            switch target.state {
            case .inaccessible(let message): accessMessage(message)
            case .symbolicLink:
                Label("Bu konum bir sembolik bağlantı; güvenlik için takip edilmez.", systemImage: "link")
                    .font(.callout).foregroundStyle(.secondary)
            case .ready where target.items.isEmpty:
                Label("Temiz. Kaldırılacak öğe yok.", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(PocketTone.success.color)
            default: EmptyView()
            }
        }
    }

    private var detailLine: String {
        let selected = model.selectedBytes(in: target)
        let base = String(localized: "\(target.items.count) öğe · \(target.fileCount) dosya")
        return selected > 0 && selected != target.bytes ? String(localized: "\(pocketBytes(selected)) seçili · \(base)") : base
    }

    private var itemList: some View {
        LazyVStack(spacing: 0) {
            ForEach(target.items.prefix(300)) { item in
                CleanupItemRow(item: item, selected: model.selection.contains(item.id), disabled: model.busy,
                               selectable: !target.target.isManagedSeparately, isProtected: model.protection.contains(item.id),
                               toggle: { model.toggle(item) }, toggleProtection: { model.toggleProtection(item) })
            }
            if target.items.count > 300 {
                Text("İlk 300 öğe gösteriliyor; tümünü seçmek için başlıktaki kutuyu kullan.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(PocketSpacing.s)
            }
        }
        .padding(.vertical, PocketSpacing.xs)
    }
}

private struct CleanupItemRow: View {
    let item: CleanupItem
    let selected: Bool
    let disabled: Bool
    let selectable: Bool
    let isProtected: Bool
    let toggle: () -> Void
    let toggleProtection: () -> Void

    var body: some View {
        let owner = CleanupOwnerCache.application(for: item.name)
        HStack(spacing: PocketSpacing.s) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden().disabled(disabled || isProtected)
                .opacity(selectable ? 1 : 0)
                .allowsHitTesting(selectable)
                .accessibilityLabel("\(item.name) seç")
            Group {
                if let owner {
                    Image(nsImage: PocketIconCache.icon(for: owner)).resizable()
                } else {
                    Image(nsImage: PocketIconCache.typeIcon(for: item.url, isDirectory: item.identity.isDirectory)).resizable()
                }
            }
            .scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(owner.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? item.label ?? item.name)
                        .lineLimit(1).truncationMode(.middle)
                    if item.safety == .review {
                        Image(systemName: "eye").font(.caption2).foregroundStyle(PocketTone.warning.color).help("İncele")
                    }
                    if let warning = item.warning {
                        Image(systemName: PocketTone.warning.symbol).font(.caption2).foregroundStyle(PocketTone.warning.color)
                            .help(warning)
                    }
                }
                (owner != nil ? Text(item.name) : Text("Son kullanım \(item.lastUsed.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: PocketSpacing.s)
            if let warning = item.warning {
                Text(warning).font(.caption2).foregroundStyle(PocketTone.warning.color).lineLimit(1).frame(maxWidth: 220, alignment: .trailing)
            }
            Text(pocketBytes(item.bytes)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
            if selectable {
                Button(action: toggleProtection) { Image(systemName: isProtected ? "lock.fill" : "lock.open") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isProtected ? PocketTone.success.color : .secondary)
                    .disabled(disabled)
                    .help(isProtected ? Text("Korumayı kaldır") : Text("Koru: bu öğe temizlenmesin"))
                    .accessibilityLabel(isProtected ? Text("\(item.name) korumasını kaldır") : Text("\(item.name) öğesini koru"))
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Finder’da göster")
                .accessibilityLabel("\(item.name) Finder’da göster")
        }
        .padding(.horizontal, PocketSpacing.m).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.06) : .clear)
        .help(item.url.path)
    }
}

// MARK: - Empty Trash confirmation

/// Emptying the Trash is permanent, so it needs an explicit acknowledgement, not just a button.
private struct EmptyTrashConfirmation: View {
    let itemCount: Int
    let bytes: Int64
    let confirm: () -> Void
    let cancel: () -> Void
    @State private var understood = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: "trash.fill", tint: .red, size: 44)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Çöp kalıcı olarak boşaltılsın mı?").font(.title3.weight(.semibold))
                    Text("\(itemCount) öğe · \(pocketBytes(bytes))").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Text("Bu işlem geri alınamaz. Yalnız listede gördüğün, ev klasöründeki Çöp öğeleri silinir; her öğe silinmeden hemen önce yeniden doğrulanır. Diğer disklerin Çöp’ü etkilenmez.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Toggle("Silinen öğelerin geri getirilemeyeceğini anlıyorum", isOn: $understood)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Kalıcı Olarak Sil", role: .destructive, action: confirm)
                    .buttonStyle(.pocketPrimary)
                    .tint(.red)
                    .disabled(!understood)
            }
        }
        .padding(PocketSpacing.xl)
        .frame(width: 440)
    }
}
