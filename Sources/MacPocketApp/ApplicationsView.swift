import AppKit
import MacPocketCore
import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var model: ApplicationWorkspaceModel
    @State private var uninstallPlan: UninstallPlan?
    @State private var pendingUpdate: HomebrewCask?
    @State private var confirmUpdate = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PocketPageHeading(title: "Uygulamalar", subtitle: "Kurulu uygulamalar, güncellemeler ve ilişkili dosyalar.", icon: "app.badge")
            HStack {
                Picker("Bölüm", selection: $model.showUpdates) {
                    Text("Kurulu Uygulamalar").tag(false)
                    Text("Güncellemeler").tag(true)
                }.pickerStyle(.segmented).frame(width: 360)
                Spacer()
                if model.showUpdates {
                    Button("Güncellemeleri Kontrol Et") { Task { await model.checkUpdates() } }
                        .disabled(model.checkingUpdates || model.updatingToken != nil)
                } else {
                    Button("Klasör Ekle…") { model.chooseApplicationFolder() }.disabled(model.busy)
                    Button("Yenile") { Task { await model.load() } }.disabled(model.busy)
                }
            }
            if let error = model.failure { PocketMessage(error, error: true) }
            if let result = model.resultMessage {
                DisclosureGroup("Son İşlem") {
                    Text(String(result.prefix(5000))).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(16)
                }.font(.callout)
            }
            if model.busy || model.checkingUpdates || model.updatingToken != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.updatingToken.map { "\($0) Homebrew ile \(model.packageAction)…" }
                         ?? (model.checkingUpdates ? "Güncellemeler kontrol ediliyor…" : "Uygulamalar inceleniyor…"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if model.showUpdates { updateList }
            else { installedList }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { if !model.loaded { await model.load() } }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
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

    private var installedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Uygulama veya bundle kimliği ara…", text: $model.search)
                    .textFieldStyle(.roundedBorder).focused($searchFocused).frame(maxWidth: 380)
                Spacer()
                Text("\(model.filtered.count) uygulama").font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                InstalledApplicationsTable(model: model)
                if let app = model.selectedApplication {
                    Divider()
                    inspector(app).frame(width: 250)
                }
            }.background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func inspector(_ app: InstalledApplication) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 64, height: 64)
                Text(app.name).font(.title3.weight(.semibold))
                Text("Sürüm \(app.version) · \(app.build)").font(.callout).foregroundStyle(.secondary)
                Text(app.bundleID).font(.caption.monospaced()).textSelection(.enabled)
                Text(app.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                LabeledContent("Kanal", value: model.cask(for: app) != nil ? "Homebrew" : app.channel.rawValue).font(.callout)
                Button("Uygulamayı Aç") { NSWorkspace.shared.open(app.url) }
                Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                Divider()
                Button("Kaldırma Planını İncele", role: .destructive) {
                    do { uninstallPlan = try UninstallPlanner.plan(app) }
                    catch { model.failure = error.localizedDescription }
                }.disabled(app.protected || model.busy || model.updatingToken != nil)
                if app.protected {
                    Text("Sistem uygulamaları ve MacPocket korunuyor.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Uygulama ve tam bundle kimliğiyle eşleşen dosyalar ayrı ayrı listelenir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var updateList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Homebrew’ün yerel kataloğunda yeni sürümü bulunan uygulamalar. App Store, Setapp ve üretici güncellemeleri kendi kanallarından yönetilir.")
                .font(.callout).foregroundStyle(.secondary)
            if let date = model.updatesCheckedAt {
                Text("Son kontrol \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.updates.isEmpty {
                ContentUnavailableView(model.updatesCheckedAt == nil ? "Güncellemeleri kontrol et" : "Bu katalogda güncelleme bulunamadı",
                                       systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Bu sonuç yalnız Homebrew tarafından yönetilen uygulamaları kapsar."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.updates) { update in
                            HStack(spacing: 14) {
                                Image(systemName: "app.badge").font(.title2).foregroundStyle(PocketTheme.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.casks.first { $0.token == update.token }?.name ?? update.name).font(.headline)
                                    Text("\(update.installedVersion) → \(update.currentVersion)").font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if update.pinned { Text("Sürüm sabitlenmiş").font(.caption).foregroundStyle(.secondary) }
                                Button("Güncelle") { pendingUpdate = update; confirmUpdate = true }
                                    .disabled(update.pinned || model.updatingToken != nil || model.checkingUpdates)
                            }.padding(16).background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }
}

private struct InstalledApplicationsTable: View {
    @ObservedObject var model: ApplicationWorkspaceModel
    var body: some View {
        Table(model.filtered, selection: $model.selection) {
            TableColumn("Uygulama") { app in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28)
                    Text(app.name).lineLimit(1)
                }.padding(.vertical, 3)
            }.width(min: 180, ideal: 320)
            TableColumn("Sürüm") { app in Text(app.version).lineLimit(1).monospacedDigit() }.width(120)
            TableColumn("Kanal") { app in Text(model.cask(for: app) != nil ? "Homebrew" : app.channel.rawValue).foregroundStyle(.secondary) }.width(105)
        }.tableStyle(.inset)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(plan.application.name) · Kaldırma Planı").font(.title2.weight(.semibold))
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
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(candidate.title).font(.headline)
                                    if candidate.containsUserData { Text("Kullanıcı verisi").font(.caption).foregroundStyle(.orange) }
                                }
                                Text(candidate.request.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }.padding(.vertical, 8)
                        }.toggleStyle(.checkbox).padding(.horizontal, 8)
                        Divider()
                    }
                }
            }
            Text("Paylaşılan üretici/App Group klasörleri ve doğrulanamayan yardımcılar bu plana otomatik eklenmez. Çalışan uygulama önce kapatılmalıdır.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("\(selected.count) öğe seçili").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(removesHomebrewApplication ? "Homebrew ile Kaldır…" : "Seçilenleri Çöp’e Taşı", role: .destructive) { confirm = true }
                    .disabled(selected.isEmpty || model.busy || model.updatingToken != nil)
            }
        }.padding(24).frame(width: 730, height: 540)
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
