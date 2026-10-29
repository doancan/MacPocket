import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class ApplicationLeftoversModel: ObservableObject {
    @Published var rows: [ApplicationLeftover] = []
    @Published var selection = Set<String>()
    @Published var busy = false
    @Published var message: String?
    @Published var search = ""
    private var operation: Task<Void, Never>?
    var filtered: [ApplicationLeftover] { rows.filter { search.isEmpty || $0.bundleID.localizedCaseInsensitiveContains(search) } }
    func scan() {
        guard !busy else { return }
        busy = true; selection = []; message = nil
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                let installed = try await ApplicationInventory().scan()
                let candidates = try await ApplicationLeftoverScanner().scan(installedIDs: Set(installed.map(\.bundleID)))
                rows = candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) == nil }
                message = "\(rows.count) aday bulundu. Başka diskte veya taşınmış uygulamalara ait olabilir."
            } catch is CancellationError { message = "Tarama iptal edildi." }
            catch { message = error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel() }
    func trash() {
        guard !busy else { return }
        let selected = filtered.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return }
        busy = true
        operation = Task {
            defer { busy = false; operation = nil }
            let installedIDs: Set<String>
            do {
                let inventory = try await ApplicationInventory().scan()
                try Task.checkCancellation()
                installedIDs = Set(inventory.map(\.bundleID))
            } catch {
                message = error is CancellationError ? "İşlem iptal edildi." : error.localizedDescription
                return
            }
            let stillUnregistered = selected.filter { candidate in
                !installedIDs.contains(where: { candidate.bundleID == $0 || candidate.bundleID.hasPrefix($0 + ".") })
                    && NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) == nil
            }
            let results = await FileTrashService().trash(stillUnregistered.map(\.request))
            let moved = Set(results.filter { $0.trashURL != nil }.map(\.id))
            rows.removeAll { moved.contains($0.id) }; selection = []
            message = "\(moved.count) öğe Çöp’e taşındı. \(selected.count - stillUnregistered.count) öğe artık kurulu bir uygulamayla eşleştiği için atlandı. " + results.compactMap(\.error).prefix(3).joined(separator: "\n")
        }
    }
}

struct ApplicationLeftoversView: View {
    @StateObject private var model = ApplicationLeftoversModel()
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PocketPageHeading(title: "Uygulama Kalıntıları", subtitle: "Kurulu veya kayıtlı bir uygulamayla eşleşmeyen bundle kimliği adayları.", icon: "square.dashed")
            Text("Aday olması gereksiz olduğu anlamına gelmez. Taşınmış uygulamalar da burada görünebilir. Kullanıcı verilerini inceleyerek seç; paylaşılan üretici klasörleri bu taramaya dahil edilmez.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Tarama kullanıcı Library içindeki yedi konumun her birinde en fazla 10.000 doğrudan öğeyi inceler. Erişilemeyen klasörler atlanır; sonuç tüm diski kapsamaz.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Bundle kimliği ara…", text: $model.search).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button("İptal Et") { model.cancel() } }
                else { Button("Tara") { model.scan() } }
            }
            if let message = model.message { Text(message).font(.callout).textSelection(.enabled) }
            Table(model.filtered, selection: $model.selection) {
                TableColumn("Bundle kimliği") { Text($0.bundleID) }.width(min: 220, ideal: 320)
                TableColumn("Tür") { Text($0.category) }.width(140)
                TableColumn("Konum") { Text($0.request.url.path).lineLimit(1).truncationMode(.middle) }
            }.disabled(model.busy)
            HStack {
                Text("\(model.selection.count) seçili").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting(model.rows.filter { model.selection.contains($0.id) }.map { $0.request.url }) }.disabled(model.selection.isEmpty)
                Button("Seçilenleri Çöp’e Taşı…", role: .destructive) { confirm = true }.disabled(model.selection.isEmpty || model.busy)
            }
        }.padding(24)
        .onChange(of: model.search) { _, _ in model.selection = [] }
        .onDisappear { model.cancel() }
        .alert("Seçili adaylar Çöp’e taşınsın mı?", isPresented: $confirm) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp’e Taşı", role: .destructive) { model.trash() }
        } message: { Text("Seçilen \(model.selection.count) öğe tercih veya kullanıcı verisi içerebilir. Uygulaması başka yerdeyse bu verilere ihtiyaç duyabilir. Gerekirse Finder’daki Çöp’ten geri alabilirsin.") }
    }
}
