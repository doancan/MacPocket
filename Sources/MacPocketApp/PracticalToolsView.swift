import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

struct PracticalDraft: Sendable {
    var input = ""
    var second = ""
    var reverse = false
    var compact = false
    var urlSafe = false
    var hash = PracticalHash.sha256
    var count = 1
    var uppercaseUUID = false
    var length = 24
    var uppercase = true
    var lowercase = true
    var digits = true
    var symbols = true
    var milliseconds = false
    var utc = false
    var wifi = false
    var ssid = ""
    var wifiPassword = ""
    var wifiHidden = false
    var wifiOpen = false
    var caseFormat = CaseFormat.camel
    var caseLive = true
    var caseOptions = CaseOptions(language: Bundle.main.preferredLocalizations.first?.hasPrefix("tr") == true ? .turkish : .english)
}

struct PracticalResult: Sendable {
    var text: String
    var notes: [String] = []
    var png: Data?
    var lines: [PracticalDiffLine] = []
    var casePreviews: [CasePreview] = []
}

/// Synchronous, bounded transforms, called on a worker task. No network or persistence.
enum PracticalExecution {
    static func run(_ tool: PracticalTool, draft: PracticalDraft) throws -> PracticalResult {
        func iso(_ date: Date, utc: Bool = true) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = utc ? TimeZone(secondsFromGMT: 0) : .current
            return formatter.string(from: date)
        }
        switch tool {
        case .caseConverter:
            let previews = try CaseConverter.previews(draft.input, options: draft.caseOptions)
            let stats = CaseConverter.statistics(draft.input)
            return .init(text: previews.first { $0.format == draft.caseFormat }?.text ?? "",
                         notes: [String(localized: "Karakter: \(stats.characters) · Sözcük: \(stats.words) · Satır: \(stats.lines)")],
                         casePreviews: previews)
        case .json: return .init(text: try PracticalTools.json(draft.input, compact: draft.compact))
        case .base64: return .init(text: try PracticalTools.base64(draft.input, decode: draft.reverse, urlSafe: draft.urlSafe))
        case .url: return .init(text: try PracticalTools.url(draft.input, decode: draft.reverse))
        case .hash: return .init(text: try PracticalTools.hash(draft.input, algorithm: draft.hash))
        case .uuid: return .init(text: try PracticalTools.uuids(count: draft.count, uppercase: draft.uppercaseUUID))
        case .password:
            return .init(text: try PracticalTools.password(length: draft.length, uppercase: draft.uppercase,
                                                           lowercase: draft.lowercase, digits: draft.digits, symbols: draft.symbols))
        case .jwt:
            let value = try PracticalTools.jwt(draft.input)
            var notes = [value.timeDescription]
            for (title, date) in [(String(localized: "Oluşturulma (iat)"), value.issuedAt),
                                  (String(localized: "Başlangıç (nbf)"), value.notBefore),
                                  (String(localized: "Sona erme (exp)"), value.expiration)] {
                if let date { notes.append(title + ": " + iso(date)) }
            }
            return .init(text: String(localized: "JWT başlığı") + "\n" + value.header + "\n\n" + String(localized: "JWT içeriği") + "\n" + value.payload, notes: notes)
        case .timestamp:
            let date = try draft.reverse ? PracticalTools.isoDate(draft.input) : PracticalTools.timestamp(draft.input, milliseconds: draft.milliseconds)
            let text = try draft.reverse ? PracticalTools.unix(date, milliseconds: draft.milliseconds) : iso(date, utc: draft.utc)
            return .init(text: text, notes: ["UTC: " + iso(date), String(localized: "Yerel saat") + ": " + iso(date, utc: false)])
        case .diff:
            let lines = try PracticalTools.diff(draft.input, draft.second)
            let added = lines.filter { $0.kind == .added }.count, removed = lines.filter { $0.kind == .removed }.count
            return .init(text: lines.map { $0.prefix + " " + $0.text }.joined(separator: "\n"),
                         notes: [added + removed == 0 ? String(localized: "Metinler aynı.") : String(localized: "Eklenen: \(added) · Silinen: \(removed)")],
                         lines: lines)
        case .qr:
            let payload = try draft.wifi ? PracticalTools.wifiPayload(ssid: draft.ssid, password: draft.wifiPassword,
                                                                      hidden: draft.wifiHidden, open: draft.wifiOpen) : draft.input
            return .init(text: payload, png: try PracticalTools.qrPNG(payload))
        }
    }

    static func example(_ tool: PracticalTool, draft: PracticalDraft) -> PracticalDraft {
        var result = draft
        switch tool {
        case .caseConverter: result.input = "HTTPServer2Response\nİzmir şehir rehberi\nuser_profile_name"
        case .json: result.input = #"{"project":"MacPocket","enabled":true,"tools":["JSON","QR"],"count":10}"#
        case .base64: result.input = draft.reverse ? "TWFjUG9ja2V0" : "MacPocket · İzmir"
        case .url: result.input = draft.reverse ? "Merhaba%20%C4%B0zmir%20%26%20MacPocket" : "Merhaba İzmir & MacPocket"
        case .hash: result.input = "MacPocket"
        case .jwt:
            let header = (try? PracticalTools.base64(#"{"alg":"none","typ":"JWT"}"#, decode: false, urlSafe: true)) ?? ""
            let payload = (try? PracticalTools.base64(#"{"sub":"demo","exp":1893456000,"name":"MacPocket"}"#, decode: false, urlSafe: true)) ?? ""
            result.input = header + "." + payload + "."
        case .timestamp:
            result.input = draft.reverse ? "2026-11-05T12:30:00+03:00" : (draft.milliseconds ? "1793871000000" : "1793871000")
        case .diff:
            result.input = "MacPocket\nJSON düzenleme\nQR okuma"
            result.second = "MacPocket\nJSON düzenleme\nQR oluşturma\nÇevrimdışı araçlar"
        case .qr:
            result.input = "https://it-tools.tech/"
            result.ssid = "MacPocket Demo"; result.wifiPassword = "example-only-123"
        case .uuid, .password: break
        }
        return result
    }
}

@MainActor
final class PracticalWorkspace: ObservableObject {
    static let shared = PracticalWorkspace()
    private let defaults: UserDefaults?
    @Published var selected: PracticalTool {
        didSet { defaults?.set(selected.rawValue, forKey: "MacPocket.practical.selected") }
    }
    @Published private(set) var favorites: Set<PracticalTool>
    @Published private(set) var drafts: [PracticalTool: PracticalDraft] = [:]
    @Published private(set) var results: [PracticalTool: PracticalResult] = [:]
    @Published private(set) var errors: [PracticalTool: String] = [:]
    @Published private(set) var running: PracticalTool?
    private var task: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var generation = UUID()

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        selected = defaults?.string(forKey: "MacPocket.practical.selected").flatMap(PracticalTool.init(rawValue:)) ?? .json
        favorites = Set((defaults?.stringArray(forKey: "MacPocket.practical.favorites") ?? []).compactMap(PracticalTool.init(rawValue:)))
    }

    func draft(for tool: PracticalTool) -> PracticalDraft { drafts[tool] ?? PracticalDraft() }

    func update(_ draft: PracticalDraft, for tool: PracticalTool) {
        if running == tool { cancel() }
        drafts[tool] = draft
        results[tool] = nil
        errors[tool] = nil
        if tool == .caseConverter { scheduleCasePreview() }
    }

    func selectCaseFormat(_ format: CaseFormat) {
        var draft = draft(for: .caseConverter); draft.caseFormat = format
        drafts[.caseConverter] = draft
        if var result = results[.caseConverter], let preview = result.casePreviews.first(where: { $0.format == format }) {
            result.text = preview.text
            results[.caseConverter] = result
        }
    }

    func selectionChanged() {
        previewTask?.cancel(); previewTask = nil
        if running == .caseConverter && selected != .caseConverter { cancel() }
        if selected == .caseConverter { scheduleCasePreview() }
    }

    private func scheduleCasePreview() {
        previewTask?.cancel(); previewTask = nil
        let draft = draft(for: .caseConverter)
        guard selected == .caseConverter, draft.caseLive, !draft.input.isEmpty,
              running == nil, results[.caseConverter] == nil else { return }
        previewTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.selected == .caseConverter, self.running == nil else { return }
            self.previewTask = nil
            self.run(.caseConverter)
        }
    }

    func clear(_ tool: PracticalTool) {
        if tool == .caseConverter { previewTask?.cancel(); previewTask = nil }
        if running == tool { cancel() }
        drafts[tool] = nil; results[tool] = nil; errors[tool] = nil
    }

    func toggleFavorite(_ tool: PracticalTool) {
        if favorites.contains(tool) { favorites.remove(tool) } else { favorites.insert(tool) }
        defaults?.set(PracticalTool.allCases.filter(favorites.contains).map(\.rawValue), forKey: "MacPocket.practical.favorites")
    }

    func cancel() {
        previewTask?.cancel(); previewTask = nil
        generation = UUID(); task?.cancel(); task = nil; running = nil
    }

    func run(_ tool: PracticalTool) {
        guard running == nil else { return }
        previewTask?.cancel(); previewTask = nil
        let draft = draft(for: tool), token = UUID()
        generation = token; running = tool; errors[tool] = nil; results[tool] = nil
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { try PracticalExecution.run(tool, draft: draft) }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                var final = result
                if tool == .caseConverter, let chosen = final.casePreviews.first(where: { $0.format == self.draft(for: tool).caseFormat }) {
                    final.text = chosen.text
                }
                self.results[tool] = final; self.running = nil; self.task = nil
                if tool != .caseConverter { self.scheduleCasePreview() }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.errors[tool] = error.localizedDescription; self.running = nil; self.task = nil
                if tool != .caseConverter { self.scheduleCasePreview() }
            }
        }
    }

    func report(_ message: String, for tool: PracticalTool) { errors[tool] = message }
}

struct PracticalToolsView: View {
    @StateObject private var workspace: PracticalWorkspace
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var revealPassword = false
    @State private var detailWidth: CGFloat = 700
    @State private var caseAdvanced = false
    @State private var casePreviewsExpanded = true
    @FocusState private var searchFocused: Bool

    init(workspace: PracticalWorkspace = .shared) { _workspace = StateObject(wrappedValue: workspace) }

    private var tool: PracticalTool { workspace.selected }
    private var draft: PracticalDraft { workspace.draft(for: tool) }
    private var visible: [PracticalTool] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return PracticalTool.allCases.filter {
            (!favoritesOnly || workspace.favorites.contains($0)) &&
                (query.isEmpty || ($0.localizedTitle + " " + $0.detail + " " + $0.group.localizedTitle).localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Pratik Araçlar", subtitle: "Dönüştür, incele ve üret. İşlemler bu Mac’te çalışır.",
                              icon: "square.grid.3x3") {
                PocketStatusBadge(text: "Çevrimdışı", systemImage: "desktopcomputer", tone: .accent)
            }
            HStack(alignment: .top, spacing: 0) {
                toolList.frame(width: 218)
                Divider()
                workbench.id(tool)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
            }
            .pocketCard(padding: 0)
            Text("İçerikler otomatik kaydedilmez. Panodan alma, kopyalama ve dışa aktarma sen istediğinde yapılır.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .pocketPage()
        .onChange(of: tool) { _, _ in revealPassword = false; workspace.selectionChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
    }

    private var toolList: some View {
        VStack(alignment: .leading, spacing: 0) {
            PocketSearchField("Pratik araç ara", text: $search, focus: $searchFocused).padding(PocketSpacing.s)
            Toggle(isOn: $favoritesOnly) { Label("Yalnız favoriler", systemImage: favoritesOnly ? "star.fill" : "star") }
                .toggleStyle(.checkbox).padding(.horizontal, PocketSpacing.m).padding(.bottom, PocketSpacing.s)
            List(selection: $workspace.selected) {
                ForEach(PracticalToolGroup.allCases) { group in
                    let tools = visible.filter { $0.group == group }
                    if !tools.isEmpty {
                        Section(group.localizedTitle) {
                            ForEach(tools) { tool in
                                HStack {
                                    Label(tool.localizedTitle, systemImage: tool.symbol)
                                    Spacer(minLength: 2)
                                    if workspace.favorites.contains(tool) { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange).accessibilityLabel("Favori") }
                                }
                                .tag(tool).padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset).scrollContentBackground(.hidden)
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView {
                        Label("Araç bulunamadı", systemImage: favoritesOnly ? "star" : "magnifyingglass")
                    } description: {
                        Text("Aramayı temizle veya favori filtresini kapat.")
                    } actions: {
                        Button("Tüm Araçları Göster") { search = ""; favoritesOnly = false }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                Text("Diğer MacPocket araçları").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button { open("screen-grab") } label: { Label("Renk seç ve QR oku", systemImage: "text.viewfinder") }
                Button { open("local-network") } label: { Label("Ağ ve MAC üreticileri", systemImage: "network") }
            }.controlSize(.small).padding(PocketSpacing.m)
        }
    }

    private var workbench: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    HStack(alignment: .top) {
                        Label(tool.localizedTitle, systemImage: tool.symbol).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 4)
                        Button { workspace.toggleFavorite(tool) } label: {
                            Image(systemName: workspace.favorites.contains(tool) ? "star.fill" : "star")
                        }
                        .buttonStyle(.borderless)
                        .help(workspace.favorites.contains(tool) ? "Favorilerden çıkar" : "Favorilere ekle")
                        .accessibilityLabel(workspace.favorites.contains(tool) ? "Favorilerden çıkar" : "Favorilere ekle")
                    }
                    Text(tool.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                options
                if tool != .uuid && tool != .password {
                    if tool == .qr && draft.wifi { wifiFields }
                    else if tool == .diff { diffInputs }
                    else { editor("Girdi", text: binding(\.input)) }
                }
                actions
                if workspace.running == tool { PocketProgressRow(message: "İşleniyor…") }
                if let error = workspace.errors[tool] { PocketMessage(error, tone: .warning) }
                if tool == .jwt {
                    PocketMessage("İmza doğrulanmaz. Zaman bilgileri tokenın kendi bildirdiği değerlerdir.", tone: .neutral)
                }
                if let result = workspace.results[tool] { output(result) }
                else if workspace.running != tool {
                    Label("İşlemi çalıştırdığında sonuç burada görünür.", systemImage: "arrow.down.doc")
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90)
                }
            }
            .padding(PocketSpacing.l)
        }
    }

    @ViewBuilder private var options: some View {
        switch tool {
        case .caseConverter: caseOptions
        case .json:
            Picker("İşlem", selection: binding(\.compact)) {
                Text("Okunabilir biçim").tag(false); Text("Küçült").tag(true)
            }.pickerStyle(.segmented)
        case .base64, .url:
            Picker("İşlem", selection: binding(\.reverse)) {
                Text("Kodla").tag(false); Text("Çöz").tag(true)
            }.pickerStyle(.segmented)
            if tool == .base64 { Toggle("URL uyumlu Base64", isOn: binding(\.urlSafe)).toggleStyle(.checkbox) }
            if tool == .url {
                Text("Bir parametre değerini kodlar. Çözme işleminde + işareti korunur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .hash:
            Picker("Algoritma", selection: binding(\.hash)) {
                ForEach(PracticalHash.allCases) { Text($0.localizedTitle).tag($0) }
            }.pickerStyle(.segmented)
        case .uuid:
            Stepper(value: binding(\.count), in: 1...100) { Text("Adet: \(draft.count)") }
            Toggle("Büyük harf kullan", isOn: binding(\.uppercaseUUID)).toggleStyle(.checkbox)
        case .password:
            Stepper(value: binding(\.length), in: 8...128) { Text("Uzunluk: \(draft.length)") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading) {
                Toggle("Büyük harf", isOn: binding(\.uppercase))
                Toggle("Küçük harf", isOn: binding(\.lowercase))
                Toggle("Rakam", isOn: binding(\.digits))
                Toggle("Sembol", isOn: binding(\.symbols))
            }.toggleStyle(.checkbox)
        case .timestamp:
            Picker("Yön", selection: binding(\.reverse)) {
                Text("Unix → Tarih").tag(false); Text("Tarih → Unix").tag(true)
            }.pickerStyle(.segmented)
            Picker("Unix birimi", selection: binding(\.milliseconds)) {
                Text("Saniye").tag(false); Text("Milisaniye").tag(true)
            }
            if !draft.reverse {
                Picker("Sonuç saat dilimi", selection: binding(\.utc)) {
                    Text("Yerel (\(TimeZone.current.identifier))").tag(false)
                    Text("UTC").tag(true)
                }
            }
            Text(draft.reverse ? "Örnek: 2026-11-05T12:30:00+03:00" : "Saniye ve milisaniye birimlerini karıştırma; birimi yukarıdan seç.")
                .font(.caption).foregroundStyle(.secondary)
        case .qr:
            Picker("QR içeriği", selection: binding(\.wifi)) {
                Text("Metin veya bağlantı").tag(false); Text("Wi-Fi ağı").tag(true)
            }.pickerStyle(.segmented)
        case .jwt, .diff: EmptyView()
        }
    }

    private var caseOptions: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Picker("Sonuç biçimi", selection: Binding(get: { draft.caseFormat }, set: { workspace.selectCaseFormat($0) })) {
                Section("Metin biçimleri") {
                    ForEach(CaseFormat.allCases.filter { !$0.usesWords }) { Text($0.localizedTitle).tag($0) }
                }
                Section("Kod ve ad biçimleri") {
                    ForEach(CaseFormat.allCases.filter(\.usesWords)) { Text($0.localizedTitle).tag($0) }
                }
            }
            Picker("Harf kuralları", selection: binding(\.caseOptions.language)) {
                ForEach(CaseLanguage.allCases) { Text($0.localizedTitle).tag($0) }
            }.pickerStyle(.segmented)
            Text("Türkçe kurallarda i → İ, I → ı; İngilizce kurallarda i → I uygulanır.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Yazarken önizle", isOn: binding(\.caseLive)).toggleStyle(.checkbox)
            Toggle("Her satırı ayrı dönüştür", isOn: binding(\.caseOptions.lineByLine)).toggleStyle(.checkbox)
            DisclosureGroup("Gelişmiş dönüşüm seçenekleri", isExpanded: $caseAdvanced) {
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    Toggle("Boş satırları koru", isOn: binding(\.caseOptions.keepBlankLines))
                        .disabled(!draft.caseOptions.lineByLine)
                    Toggle("Latin harflerini sadeleştir (ç → c, ı → i)", isOn: binding(\.caseOptions.simplifyLatin))
                    Toggle("HTTPServer gibi kısaltmaları ayır", isOn: binding(\.caseOptions.splitAcronyms))
                    Toggle("Sayıları ayrı sözcük olarak işle", isOn: binding(\.caseOptions.separateNumbers))
                    Toggle("Tamamı büyük yazılmış sözcükleri koru", isOn: binding(\.caseOptions.preserveAcronyms))
                    Toggle("Değişken adı rakamla başlarsa _ ekle", isOn: binding(\.caseOptions.prefixNumericIdentifiers))
                }.toggleStyle(.checkbox).padding(.top, PocketSpacing.xs)
            }
            Text("Kod biçimlerinde noktalama ve emojiler ayraç sayılır. Metin biçimleri bunları korur. En fazla 64 KiB metin kullanabilirsin.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func casePreviewList(_ previews: [CasePreview]) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Biçim sayısı: \(previews.count)").font(.callout.weight(.semibold))
                    Spacer(minLength: 4)
                    Button("Tüm Biçimleri Kopyala") { copyAllCases(previews) }
                }
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    Text("Biçim sayısı: \(previews.count)").font(.callout.weight(.semibold))
                    Button("Tüm Biçimleri Kopyala") { copyAllCases(previews) }
                }
            }
            Button("Sonucu Girdi Yap") {
                guard let text = workspace.results[.caseConverter]?.text else { return }
                var value = draft; value.input = text
                workspace.update(value, for: .caseConverter)
            }.disabled(workspace.results[.caseConverter]?.text.isEmpty != false)
            DisclosureGroup("Tüm biçimleri karşılaştır", isExpanded: $casePreviewsExpanded) {
                LazyVStack(alignment: .leading, spacing: PocketSpacing.s) {
                    ForEach(previews) { preview in
                        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                            HStack {
                                Button { workspace.selectCaseFormat(preview.format) } label: {
                                    Label(preview.format.localizedTitle,
                                          systemImage: draft.caseFormat == preview.format ? "checkmark.circle.fill" : "circle")
                                        .font(.callout.weight(.semibold))
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(Text("\(preview.format.localizedTitle) biçimini seç"))
                                    .accessibilityValue(draft.caseFormat == preview.format ? Text("Seçili") : Text("Seçili değil"))
                                Spacer(minLength: 4)
                                Button { copy(preview.text) } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.borderless)
                                    .help("Bu biçimi kopyala")
                                    .accessibilityLabel(Text("\(preview.format.localizedTitle) sonucunu kopyala"))
                            }
                            Text(verbatim: preview.text.isEmpty ? String(localized: "(boş metin)") : String(preview.text.prefix(240)) + (preview.text.count > 240 ? "…" : ""))
                                .font(.system(.caption, design: .monospaced)).lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(PocketSpacing.s)
                        .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: PocketRadius.small))
                    }
                }.padding(.top, PocketSpacing.s)
            }
            Text("Kartlar kısa önizlemedir; kopyalama düğmeleri metnin tamamını alır.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func copyAllCases(_ previews: [CasePreview]) {
        copy(previews.map { $0.format.localizedTitle + "\n" + $0.text }.joined(separator: "\n\n"))
    }

    private var wifiFields: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text("Ağ adı (SSID)").font(.callout.weight(.medium))
            TextField("Wi-Fi ağ adı", text: binding(\.ssid)).textFieldStyle(.roundedBorder).accessibilityLabel("Ağ adı (SSID)")
            Toggle("Parolasız ağ", isOn: binding(\.wifiOpen)).toggleStyle(.checkbox)
            if !draft.wifiOpen {
                Text("Wi-Fi parolası").font(.callout.weight(.medium))
                SecureField("Wi-Fi parolası", text: binding(\.wifiPassword)).textFieldStyle(.roundedBorder)
            }
            Toggle("Gizli ağ", isOn: binding(\.wifiHidden)).toggleStyle(.checkbox)
        }
    }

    private var diffInputs: some View {
        Group {
            if detailWidth >= 620 {
                HStack(alignment: .top, spacing: PocketSpacing.m) {
                    editor("Önceki metin", text: binding(\.input))
                    editor("Yeni metin", text: binding(\.second))
                }
            } else {
                editor("Önceki metin", text: binding(\.input))
                editor("Yeni metin", text: binding(\.second))
            }
        }
    }

    private func editor(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer(minLength: 2)
                Button { paste(into: text) } label: { Label("Panodan Al", systemImage: "clipboard") }
                    .controlSize(.small).disabled(workspace.running != nil)
            }
            TextEditor(text: text).font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden).padding(7)
                .frame(height: tool == .diff ? 170 : 150)
                .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: PocketRadius.small))
                .overlay { RoundedRectangle(cornerRadius: PocketRadius.small).strokeBorder(PocketTheme.line) }
                .accessibilityLabel(Text(title))
            Text("UTF-8 bayt: \(text.wrappedValue.utf8.count) / \(tool == .caseConverter ? CaseConverter.maximumInputBytes : PracticalTools.maximumInputBytes)")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PocketSpacing.s) { actionButtons }
            VStack(alignment: .leading, spacing: PocketSpacing.s) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button { workspace.run(tool); revealPassword = false } label: {
            Label(tool == .uuid || tool == .password || tool == .qr ? "Oluştur" : tool == .diff ? "Karşılaştır" : tool == .caseConverter ? "Dönüştür" : "Çalıştır",
                  systemImage: tool == .uuid || tool == .password || tool == .qr ? "sparkles" : "play.fill")
        }.buttonStyle(.pocketPrimary).disabled(workspace.running != nil)
            .keyboardShortcut(.return, modifiers: .command)
        if tool != .uuid && tool != .password {
            Button("Örnek Veri") { workspace.update(PracticalExecution.example(tool, draft: draft), for: tool) }
                .disabled(workspace.running != nil)
        }
        if tool == .timestamp {
            Button("Şimdi") {
                var value = draft
                value.input = value.reverse ? Date().formatted(.iso8601) : ((try? PracticalTools.unix(Date(), milliseconds: value.milliseconds)) ?? "")
                workspace.update(value, for: tool)
            }.disabled(workspace.running != nil)
        }
        Button("Temizle") { workspace.clear(tool); revealPassword = false }
        if workspace.running == tool { Button("İptal Et", role: .cancel) { workspace.cancel() } }
    }

    @ViewBuilder private func output(_ result: PracticalResult) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack { outputHeading(result) }
                VStack(alignment: .leading, spacing: PocketSpacing.s) { outputHeading(result) }
            }
            ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                Text(verbatim: note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let png = result.png, let image = NSImage(data: png) {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 260, maxHeight: 260)
                    .background(.white).accessibilityLabel("Oluşturulan QR kodu")
            } else if tool == .password && !revealPassword {
                HStack {
                    Text(verbatim: String(repeating: "•", count: min(result.text.count, 32))).font(.system(.title3, design: .monospaced))
                    Spacer(minLength: 4)
                    Button("Göster") { revealPassword = true }
                }.pocketCard(padding: PocketSpacing.m)
            } else if result.text.isEmpty {
                Text("İşlem tamamlandı; sonuç boş bir metin.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    if tool == .diff {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(result.lines) { line in
                                Text(verbatim: line.prefix + " " + line.text)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(line.kind == .added ? Color.green.opacity(0.10) : line.kind == .removed ? Color.red.opacity(0.10) : Color.clear)
                            }
                        }.font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    } else {
                        Text(verbatim: result.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: tool == .caseConverter ? 140 : 230)
                .pocketCard(padding: PocketSpacing.m)
                if tool == .password { Button("Gizle") { revealPassword = false }.controlSize(.small) }
            }
            if !result.casePreviews.isEmpty { casePreviewList(result.casePreviews) }
        }
    }

    @ViewBuilder private func outputHeading(_ result: PracticalResult) -> some View {
        Text("Sonuç").font(.headline).accessibilityAddTraits(.isHeader)
        Spacer(minLength: 4)
        Button { copy(result.text) } label: { Label("Kopyala", systemImage: "doc.on.doc") }.disabled(result.text.isEmpty)
        Button { export(result) } label: {
            Label(result.png == nil ? "Kaydet…" : "PNG Kaydet…", systemImage: "square.and.arrow.down")
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<PracticalDraft, Value>) -> Binding<Value> {
        let selected = tool
        return Binding(get: { workspace.draft(for: selected)[keyPath: path] }, set: { value in
            var draft = workspace.draft(for: selected); draft[keyPath: path] = value
            workspace.update(draft, for: selected)
        })
    }

    private func paste(into binding: Binding<String>) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            workspace.report(String(localized: "Panoda metin yok."), for: tool); return
        }
        do { try PracticalTools.validateSize(text); binding.wrappedValue = text }
        catch { workspace.report(error.localizedDescription, for: tool) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Our clipboard history already honors this marker; temporary tool output is not archived.
        NSPasteboard.general.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        PocketToast.show(String(localized: "Panoya kopyalandı."), symbol: "doc.on.doc")
    }

    private func export(_ result: PracticalResult) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = result.png == nil ? (tool == .json ? [.json] : [.plainText]) : [.png]
        panel.nameFieldStringValue = tool.localizedTitle + (result.png == nil ? (tool == .json ? ".json" : ".txt") : ".png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let png = result.png { try png.write(to: url, options: .atomic) }
            else { try result.text.write(to: url, atomically: true, encoding: .utf8) }
            PocketToast.show(String(localized: "Kaydedildi."), symbol: "checkmark.circle")
        } catch { workspace.report(error.localizedDescription, for: tool) }
    }

    private func open(_ id: String) { NotificationCenter.default.post(name: .pocketOpenTool, object: id) }
}
