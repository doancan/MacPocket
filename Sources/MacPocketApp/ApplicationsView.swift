import AppKit
import MacPocketCore
import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var model: ApplicationWorkspaceModel
    @State private var uninstallPlan: UninstallPlan?
    @State private var pendingUpdate: HomebrewCask?
    @State private var confirmUpdate = false
    @State private var showUpdatesInfo = false
    @FocusState private var searchFocused: Bool

    private var working: Bool { model.busy || model.checkingUpdates || model.updatingToken != nil }
    private var progressMessage: String {
        if let token = model.updatingToken {
            // `packageAction` names the running Homebrew command; compared in both raw and localized form.
            let removing = ["kaldırılıyor", String(localized: "kaldırılıyor")].contains(model.packageAction)
            return removing ? String(localized: "\(token) Homebrew ile kaldırılıyor…") : String(localized: "\(token) Homebrew ile güncelleniyor…")
        }
        return model.checkingUpdates ? String(localized: "Güncellemeler kontrol ediliyor…") : String(localized: "Uygulamalar inceleniyor…")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Uygulamalar", subtitle: "Kurulu uygulamalar, güncellemeler ve ilişkili dosyalar.", icon: "app.badge") {
                headingActions
            }
            GlassTabBar(tabs: [GlassTab(id: false, title: "Kurulu Uygulamalar", symbol: "square.grid.2x2"),
                               GlassTab(id: true, title: "Güncellemeler", symbol: "arrow.down.circle")],
                        selection: $model.showUpdates)
            .accessibilityLabel("Bölüm")
            .frame(maxWidth: 360)
            if working { PocketProgressRow(message: progressMessage) }
            if let error = model.failure { PocketMessage(error, tone: .warning) }
            if let result = model.resultMessage { lastOperation(result) }
            if model.showUpdates { updateList } else { installedList }
        }
        .pocketPage()
        .task { if !model.loaded { await model.load() } }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in
            model.showUpdates = false
            searchFocused = true
        }
        .sheet(item: $uninstallPlan) { plan in
            UninstallPlanView(plan: plan, model: model)
        }
        .alert("Uygulama güncellensin mi?", isPresented: $confirmUpdate) {
            Button("Vazgeç", role: .cancel) { pendingUpdate = nil }
            Button("Homebrew ile Güncelle") {
                if let update = pendingUpdate { Task { await model.upgrade(update) } }
                pendingUpdate = nil
            }
        } message: {
            if let update = pendingUpdate {
                Text("\(update.name): \(update.installedVersion) → \(update.currentVersion). Uygulamanın açık pencerelerini ve çalışmalarını kapatmalısın. Güncelleme Homebrew tarafından yürütülür.")
            }
        }
    }

    @ViewBuilder
    private var headingActions: some View {
        HStack(spacing: PocketSpacing.s) {
            if model.showUpdates {
                Button("Güncellemeleri Kontrol Et") { Task { await model.checkUpdates() } }
                    .buttonStyle(.pocketPrimary)
                    .disabled(model.busy || model.checkingUpdates || model.updatingToken != nil)
                    .help("Homebrew kataloğunda yeni sürümleri ara")
            } else {
                Button("Klasör Ekle…") { model.chooseApplicationFolder() }
                    .disabled(model.busy)
                    .help("Standart konumlar dışındaki bir uygulama klasörünü envantere ekle")
                Button("Yenile") { Task { await model.load() } }
                    .disabled(model.busy)
                    .help("Uygulama envanterini yeniden oku")
            }
        }
    }

    private func lastOperation(_ result: String) -> some View {
        DisclosureGroup {
            ScrollView {
                Text(String(result.prefix(5000)))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        } label: {
            Label("Son işlem tamamlandı", systemImage: PocketTone.success.symbol)
                .foregroundStyle(PocketTone.success.color)
        }
        .font(.callout)
        .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
    }

    // MARK: Installed

    private var installedList: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketSearchField("Uygulama veya bundle kimliği ara…", text: $model.search, focus: $searchFocused)
                    .frame(maxWidth: 380)
                    .accessibilityLabel("Uygulama ara")
                Spacer(minLength: PocketSpacing.s)
                Text("\(model.filtered.count) uygulama")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 0) {
                InstalledApplicationsTable(model: model)
                    .overlay { installedEmptyState }
                if let app = model.selectedApplication {
                    Divider()
                    ApplicationInspector(app: app, model: model) { plan in uninstallPlan = plan }
                        .frame(width: 280)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                    .strokeBorder(PocketTheme.line.opacity(0.6), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private var installedEmptyState: some View {
        if model.filtered.isEmpty && !model.busy {
            if !model.search.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else if model.loaded {
                ContentUnavailableView("Uygulama bulunamadı", systemImage: "app.dashed",
                                       description: Text("Standart Applications konumlarında uygulama yok. Klasör Ekle… ile başka bir konum ekleyebilirsin."))
            }
        }
    }

    // MARK: Updates

    private var updateList: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                Group {
                    if let checked = model.updatesCheckedAt {
                        Text("Son kontrol \(checked.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Henüz kontrol edilmedi")
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                Button { showUpdatesInfo.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Güncellemeler hakkında")
                    .help("Hangi uygulamalar kapsanır?")
                    .popover(isPresented: $showUpdatesInfo, arrowEdge: .bottom) {
                        Text("Yalnız Homebrew’ün yerel kataloğunda yeni sürümü bulunan uygulamalar listelenir. App Store, Setapp ve üretici güncellemeleri kendi kanallarından yönetilir.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 300)
                            .padding(PocketSpacing.l)
                    }
                Spacer(minLength: 0)
                if !model.updates.isEmpty {
                    Text("\(model.updates.count) güncelleme").font(.callout).foregroundStyle(.secondary)
                }
            }
            if model.updates.isEmpty {
                if !model.checkingUpdates {
                    ContentUnavailableView {
                        Label(model.updatesCheckedAt == nil ? "Güncellemeleri kontrol et" : "Güncelleme bulunamadı",
                              systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text("Bu sonuç yalnız Homebrew tarafından yönetilen uygulamaları kapsar.")
                    } actions: {
                        if model.updatesCheckedAt == nil {
                            Button("Güncellemeleri Kontrol Et") { Task { await model.checkUpdates() } }
                                .disabled(working)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: PocketSpacing.s) {
                        ForEach(model.updates) { update in updateRow(update) }
                    }
                }
            }
        }
    }

    private func updateRow(_ update: HomebrewCask) -> some View {
        let app = model.application(for: update)
        let name = app?.name ?? model.casks.first { $0.token == update.token }?.name ?? update.name
        let updating = model.updatingToken == update.token
        return HStack(spacing: PocketSpacing.m) {
            if let app {
                PocketAppIcon(url: app.url, size: 36)
            } else {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(PocketTheme.accent)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text(name).font(.headline).lineLimit(1)
                Text("\(update.installedVersion) → \(update.currentVersion)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: PocketSpacing.s)
            if update.pinned {
                PocketStatusBadge(text: "Sürüm sabitlenmiş" as LocalizedStringKey, systemImage: "pin", tone: .neutral)
                    .help("brew unpin ile sabitlemeyi kaldırmadan güncellenemez")
            }
            if updating {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Güncelleniyor")
            }
            Button("Güncelle…") { pendingUpdate = update; confirmUpdate = true }
                .disabled(update.pinned || model.updatingToken != nil || model.checkingUpdates)
                .help("\(name) uygulamasını Homebrew ile güncelle")
        }
        .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
        .accessibilityElement(children: .contain)
    }
}

private struct ApplicationInspector: View {
    let app: InstalledApplication
    @ObservedObject var model: ApplicationWorkspaceModel
    let reviewUninstall: (UninstallPlan) -> Void

    private var channel: String { model.cask(for: app) != nil ? "Homebrew" : app.channel.title }
    private var version: String { app.build.isEmpty || app.build == app.version ? app.version : "\(app.version) (\(app.build))" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                VStack(spacing: PocketSpacing.s) {
                    PocketAppIcon(url: app.url, size: 64)
                    Text(app.name).font(.headline).multilineTextAlignment(.center).lineLimit(2)
                    Text("Sürüm \(version)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    if app.protected {
                        PocketStatusBadge(text: "Korunuyor" as LocalizedStringKey, systemImage: "lock", tone: .neutral)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    inspectorRow("Kanal", value: channel)
                    inspectorRow("Bundle kimliği", value: app.bundleID, monospaced: true)
                    inspectorRow("Konum", value: app.url.deletingLastPathComponent().path)
                }

                Divider()

                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    Button { NSWorkspace.shared.open(app.url) } label: {
                        Label("Uygulamayı Aç", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                    }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: {
                        Label("Finder’da Göster", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    Button(role: .destructive) {
                        do { reviewUninstall(try UninstallPlanner.plan(app)) }
                        catch { model.failure = error.localizedDescription }
                    } label: {
                        Label("Kaldırma Planını İncele…", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .disabled(app.protected || model.busy || model.updatingToken != nil)
                    .help("Hiçbir şey hemen silinmez; önce kaldırılacak öğeleri seçersin")
                    Text(app.protected ? "Sistem uygulamaları ve MacPocket korunuyor."
                         : "Uygulama ve tam bundle kimliğiyle eşleşen dosyalar ayrı ayrı listelenir.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PocketSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PocketTheme.panel)
    }

    private func inspectorRow(_ title: LocalizedStringKey, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct InstalledApplicationsTable: View {
    @ObservedObject var model: ApplicationWorkspaceModel
    var body: some View {
        Table(model.filtered, selection: $model.selection) {
            TableColumn("Uygulama") { app in
                HStack(spacing: PocketSpacing.s) {
                    PocketAppIcon(url: app.url, size: 24)
                    Text(app.name).lineLimit(1)
                    if app.protected {
                        Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(.tertiary)
                            .help("Korunan uygulama")
                            .accessibilityLabel("Korunan uygulama")
                    }
                }
                .padding(.vertical, PocketSpacing.xxs)
            }
            .width(min: 180, ideal: 320)
            TableColumn("Sürüm") { app in Text(app.version).lineLimit(1).monospacedDigit() }
                .width(min: 70, ideal: 120)
            TableColumn("Kanal") { app in
                Text(verbatim: model.cask(for: app) != nil ? "Homebrew" : app.channel.title).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 105)
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            if let app = model.applications.first(where: { ids.contains($0.id) }) {
                Button("Uygulamayı Aç") { NSWorkspace.shared.open(app.url) }
                Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            }
        }
    }
}

private struct UninstallPlanView: View {
    let plan: UninstallPlan
    @ObservedObject var model: ApplicationWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var confirm = false
    private var removesHomebrewApplication: Bool {
        model.cask(for: plan.application) != nil && selected.contains(plan.application.id)
    }
    init(plan: UninstallPlan, model: ApplicationWorkspaceModel) {
        self.plan = plan; self.model = model
        _selected = State(initialValue: [plan.application.url.path])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(spacing: PocketSpacing.m) {
                PocketAppIcon(url: plan.application.url, size: 40)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Kaldırma Planı").font(.title2.weight(.semibold))
                    Text(plan.application.name).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(removesHomebrewApplication
                 ? "Uygulama Homebrew ile kaldırılır; paket kaydı da güncellenir. Seçtiğin ilişkili dosyalar Çöp’e taşınır."
                 : "Taşınacak öğeleri seç. Kullanıcı verisi içeren öğeler ayrıca işaretlenir. Hiçbir öğe henüz değiştirilmedi.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(plan.candidates) { candidate in
                        Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: { value in
                            if value { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
                        })) {
                            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                                HStack(spacing: PocketSpacing.s) {
                                    Text(candidate.title).font(.headline)
                                    if candidate.containsUserData {
                                        PocketStatusBadge(text: "Kullanıcı verisi" as LocalizedStringKey, systemImage: "person.crop.circle", tone: .warning)
                                    }
                                }
                                Text(candidate.request.url.path).font(.subheadline).foregroundStyle(.secondary)
                                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                            }.padding(.vertical, PocketSpacing.s)
                        }
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PocketSpacing.m)
                        Divider()
                    }
                }
            }
            .pocketCard(padding: 0, radius: PocketRadius.medium)
            Label("Paylaşılan üretici/App Group klasörleri ve doğrulanamayan yardımcılar plana eklenmez. Çalışan uygulama önce kapatılmalıdır.",
                  systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text("\(selected.count) öğe seçili").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(removesHomebrewApplication ? "Homebrew ile Kaldır…" : "Seçilenleri Çöp’e Taşı", role: .destructive) { confirm = true }
                    .disabled(selected.isEmpty || model.busy || model.updatingToken != nil)
            }
        }.padding(PocketSpacing.xl).frame(width: 730, height: 540)
        .alert(removesHomebrewApplication ? "Homebrew uygulaması kaldırılsın mı?" : "Seçilen öğeler Çöp’e taşınsın mı?", isPresented: $confirm) {
            Button("Vazgeç", role: .cancel) {}
            Button(removesHomebrewApplication ? "Homebrew ile Kaldır" : "Çöp’e Taşı", role: .destructive) {
                let selection = selected
                Task { await model.uninstall(plan, selected: selection) }
                dismiss()
            }
        } message: {
            Text(removesHomebrewApplication
                 ? "\(plan.application.name) ve paket kaydı Homebrew tarafından kaldırılır. Uygulamanın kendisi Çöp’e gitmeyebilir; geri almak için yeniden kurman gerekir. Seçili ilişkili dosyalar Çöp’e taşınır."
                 : "\(plan.application.name) için \(selected.count) öğe seçildi. Seçili kullanıcı verileri de taşınır. Gerekirse Finder’daki Çöp’ten geri alabilirsin.")
        }
    }
}
