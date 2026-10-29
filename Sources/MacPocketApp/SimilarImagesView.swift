import AppKit
import ImageIO
import MacPocketCore
import SwiftUI

@MainActor
final class SimilarImagesModel: ObservableObject {
    @Published var root: URL?
    @Published var threshold = 0.6
    @Published var maximumImages = 250
    @Published var report: SimilarImagesReport?
    @Published var busy = false
    @Published var progress = ""
    @Published var failure: String?
    private let service = SimilarImagesService()
    private var operation: Task<Void, Never>?
    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Görsel Klasörünü Seç"; panel.message = "Yalnız seçilen klasördeki desteklenen resimler yerel olarak incelenir."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }; self.root = url; self.report = nil
        }
    }
    func scan() {
        guard !busy, let root else { return }
        busy = true; report = nil; failure = nil
        var options = SimilarImagesOptions(); options.distanceThreshold = Float(threshold); options.maximumImages = maximumImages
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                report = try await service.scan(root, options: options) { [weak self] value in
                    await MainActor.run { self?.progress = value.message }
                }
            } catch is CancellationError { failure = "İnceleme iptal edildi." }
            catch { failure = error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel() }
}

struct SimilarImagesView: View {
    @StateObject private var model = SimilarImagesModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PocketPageHeading(title: "Benzer Görseller", subtitle: "Apple Vision ile görsel benzerliği adaylarını yerel olarak karşılaştır.", icon: "photo.on.rectangle.angled")
            HStack {
                Label(model.root?.path ?? "Önce bir görsel klasörü seç", systemImage: "folder").font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Klasör Seç…") { model.chooseFolder() }.disabled(model.busy)
                if model.busy { Button("İptal Et") { model.cancel() } }
                else { Button("Karşılaştır") { model.scan() }.buttonStyle(.borderedProminent).disabled(model.root == nil) }
            }
            HStack(spacing: 20) {
                Picker("Benzerlik kapsamı", selection: $model.threshold) {
                    Text("Yakın · 0,3").tag(0.3); Text("Orta · 0,6").tag(0.6); Text("Geniş · 0,9").tag(0.9)
                }.frame(width: 240)
                Picker("En çok", selection: $model.maximumImages) {
                    Text("100 görsel").tag(100); Text("250 görsel").tag(250); Text("500 görsel").tag(500)
                }.frame(width: 180)
                Spacer()
            }.disabled(model.busy)
            Text("Benzerlik eşit içerik demek değildir. Mesafe küçüldükçe benzerlik artar; değer bir yüzde değildir. Eşik deneyseldir: fotoğrafları incelemeden silme. Bu araç dosya silmez veya yüklemez.")
                .font(.callout).foregroundStyle(.secondary)
            if model.busy { HStack { ProgressView().controlSize(.small); Text(model.progress).font(.callout) } }
            if let failure = model.failure { PocketMessage(failure, error: true) }
            if let report = model.report {
                HStack {
                    Text("\(report.discoveredImages) desteklenen dosya · \(report.analyzedImages) analiz · \(report.skippedImages) atlanan")
                    Spacer()
                    Text(report.scannedAt.formatted(date: .abbreviated, time: .shortened))
                }.font(.caption).foregroundStyle(.secondary)
                if report.partial || report.inaccessibleCount > 0 {
                    PocketMessage("Sonuç kısmi. En büyük \(model.maximumImages) görsel, 100.000 klasör girdisi, 60 saniye ve 1.000 eşleşme sınırı uygulanır. \(report.inaccessibleCount) öğeye erişilemedi.", error: true)
                }
                if !report.issues.isEmpty {
                    DisclosureGroup("Atlanan veya okunamayan görseller") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).textSelection(.enabled) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }
                }
                if report.groups.isEmpty {
                    ContentUnavailableView("Bu kapsamda benzerlik adayı bulunamadı", systemImage: "photo.on.rectangle",
                                           description: Text("Farklı eşik veya başka klasör seçebilirsin. Kısmi sonuç uyarısı varsa kapsam tamamlanmamıştır."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(report.groups) { group in
                                SimilarImageGroupView(group: group)
                            }
                        }
                    }
                }
            } else if !model.busy {
                ContentUnavailableView("Görsellerini karşılaştır", systemImage: "photo.on.rectangle.angled",
                                       description: Text("JPEG, PNG, HEIC, TIFF, WebP, BMP ve GIF; çok kareli dosyalarda yalnız ilk kare incelenir."))
            } else { Spacer(minLength: 0) }
            Text("Bağlantılar izlenmez, hard link tek sayılır. Her görsel en çok 64 MiB / 100 megapiksel olabilir; analiz kopyası 1.536 piksele küçültülür. İptal ve süre sınırı işlem adımları arasında denetlenir. Gruplar yalnız referansla doğrudan eşleşen adayları içerir; adaylar birbirine benzemeyebilir.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.threshold) { _, _ in model.report = nil }
        .onChange(of: model.maximumImages) { _, _ in model.report = nil }
        .onDisappear { model.cancel() }
    }
}

private struct SimilarImageGroupView: View {
    let group: SimilarImageGroup
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(group.reference.url.lastPathComponent, systemImage: "photo").font(.headline).lineLimit(1)
                Spacer()
                Text("\(group.matches.count) aday").font(.caption).foregroundStyle(.secondary)
                Button("Referansı Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([group.reference.url]) }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    SimilarImageTile(file: group.reference, caption: "Referans")
                    ForEach(group.matches) { match in
                        SimilarImageTile(file: match.file, caption: String(format: "Mesafe %.3f", match.distance))
                    }
                }
            }
        }.padding(16).background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SimilarImageTile: View {
    let file: ScannedFile
    let caption: String
    @State private var preview: NSImage?
    @State private var changed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(PocketTheme.background)
                if let preview { Image(nsImage: preview).resizable().scaledToFit() }
                else { Image(systemName: changed ? "exclamationmark.triangle" : "photo").foregroundStyle(.secondary) }
            }.frame(width: 155, height: 115)
            Text(file.url.lastPathComponent).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
            Text(changed ? "Dosya değişmiş veya okunamıyor" : caption).font(.caption).foregroundStyle(.secondary)
            Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.controlSize(.small)
        }.frame(width: 155)
        .task(id: file.id) {
            let image = await SimilarThumbnailLoader.shared.load(file)
            guard !Task.isCancelled else { return }
            if let image { preview = NSImage(cgImage: image, size: .zero) } else { changed = true }
        }
    }
}

// Serialize thumbnail decoding so a gallery cannot launch hundreds of image decoders.
private actor SimilarThumbnailLoader {
    static let shared = SimilarThumbnailLoader()
    func load(_ file: ScannedFile) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return try? SimilarImagesService.thumbnail(for: file)
    }
}
