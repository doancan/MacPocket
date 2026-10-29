import AppKit
import MacPocketCore
import SwiftUI

struct FileWorkspaceView: View {
    @ObservedObject var model: FileWorkspaceModel
    var cleanup = false
    @State private var confirmTrash = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PocketPageHeading(title: cleanup ? "Temizlik" : "Disk Analizi",
                              subtitle: cleanup ? "Alan kaplayan öğeleri incele, seçtiklerini Çöp’e taşı." : "Bir klasörün alan kullanımını, büyük dosyalarını ve kopyalarını incele.",
                              icon: cleanup ? "sparkles" : "internaldrive")
            HStack(spacing: 10) {
                if cleanup {
                    Menu("Kaynaklar") {
                        Button("Önbellek") { useCleanupSource("Library/Caches", folders: true) }
                        Button("Günlükler") { useCleanupSource("Library/Logs", folders: true) }
                        Button("İndirilenler") { useCleanupSource("Downloads", folders: false) }
                    }
                }
                Label(model.root?.path ?? "Önce bir klasör seç", systemImage: "folder")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Klasör Seç…") { model.chooseFolder() }.disabled(model.busy)
                if model.busy {
                    Button("İptal Et") { model.cancel() }
                } else {
                    Button("Tara") { model.scan() }.buttonStyle(.borderedProminent).disabled(model.root == nil)
                }
            }
            if model.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.progress).font(.callout).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            }
            if let failure = model.failure { PocketMessage(failure, error: true) }
            if let result = model.resultMessage { PocketMessage(result) }
            if let report = model.report { results(report) }
            else if !model.busy {
                ContentUnavailableView(cleanup ? "Önce taramayı çalıştır" : "Diskini keşfet",
                                       systemImage: cleanup ? "sparkles" : "internaldrive",
                                       description: Text("Tarama dosyaları değiştirmez. Taşınacak öğeleri sonuçlardan sen seçersin."))
            } else { Spacer(minLength: 0) }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .onChange(of: model.scope) { _, _ in model.selection = [] }
        .onChange(of: model.search) { _, _ in model.selection = [] }
        .alert("Seçilen öğeler Çöp’e taşınsın mı?", isPresented: $confirmTrash) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp’e Taşı", role: .destructive) { model.trashSelection() }
        } message: {
            Text("\(model.selectedRows.count) öğe · \(pocketBytes(UInt64(max(0, model.selectedBytes)))) mantıksal boyut. Gerekirse Finder’daki Çöp’ten geri alabilirsin.")
        }
    }

    private func useCleanupSource(_ path: String, folders: Bool) {
        model.useRoot(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path), scope: folders ? .folders : .large)
    }

    private func results(_ report: FileScanReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                Label("\(report.fileCount.formatted()) tekil dosya", systemImage: "doc.on.doc")
                Text(pocketBytes(UInt64(max(0, report.bytes)))).monospacedDigit()
                Spacer()
                Text(report.scannedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }.font(.callout)
            if report.limitReached || !report.retainedAllFiles || report.inaccessibleCount > 0 {
                Text("\(report.limitReached ? "Tarama sınırına ulaşıldı. " : "")\(!report.retainedAllFiles ? "En büyük \(report.files.count.formatted()) dosya listeleniyor. " : "")\(report.inaccessibleCount) erişilemeyen öğe. Sonuç kapsamı kısmi olabilir.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Picker("Görünüm", selection: $model.scope) {
                    ForEach(FileWorkspaceScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 480).disabled(model.busy)
                Spacer()
                TextField("Sonuçlarda ara…", text: $model.search).textFieldStyle(.roundedBorder)
                    .focused($searchFocused).frame(width: 210)
            }
            HStack(spacing: 14) {
                Picker("En az", selection: $model.minimumMB) {
                    Text("Tüm boyutlar").tag(0.0)
                    Text("10 MB+").tag(10.0)
                    Text("100 MB+").tag(100.0)
                    Text("1 GB+").tag(1024.0)
                }.frame(width: 175)
                if model.scope == .old {
                    Picker("Değiştirilme", selection: $model.olderDays) {
                        Text("30 günden eski").tag(30.0)
                        Text("90 günden eski").tag(90.0)
                        Text("1 yıldan eski").tag(365.0)
                    }.frame(width: 190)
                }
                if model.scope == .duplicates {
                    Button("İçerikleri Karşılaştır") { model.findDuplicates() }.disabled(model.busy)
                    Button("Fazla Kopyaları Seç") { model.selectExtraCopies() }.disabled(model.duplicates.isEmpty || model.busy)
                }
                Spacer()
            }.controlSize(.small)
            FileResultsTable(rows: model.rows, selection: $model.selection)
                .disabled(model.busy)
            HStack {
                Text("\(model.rows.count.formatted()) listelenen · \(model.selectedRows.count) seçili")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Finder’da Göster") {
                    NSWorkspace.shared.activateFileViewerSelecting(model.selectedRows.map(\.url))
                }.disabled(model.selection.isEmpty)
                Button("Seçilenleri Çöp’e Taşı", role: .destructive) { confirmTrash = true }
                    .disabled(model.selectedRows.isEmpty || model.busy || !model.preservesDuplicateOriginals)
            }
            if !model.preservesDuplicateOriginals {
                Text("Her yinelenen grupta en az bir dosyayı korumalısın.").font(.caption).foregroundStyle(.orange)
            }
            Text("Boyutlar mantıksal dosya boyutudur; APFS paylaşımlı alanı ve dosyaların yeniden oluşturulması nedeniyle kazanılan alan farklı olabilir. Bağlantılar takip edilmez.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FileResultsTable: View {
    let rows: [FileResultRow]
    @Binding var selection: Set<String>
    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Ad") { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).lineLimit(1)
                    Text(row.parent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 3)
            }.width(min: 260, ideal: 480)
            TableColumn("Boyut") { row in
                Text(pocketBytes(UInt64(max(0, row.bytes)))).monospacedDigit()
            }.width(110)
            TableColumn("Değiştirilme") { row in
                Text(row.modified.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
            }.width(140)
        }.tableStyle(.inset)
    }
}

struct PocketPageHeading: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.system(size: 25, weight: .medium)).foregroundStyle(PocketTheme.accent)
                .frame(width: 48, height: 48).background(PocketTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 25, weight: .semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PocketMessage: View {
    let message: String
    var error = false
    init(_ message: String, error: Bool = false) { self.message = message; self.error = error }
    var body: some View {
        Label(message, systemImage: error ? "exclamationmark.triangle" : "checkmark.circle")
            .font(.callout).foregroundStyle(error ? Color.orange : Color.secondary)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}
