import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class WindowSwitcherModel: ObservableObject {
    @Published var windows: [SwitchableWindow] = []
    @Published var trusted = false
    @Published var partial = false
    @Published var busy = false
    @Published var failure: String?
    @Published var selection: String?
    @Published var search = ""
    private let catalog = WindowCatalog()
    var filtered: [SwitchableWindow] {
        windows.filter { search.isEmpty || "\($0.application) \($0.title)".localizedCaseInsensitiveContains(search) }
    }
    var selected: SwitchableWindow? { filtered.first { $0.id == selection } }
    func refresh() async {
        guard !busy else { return }
        busy = true
        let report = await catalog.snapshot()
        windows = report.windows; trusted = report.accessibilityGranted; partial = report.partial
        selection = filtered.first?.id; busy = false
    }
    func focus() async {
        guard let selected else { return }
        do { try await catalog.focus(selected.id); failure = nil }
        catch { failure = error.localizedDescription }
    }
}

struct WindowSwitcherView: View {
    @StateObject private var model = WindowSwitcherModel()
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PocketPageHeading(title: "Pencere Geçişi", subtitle: "Açık pencerelerini bul ve seçtiğini öne getir.", icon: "macwindow.on.rectangle")
            if !model.trusted {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pencere erişimi gerekiyor").font(.headline)
                        Text("Erişilebilirlik izni olmadan yalnız uygulamalar listelenir. İzin verildiğinde pencere başlıkları ve tek pencereye geçiş açılır.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Erişim İste…") { WindowCatalog.requestAccessibilityPermission() }
                }.padding(16).background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            if let failure = model.failure { PocketMessage(failure, error: true) }
            if model.partial { PocketMessage("Pencere listesi süre veya öğe sınırına ulaştı. Liste kısmi; yeniden deneyebilirsin.", error: true) }
            HStack {
                TextField("Uygulama veya pencere ara…", text: $model.search).textFieldStyle(.roundedBorder)
                    .focused($searchFocused).frame(maxWidth: 360)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Yenile") { Task { await model.refresh() } }.disabled(model.busy)
            }
            Table(model.filtered, selection: $model.selection) {
                TableColumn("Uygulama") { window in
                    HStack(spacing: 10) {
                        if let url = window.applicationURL { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24) }
                        Text(window.application)
                    }.padding(.vertical, 4)
                }.width(min: 160, ideal: 260)
                TableColumn("Pencere") { window in Text(window.title).lineLimit(1) }
                TableColumn("Durum") { window in Text(window.minimized ? "Küçültülmüş" : (window.windowAccessible ? "Açık" : "Uygulama")) }.width(110)
            }.tableStyle(.inset)
            HStack {
                Text("\(model.filtered.count) öğe · Başka Space ve tam ekran davranışı macOS izinlerine bağlıdır.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.selected?.windowAccessible == true ? "Pencereyi Öne Getir" : "Uygulamayı Öne Getir") { Task { await model.focus() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.selected == nil)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
    }
}
