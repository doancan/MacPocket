import AppKit
@preconcurrency import Carbon
import MacPocketCore
import SwiftUI

/// Tools → Pencere Geçişi: switcher settings and the detailed window table.
struct WindowSwitcherView: View {
    @ObservedObject private var controller = WindowSwitcherHotkeyController.shared
    /// Created on first appearance: `@State` would otherwise build a model (catalog, observers) on every view init.
    @State private var model: WindowSwitcherModel?
    @State private var section = Section.settings
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenRecording = WindowPreviewProvider.permitted
    @State private var secureInput = SecureKeyboardInputStatus.read()

    private enum Section: String, CaseIterable {
        case settings, windows
        var title: LocalizedStringKey { self == .settings ? "Ayarlar" : "Pencereler" }
        var symbol: String { self == .settings ? "slider.horizontal.3" : "macwindow.on.rectangle" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Pencere Geçişi", subtitle: "Windows tarzı Alt+Tab: canlı küçük resimlerle pencereler arasında geçiş.",
                              icon: "macwindow.on.rectangle") {
                Button { controller.show() } label: { Label("Önizle", systemImage: "play.rectangle") }
                    .help("Pencere geçişini şimdi aç")
            }
            permissions
            if secureInput.enabled { secureInputNotice }
            GlassTabBar(tabs: Section.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol) }, selection: $section)
                .accessibilityLabel("Bölüm")
                .frame(maxWidth: 320)
            switch section {
            case .settings: SwitcherSettingsForm(controller: controller)
            case .windows: if let model { SwitcherWindowTable(model: model) }
            }
        }
        .pocketPage()
        .onAppear {
            let model = model ?? WindowSwitcherModel()
            self.model = model
            model.startObserving()
        }
        .onDisappear { model?.stopObserving() }
        .task {
            while !Task.isCancelled {
                secureInput = SecureKeyboardInputStatus.read()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibility = AXIsProcessTrusted()
            screenRecording = WindowPreviewProvider.permitted
        }
    }

    private var secureInputNotice: some View {
        let owner = secureInput.processID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? String(localized: "Başka bir uygulama")
        return Label {
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text("Güvenli Klavye Girişi açık").font(.headline)
                Text("\(owner) güvenli klavye girişini açık tutuyor. Bu durum pencere geçişi kısayollarını kapatmaz.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "keyboard.badge.ellipsis").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard(padding: PocketSpacing.m)
        .accessibilityElement(children: .combine)
    }

    private var permissions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PocketSpacing.m) { accessibilityCard; screenRecordingCard }
            VStack(spacing: PocketSpacing.m) { accessibilityCard; screenRecordingCard }
        }
    }

    private var accessibilityCard: some View {
        permissionCard(title: "Erişilebilirlik", granted: accessibility,
                       detail: "Pencere başlıkları, öne getirme, kapatma ve küçültme için.",
                       request: { WindowCatalog.requestAccessibilityPermission() },
                       settings: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private var screenRecordingCard: some View {
        permissionCard(title: "Ekran Kaydı", granted: screenRecording,
                       detail: "Canlı küçük resimler, tam boy önizleme ve diğer masaüstlerindeki bazı pencereler için.",
                       request: { WindowPreviewProvider.requestPermission() },
                       settings: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func permissionCard(title: LocalizedStringKey, granted: Bool, detail: LocalizedStringKey, request: @escaping () -> Void, settings: String) -> some View {
        HStack(alignment: .top, spacing: PocketSpacing.m) {
            Image(systemName: granted ? "checkmark.seal.fill" : "lock.fill")
                .font(.title3).foregroundStyle(granted ? PocketTheme.disk : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                HStack {
                    Text(title).font(.headline)
                    PocketStatusBadge(text: granted ? "Verildi" : "Gerekli", tone: granted ? .success : .warning)
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: PocketSpacing.s)
            if !granted {
                Menu("İzin Ver") {
                    Button("İzin İste") { request() }
                    Button("Sistem Ayarlarını Aç") { if let url = URL(string: settings) { NSWorkspace.shared.open(url) } }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard(padding: PocketSpacing.m)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Window table

private struct SwitcherWindowTable: View {
    @Bindable var model: WindowSwitcherModel
    @State private var confirmClose = false
    @State private var pendingClose: SwitchableWindow?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            if let failure = model.failure { PocketMessage(failure, error: true) }
            if model.partial { PocketMessage("Liste kısmi olabilir. Yenileyebilirsin.", tone: .warning) }
            if model.trusted && !model.otherSpacesVisible {
                PocketMessage("Diğer masaüstlerindeki bazı pencereleri listelemek için Ekran Kaydı izni gerekir.", tone: .neutral)
            }
            if model.order == .space && (!model.spaceMetadataAvailable || model.spaceMetadataPartial) {
                PocketMessage("Masaüstü bilgisi alınamayan pencereler listenin sonunda son kullanım sırasıyla gösterilir.", tone: .neutral)
            }
            if model.order == .creation { SwitcherCreationOrderNote() }
            HStack {
                PocketSearchField("Uygulama veya pencere ara…", text: $model.search, focus: $searchFocused).frame(maxWidth: 360)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { Task { await model.refresh() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }.disabled(model.busy)
            }
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                Table(model.filtered, selection: $model.selection) {
                    TableColumn("Uygulama") { window in
                        HStack(spacing: PocketSpacing.s) {
                            PocketAppIcon(url: window.applicationURL, size: 22)
                            Text(window.application).lineLimit(1)
                        }
                    }.width(min: 140, ideal: 200)
                    TableColumn("Pencere") { window in Text(window.title).lineLimit(1) }
                    TableColumn("Durum") { window in
                        Text(state(window)).foregroundStyle(.secondary)
                            .help(window.spaceMembership?.localizedDescription ?? String(localized: "Masaüstü bilgisi bilinmiyor"))
                    }.width(120)
                }
                .tableStyle(.inset)
                .contextMenu {
                    Button("Öne Getir") { Task { await model.focus() } }.disabled(model.selected == nil)
                    Button("Uygulamayı Gizle") { Task { await model.action(.hideApplication) } }.disabled(model.selected == nil)
                    Button("Bu Uygulamayı Hariç Tut") { model.excludeSelected() }.disabled(model.selected?.applicationURL == nil)
                }
                previewPane.frame(width: 240)
            }
            HStack {
                Menu("Pencere İşlemleri") {
                    Button(model.selected?.minimized == true ? "Küçültmeyi Geri Al" : "Küçült") {
                        Task { await model.action(model.selected?.minimized == true ? .restore : .minimize) }
                    }.disabled(model.selected?.canMinimize != true)
                    Button(model.selected?.fullScreen == true ? "Tam Ekrandan Çık" : "Tam Ekrana Geç") { Task { await model.action(.toggleFullScreen) } }
                        .disabled(model.selected?.canFullScreen != true)
                    Button("Uygulamayı Gizle") { Task { await model.action(.hideApplication) } }.disabled(model.selected == nil)
                    Button("Pencereyi Kapat…", role: .destructive) { pendingClose = model.selected; confirmClose = true }
                        .disabled(model.selected?.canClose != true)
                    Divider()
                    Button("Bu Uygulamayı Hariç Tut") { model.excludeSelected() }.disabled(model.selected?.applicationURL == nil)
                }
                .fixedSize()
                Text("\(model.filtered.count) öğe").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(model.selected?.isRealWindow == true ? "Pencereyi Öne Getir" : "Uygulamayı Öne Getir") { Task { await model.focus() } }
                    .buttonStyle(.pocketPrimary).keyboardShortcut(.defaultAction).disabled(model.selected == nil || model.busy)
            }
        }
        .task(id: model.lifecycleRevision) { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .onChange(of: model.selection) { _, _ in model.preview = nil; model.previewMessage = nil }
        .alert("Pencere kapatılsın mı?", isPresented: $confirmClose) {
            Button("Vazgeç", role: .cancel) {}
            Button("Pencereyi Kapat", role: .destructive) { if let id = pendingClose?.id { Task { await model.action(.close, id: id) } } }
        } message: {
            let application = pendingClose?.application ?? String(localized: "Uygulama")
            let title = pendingClose?.title ?? String(localized: "Pencere")
            Text("\(application) · \(title). Kaydedilmemiş işler için uygulamanın kendi onayı açılabilir.")
        }
    }

    private func state(_ window: SwitchableWindow) -> String {
        if window.hidden { return String(localized: "Gizli") }
        if window.minimized { return String(localized: "Küçültülmüş") }
        if window.isOnAnotherSpace { return String(localized: "Diğer masaüstü") }
        if window.fullScreen { return String(localized: "Tam ekran") }
        if window.nativeTab?.selected == false { return String(localized: "Arka plan sekmesi") }
        return window.isRealWindow ? String(localized: "WindowState.open", defaultValue: "Açık") : String(localized: "Penceresiz")
    }

    private var previewPane: some View {
        VStack(spacing: PocketSpacing.m) {
            if let image = model.preview {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: PocketRadius.small))
            } else {
                Image(systemName: "macwindow").font(.system(size: 40)).foregroundStyle(.secondary)
            }
            if model.previewBusy { ProgressView().controlSize(.small) }
            if let message = model.previewMessage { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            if WindowPreviewProvider.permitted {
                Button("Seçili Pencereyi Önizle") { Task { await model.capturePreview() } }
                    .disabled(model.selected?.windowID == nil || model.previewBusy)
            } else {
                Text("Önizleme Ekran Kaydı izni gerektirir.").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Görüntüler yalnız bellekte tutulur; diske kaydedilmez.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pocketCard(padding: PocketSpacing.m)
    }
}

struct SwitcherCreationOrderNote: View {
    var body: some View {
        Text("Gözlem açıkken oluşturulan pencereler eskiden yeniye sıralanır. Önceden açık olanlar ve tarihi alınamayanlar sonda son kullanım sırasıyla gösterilir.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// The app already owns one settings-file workflow; link directly to its Advanced tab.
struct SwitcherSettingsTransferLink: View {
    @Environment(\.openSettings) private var openSettings
    var openOverride: (() -> Void)? = nil
    var body: some View {
        Button("Ayar aktarımını aç…") {
            PocketSettingsNavigation.shared.section = .advanced
            if let openOverride { openOverride() } else { openSettings();NSApp.activate(ignoringOtherApps: true) }
        }
        Text("Ayarlar > Gelişmiş bölümündeki aktarım; kısayolları, filtreleri, görünümü, eylemleri ve istisnaları diğer MacPocket ayarlarıyla birlikte taşır. İçe aktarma mevcut ayarların yerini alır.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
    }
}
