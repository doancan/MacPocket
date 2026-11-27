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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Görsel Klasörünü Seç")
        panel.message = String(localized: "Yalnız seçilen klasördeki desteklenen resimler yerel olarak incelenir.")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.root = url
            self.report = nil
        }
    }
    func scan() {
        guard !busy, let root else { return }
        busy = true
        report = nil
        failure = nil
        var options = SimilarImagesOptions()
        options.distanceThreshold = Float(threshold)
        options.maximumImages = maximumImages
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                report = try await service.scan(root, options: options) { [weak self] value in
                    await MainActor.run { self?.progress = value.message }
                }
            } catch is CancellationError { failure = String(localized: "İnceleme iptal edildi.") }
            catch { failure = error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel() }
}

struct SimilarImagesView: View {
    @StateObject private var model = SimilarImagesModel()
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Benzer Görseller",
                              subtitle: "Apple Vision ile görsel benzerliği adaylarını yerel olarak karşılaştır.",
                              icon: "photo.on.rectangle.angled") {
                headingActions
            }
            optionsBar
            if model.busy { PocketProgressRow(message: model.progress.isEmpty ? String(localized: "Görseller hazırlanıyor…") : model.progress) }
            if let failure = model.failure { PocketMessage(failure, tone: .warning) }
            if let report = model.report {
                results(report)
            } else if !model.busy {
                ContentUnavailableView {
                    Label("Görsellerini karşılaştır", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("JPEG, PNG, HEIC, TIFF, WebP, BMP ve GIF desteklenir; çok kareli dosyalarda yalnız ilk kare incelenir. Bu araç dosya silmez veya yüklemez.")
                } actions: {
                    if model.root == nil {
                        Button("Klasör Seç…") { model.chooseFolder() }
                    } else {
                        Button("Karşılaştır") { model.scan() }.buttonStyle(.pocketPrimary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .pocketPage()
        .onChange(of: model.threshold) { _, _ in model.report = nil }
        .onChange(of: model.maximumImages) { _, _ in model.report = nil }
        .onDisappear { model.cancel() }
    }

    private var headingActions: some View {
        HStack(spacing: PocketSpacing.s) {
            Button("Klasör Seç…") { model.chooseFolder() }
                .disabled(model.busy)
                .help("Karşılaştırılacak görsel klasörünü seç")
            if model.busy {
                Button("İptal Et", role: .cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .help("Karşılaştırmayı durdur")
            } else {
                Button("Karşılaştır") { model.scan() }
                    .buttonStyle(.pocketPrimary)
                    .disabled(model.root == nil)
                    .help("Seçili klasördeki görselleri karşılaştır")
            }
        }
    }

    private var optionsBar: some View {
        HStack(spacing: PocketSpacing.l) {
            Label {
                (model.root.map { Text(verbatim: $0.path) } ?? Text("Henüz klasör seçilmedi")).lineLimit(1).truncationMode(.middle)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .help(model.root?.path ?? "")
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Benzerlik", selection: $model.threshold) {
                Text("Yakın · 0,3").tag(0.3)
                Text("Orta · 0,6").tag(0.6)
                Text("Geniş · 0,9").tag(0.9)
            }
            .fixedSize()
            .help("Mesafe eşiği: küçük değer daha sıkı eşleşme demektir; değer bir yüzde değildir.")
                .pocketMenuPicker()
            Picker("En çok", selection: $model.maximumImages) {
                Text("100 görsel").tag(100)
                Text("250 görsel").tag(250)
                Text("500 görsel").tag(500)
            }
            .fixedSize()
            .help("İncelenecek en büyük görsel sayısı")
                .pocketMenuPicker()
            Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Benzerlik hakkında")
                .help("Benzerlik ve sınırlar hakkında")
                .popover(isPresented: $showInfo, arrowEdge: .bottom) { infoPopover }
        }
        .controlSize(.small)
        .disabled(model.busy)
        .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text("Benzerlik hakkında").font(.headline)
            Label("Benzerlik eşit içerik demek değildir. Mesafe küçüldükçe benzerlik artar; eşik deneyseldir. Fotoğrafları incelemeden silme.", systemImage: "eye")
            Label("Gruplar yalnız referansla doğrudan eşleşen adayları içerir; adaylar birbirine benzemeyebilir.", systemImage: "square.stack.3d.up")
            Label("Bağlantılar izlenmez, hard link tek sayılır. Görsel başına en çok 64 MiB / 100 megapiksel; analiz kopyası 1.536 piksele küçültülür.", systemImage: "ruler")
            Label("Bu araç dosya silmez veya yüklemez; tüm analiz bu Mac’te yapılır.", systemImage: "lock.shield")
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 340)
        .padding(PocketSpacing.l)
    }

    private func results(_ report: SimilarImagesReport) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.xl) {
                Label("\(report.discoveredImages) desteklenen", systemImage: "photo.stack")
                Label("\(report.analyzedImages) analiz", systemImage: "eye")
                if report.skippedImages > 0 {
                    Label("\(report.skippedImages) atlanan", systemImage: "forward")
                }
                Label("\(report.groups.count) grup", systemImage: "square.stack.3d.up")
                Spacer(minLength: PocketSpacing.s)
                Text(report.scannedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }
            .font(.callout)
            .monospacedDigit()
            if report.partial || report.inaccessibleCount > 0 {
                PocketMessage(String(localized: "Sonuç kısmi: en büyük \(model.maximumImages) görsel, 100.000 klasör girdisi, 60 saniye ve 1.000 eşleşme sınırı uygulanır.")
                              + (report.inaccessibleCount > 0 ? " " + String(localized: "\(report.inaccessibleCount) öğeye erişilemedi.") : ""),
                              tone: .warning)
            }
            if !report.issues.isEmpty {
                DisclosureGroup("Atlanan veya okunamayan görseller (\(report.issues.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                                Text(issue).font(.subheadline).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }
                .font(.callout)
            }
            if report.groups.isEmpty {
                ContentUnavailableView("Bu kapsamda benzerlik adayı bulunamadı", systemImage: "photo.on.rectangle",
                                       description: Text("Daha geniş bir eşik veya başka bir klasör deneyebilirsin. Kısmi sonuç uyarısı varsa kapsam tamamlanmamıştır."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PocketSpacing.m) {
                        ForEach(report.groups) { group in
                            SimilarImageGroupView(group: group)
                        }
                    }
                }
            }
        }
    }
}

private struct SimilarImageGroupView: View {
    let group: SimilarImageGroup
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                Label(group.reference.url.lastPathComponent, systemImage: "photo")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                    .help(group.reference.url.path)
                PocketStatusBadge(text: "\(group.matches.count) aday", tone: .accent)
                Spacer(minLength: PocketSpacing.s)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([group.reference.url] + group.matches.map(\.file.url))
                } label: {
                    Label("Tümünü Finder’da Göster", systemImage: "folder")
                }
                .controlSize(.small)
                .help("Referansı ve adayları Finder’da seç")
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: PocketSpacing.m) {
                    SimilarImageTile(file: group.reference, caption: "Referans", isReference: true)
                    ForEach(group.matches) { match in
                        SimilarImageTile(file: match.file, caption: "Mesafe \(match.distance.formatted(.number.precision(.fractionLength(3))))")
                    }
                }
                .padding(.bottom, PocketSpacing.xs)
            }
        }
        .pocketCard()
    }
}

private struct SimilarImageTile: View {
    let file: ScannedFile
    let caption: LocalizedStringKey
    var isReference = false
    @State private var preview: NSImage?
    @State private var changed = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous).fill(PocketTheme.background)
                if let preview {
                    Image(nsImage: preview).resizable().scaledToFit()
                } else if changed {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(PocketTone.warning.color)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 160, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous)
                    .strokeBorder(isReference ? PocketTheme.accent : PocketTheme.line.opacity(0.6), lineWidth: isReference ? 2 : 0.5)
            }
            Text(file.url.lastPathComponent).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
            (changed ? Text("Dosya değişmiş veya okunamıyor") : Text(caption))
                .font(.subheadline).foregroundStyle(changed ? PocketTone.warning.color : .secondary)
                .monospacedDigit()
        }
        .frame(width: 160)
        .contentShape(Rectangle())
        .help(file.url.path)
        .contextMenu {
            Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Button("Aç") { NSWorkspace.shared.open(file.url) }
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Finder’da Göster")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
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
