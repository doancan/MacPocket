import AppKit
import MacPocketCore
import SwiftUI

/// Large files, folders, old files and duplicates of a chosen folder. Embedded in Disk Analizi.
struct FileWorkspaceView: View {
    @ObservedObject var model: FileWorkspaceModel
    @State private var confirmTrash = false
    @State private var showInfo = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            toolbar
            if model.busy { PocketProgressRow(message: model.progress.isEmpty ? String(localized: "Çalışıyor…") : model.progress) }
            if let failure = model.failure {
                PocketMessage(failure, tone: model.report == nil ? .critical : .warning)
            }
            if let result = model.resultMessage { PocketMessage(result, tone: .success) }
            if let report = model.report {
                results(report)
            } else if !model.busy {
                ContentUnavailableView {
                    Label("Büyük, eski ve yinelenen dosyaları bul", systemImage: "doc.text.magnifyingglass")
                } description: {
                    if let root = model.root {
                        Text("\(root.lastPathComponent) klasörünü tara. Taşınacak öğeleri sonuçlardan sen seçersin.")
                    } else {
                        Text("Taramak için bir klasör seç. Tarama dosyaları değiştirmez.")
                    }
                } actions: {
                    HStack {
                        Button("Klasör Seç…") { model.chooseFolder() }
                        if model.root != nil { Button("Tara") { model.scan() }.buttonStyle(.pocketPrimary) }
                    }
                    quickRoots
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .alert("Seçilen öğeler Çöp’e taşınsın mı?", isPresented: $confirmTrash) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp’e Taşı", role: .destructive) { model.trashSelection() }
        } message: {
            Text("\(model.selectedRows.count) öğe · \(pocketBytes(model.selectedBytes)) mantıksal boyut. Gerekirse Finder’daki Çöp’ten geri alabilirsin.")
        }
    }

    // MARK: Header

    private var quickRoots: some View {
        HStack(spacing: PocketSpacing.s) {
            ForEach([(String(localized: "İndirilenler"), "Downloads"), (String(localized: "Belgeler"), "Documents"), (String(localized: "Masaüstü"), "Desktop"), (String(localized: "Ev Klasörü"), "")], id: \.1) { title, path in
                Button(title) {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    model.useRoot(path.isEmpty ? home : home.appendingPathComponent(path), scope: model.scope)
                    model.scan()
                }
                .buttonStyle(.link)
            }
        }
        .font(.callout)
    }

    private var toolbar: some View {
        HStack(spacing: PocketSpacing.s) {
            Label {
                (model.root.map { Text(verbatim: $0.path) } ?? Text("Henüz klasör seçilmedi"))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .help(model.root?.path ?? "")
            Button { showInfo.toggle() } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Tarama hakkında")
            .help("Boyutlar ve güvenlik hakkında")
            .popover(isPresented: $showInfo, arrowEdge: .bottom) { infoPopover }
            Spacer(minLength: PocketSpacing.s)
            Button("Klasör Seç…") { model.chooseFolder() }
                .disabled(model.busy)
                .help("Taranacak klasörü seç")
            if model.busy {
                Button("İptal Et", role: .cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .help("Süren işlemi durdur")
            } else {
                Button(model.report == nil ? ("Tara" as LocalizedStringKey) : "Yeniden Tara") { model.scan() }
                    .buttonStyle(.pocketPrimary)
                    .disabled(model.root == nil)
                    .help(model.report == nil ? Text("Seçili klasörü tara") : Text("Klasörü yeniden tara"))
            }
        }
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text("Tarama hakkında").font(.headline)
            Label("Tarama dosyaları değiştirmez; yalnız seçtiğin öğeler Çöp’e taşınır ve Finder’dan geri alınabilir.", systemImage: "trash")
            Label("Bu görünümdeki boyutlar mantıksal dosya boyutudur; APFS paylaşımlı alanı nedeniyle kazanılan alan farklı olabilir.", systemImage: "internaldrive")
            Label("Sembolik bağlantılar takip edilmez, hard link’ler bir kez sayılır, paket içleri tek tek sunulmaz.", systemImage: "link")
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 320)
        .padding(PocketSpacing.l)
    }

    // MARK: Results

    private func results(_ report: FileScanReport) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            summary(report)
            controls
            resultsTable
            footer
        }
    }

    private func summary(_ report: FileScanReport) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.xl) {
                Label("\(report.fileCount) tekil dosya", systemImage: "doc.on.doc")
                Label(pocketBytes(report.bytes), systemImage: "externaldrive").monospacedDigit()
                if model.hasTrashedItems {
                    PocketStatusBadge(text: "Çöp’e taşınanlar gizlendi", systemImage: "trash", tone: .neutral)
                        .help("Toplamlar bir sonraki taramada güncellenir.")
                }
                Spacer(minLength: PocketSpacing.s)
                Text(report.scannedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
                    .help("Tarama zamanı")
            }
            .font(.callout)
            if report.limitReached || !report.retainedAllFiles || report.inaccessibleCount > 0 {
                Label(partialText(report), systemImage: PocketTone.warning.symbol)
                    .font(.subheadline)
                    .foregroundStyle(PocketTone.warning.color)
                    .help(report.issues.prefix(5).joined(separator: "\n"))
            }
            if report.packagedFileCount > 0 {
                Label("\(report.packagedFileCount) dosya .app veya .photoslibrary gibi paketlerin içinde; toplamlara dahil ama tek tek listelenmez. Paketleri “Klasörler” görünümünde tek öğe olarak bulabilirsin.",
                      systemImage: "shippingbox")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
    }

    private func partialText(_ report: FileScanReport) -> String {
        var parts: [String] = []
        if report.limitReached { parts.append(String(localized: "Tarama sınırına ulaşıldı.")) }
        if !report.retainedAllFiles { parts.append(String(localized: "En büyük \(report.files.count) dosya listeleniyor.")) }
        if report.inaccessibleCount > 0 { parts.append(String(localized: "\(report.inaccessibleCount) öğeye erişilemedi.")) }
        parts.append(String(localized: "Sonuç kısmi olabilir."))
        return parts.joined(separator: " ")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                GlassTabBar(tabs: FileWorkspaceScope.allCases.map { GlassTab(id: $0, title: $0.localizedTitle) },
                            selection: $model.scope)
                .accessibilityLabel("Görünüm")
                .frame(maxWidth: 480)
                .disabled(model.busy)
                Spacer(minLength: PocketSpacing.s)
                PocketSearchField("Sonuçlarda ara…", text: $model.search, focus: $searchFocused)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Sonuçlarda ara")
            }
            HStack(spacing: PocketSpacing.m) {
                Picker("En az", selection: $model.minimumMB) {
                    Text("Tüm boyutlar").tag(0.0)
                    Text("10 MB+").tag(10.0)
                    Text("100 MB+").tag(100.0)
                    Text("1 GB+").tag(1024.0)
                }
                .fixedSize()
                if model.scope == .old {
                    Picker("Değiştirilme", selection: $model.olderDays) {
                        Text("30 günden eski").tag(30.0)
                        Text("90 günden eski").tag(90.0)
                        Text("1 yıldan eski").tag(365.0)
                    }
                    .fixedSize()
                }
                if model.scope == .duplicates {
                    Button("İçerikleri Karşılaştır") { model.findDuplicates() }
                        .disabled(model.busy)
                        .help("Aynı boyuttaki dosyaları içerikleriyle karşılaştır")
                    Button("Fazla Kopyaları Seç") { model.selectExtraCopies() }
                        .disabled(model.duplicates.isEmpty || model.busy)
                        .help("Her grupta ilk dosyayı koru, diğerlerini seç")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }

    private var resultsTable: some View {
        FileResultsTable(rows: model.rows, selection: $model.selection)
            .disabled(model.busy)
            .overlay {
                if model.rows.isEmpty && !model.busy { emptyResults }
            }
    }

    @ViewBuilder
    private var emptyResults: some View {
        if !model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: model.search)
        } else if model.scope == .duplicates && model.duplicates.isEmpty {
            ContentUnavailableView {
                Label("Yinelenen grup yok", systemImage: "doc.on.doc")
            } description: {
                Text("Aynı içerikli dosyaları bulmak için içerikleri karşılaştır.")
            } actions: {
                Button("İçerikleri Karşılaştır") { model.findDuplicates() }
            }
        } else {
            ContentUnavailableView("Bu görünümde öğe yok", systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("Boyut veya tarih filtresini değiştirmeyi dene."))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            HStack(spacing: PocketSpacing.s) {
                Text(selectionSummary)
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: PocketSpacing.s)
                Button("Finder’da Göster") {
                    NSWorkspace.shared.activateFileViewerSelecting(model.selectedRows.map(\.url))
                }
                .disabled(model.selectedRows.isEmpty)
                .help("Seçili öğeleri Finder’da göster")
                Button("Çöp’e Taşı…", role: .destructive) { confirmTrash = true }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selectedRows.isEmpty || model.busy || !model.preservesDuplicateOriginals)
                    .help("Seçili öğeleri Çöp’e taşı (⌘⌫)")
            }
            if !model.preservesDuplicateOriginals {
                Label("Her yinelenen grupta en az bir dosyayı korumalısın.", systemImage: PocketTone.warning.symbol)
                    .font(.subheadline).foregroundStyle(PocketTone.warning.color)
            }
        }
    }

    private var selectionSummary: String {
        let listed = String(localized: "\(model.rows.count) listelenen")
        guard !model.selectedRows.isEmpty else { return listed }
        return String(localized: "\(listed) · \(model.selectedRows.count) seçili (\(pocketBytes(model.selectedBytes)))")
    }
}

private struct FileResultsTable: View {
    let rows: [FileResultRow]
    @Binding var selection: Set<String>

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Ad") { row in
                HStack(spacing: PocketSpacing.s) {
                    Image(nsImage: PocketIconCache.typeIcon(for: row.url, isDirectory: row.identity.isDirectory))
                        .resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                        Text(row.name).lineLimit(1)
                        Text(row.parent).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.vertical, PocketSpacing.xxs)
                .help(row.url.path)
            }
            .width(min: 260, ideal: 480)
            TableColumn("Boyut") { row in
                Text(pocketBytes(row.bytes)).monospacedDigit()
            }
            .width(min: 80, ideal: 110)
            TableColumn("Değiştirilme") { row in
                Text(row.modified.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button("Finder’da Göster") {
                    NSWorkspace.shared.activateFileViewerSelecting(rows.filter { ids.contains($0.id) }.map(\.url))
                }
            }
        } primaryAction: { ids in
            NSWorkspace.shared.activateFileViewerSelecting(rows.filter { ids.contains($0.id) }.map(\.url))
        }
    }
}
