import AppKit
import SSHConfigKit
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel
    @Environment(\.sshNavigate) private var navigate
    @State private var saveFlow: SaveFlowModel?
    @State private var showExternalDiff = false
    @State private var confirmSaveWithPending = false
    @FocusState private var searchFocused: Bool

    private var deleteTitle: String {
        guard case .host(let alias, _)? = model.pendingDelete else { return "" }
        return String(localized: "SSH.delete.confirm.title %@", defaultValue: "“\(alias)” silinsin mi?")
    }

    var body: some View {
        GeometryReader { bounds in
            HSplitView {
                VStack(spacing: 0) {
                    // Same capsule search field as the rest of MacPocket, built from plain parts so this
                    // package stays independent of the app's design layer.
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(searchFocused ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                        TextField(String(localized: "SSH.sidebar.search.prompt", defaultValue: "Host ara"), text: $model.searchText)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                    .padding(8)
                    SidebarView(model: model)
                }
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
                VStack(spacing: 0) {
                    BannerStack(model: model, showExternalDiff: $showExternalDiff)
                    DetailView(model: model)
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
            .clipped()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacPocket.find"))) { _ in
            searchFocused = true
        }
        .onChange(of: model.store.diskText) {
            // Keep a form with blocked edits; the stale guard still protects against external changes.
            if !model.hasPendingFormEdits { model.resetEditor() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.addHost()
                } label: {
                    Label(String(localized: "SSH.toolbar.addHost", defaultValue: "Host Ekle"), systemImage: "plus")
                }
                .disabled(model.store.loadState != .loaded)
            }
            // Liquid Glass groups neighbouring items on one background: Add, then the tools, then Save.
            ToolbarSpacer(.fixed, placement: .primaryAction)
            if !model.statusCounts.isEmpty {
                ToolbarItem(placement: .status) {
                    StatusSummaryView(model: model)
                }
            }
            ToolbarItem(placement: .status) {
                if model.store.hasUnsavedChanges {
                    Label(String(localized: "SSH.toolbar.unsaved", defaultValue: "Kaydedilmemiş değişiklikler"), systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if model.connectionTests.isTestingAll {
                    Button {
                        model.connectionTests.cancelAll()
                    } label: {
                        Label(String(localized: "SSH.toolbar.stopTesting", defaultValue: "Testi Durdur"), systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        model.connectionTests.testAll(model.connectableAliases, using: model.commandBuilder)
                    } label: {
                        Label(String(localized: "SSH.toolbar.testAll", defaultValue: "Tümünü Test Et"), systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(model.connectableAliases.isEmpty)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigate(.knownHosts)
                } label: {
                    Label(String(localized: "SSH.toolbar.knownHosts", defaultValue: "Bilinen Sunucular"), systemImage: "checkmark.shield")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { navigate(.keys) } label: { Label(String(localized: "SSH.toolbar.keys", defaultValue: "Anahtarlar"), systemImage: "key") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { navigate(.settings) } label: {
                    Label(String(localized: "SSH.toolbar.settings", defaultValue: "SSH Ayarları"), systemImage: "gearshape")
                }
                .help(String(localized: "SSH.toolbar.settings.help", defaultValue: "SSH bağlantı ayarlarını açar."))
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // An unapplied group draft is applied first; only blocked form edits need the warning.
                    model.applyPendingGroupDraft()
                    if model.hasBlockedFormEdits {
                        confirmSaveWithPending = true
                    } else if model.hasPendingGroupDraft {
                        // The draft could not be applied; its error is showing. Do not save without it.
                    } else {
                        saveFlow = model.makeSaveFlow()
                    }
                } label: {
                    Label(String(localized: "SSH.action.save", defaultValue: "Kaydet"), systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(model.store.hasUnsavedChanges || model.hasPendingGroupDraft) || model.store.isSaving)
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } })
        ) {
            Button(String(localized: "SSH.action.delete", defaultValue: "Sil"), role: .destructive) { model.confirmPendingDelete() }
        } message: {
            Text(String(localized: "SSH.delete.confirm.message", defaultValue: "Host, kaydettiğinizde dosyadan kaldırılır."))
        }
        .confirmationDialog(
            String(localized: "SSH.saveWithPending.title", defaultValue: "Diğer değişiklikler yine de kaydedilsin mi?"), isPresented: $confirmSaveWithPending
        ) {
            Button(String(localized: "SSH.action.save", defaultValue: "Kaydet")) { saveFlow = model.makeSaveFlow() }
        } message: {
            Text(String(localized: "SSH.saveWithPending.message", defaultValue: "Formda sorunlar var; o alanlar kaydedilmeyecek."))
        }
        .confirmationDialog(
            String(localized: "SSH.discardForm.title", defaultValue: "Formdaki değişiklikler atılsın mı?"),
            isPresented: Binding(get: { model.hasPendingDiscardConfirmation }, set: { if !$0 { model.cancelPendingSelection() } })
        ) {
            Button(String(localized: "SSH.discardForm.discard", defaultValue: "At"), role: .destructive) { model.confirmPendingSelection() }
        } message: {
            Text(String(localized: "SSH.discardForm.message", defaultValue: "Bazı alanlarda sorun olduğu için bu değişiklikler uygulanmadı."))
        }
        .sheet(item: $saveFlow) { flow in
            SaveSheet(flow: flow) { reloaded in
                if reloaded { model.resetEditor() }
                saveFlow = nil
            }
        }
        .sheet(item: Binding(get: { model.hostKeyRemoval }, set: { if $0 == nil { model.cancelHostKeyRemoval() } })) { removal in
            HostKeyRemovalSheet(model: model, removal: removal)
        }
        .sheet(isPresented: $showExternalDiff) {
            ExternalDiffSheet(store: model.store) { showExternalDiff = false }
        }
        .alert(String(localized: "SSH.connect.automationDenied.title", defaultValue: "Terminali Kontrol Etmek İçin İzin Gerekiyor"), isPresented: $model.automationDenied) {
            Button(String(localized: "SSH.connect.automationDenied.open", defaultValue: "Gizlilik Ayarlarını Aç")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(String(localized: "SSH.action.close", defaultValue: "Kapat"), role: .cancel) {}
        } message: {
            Text(String(localized: "SSH.connect.automationDenied.message", defaultValue: "Gizlilik ve Güvenlik → Otomasyon altında MacPocket’a izin verin ve tekrar deneyin."))
        }
        .alert(
            String(localized: "SSH.connect.fellBack.title", defaultValue: "Terminal'de Açıldı"),
            isPresented: Binding(get: { model.fallbackNotice != nil }, set: { if !$0 { model.fallbackNotice = nil } })
        ) {
            Button(String(localized: "SSH.action.close", defaultValue: "Kapat")) { model.fallbackNotice = nil }
        } message: {
            Text(model.fallbackNotice ?? "")
        }
        .alert(
            String(localized: "SSH.error.title", defaultValue: "Bir Sorun Oluştu"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "SSH.action.close", defaultValue: "Kapat")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Disk (old) → mine (new) for the "file changed elsewhere" banner.
private struct ExternalDiffSheet: View {
    let store: ConfigStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "SSH.conflict.title", defaultValue: "Dosya Diskte Değişti")).font(.headline)
            DiffTextView(hunks: SaveFlowModel.diskVersusMemory(store))
                .frame(minWidth: 640, minHeight: 360)
            HStack {
                Spacer()
                Button(String(localized: "SSH.action.close", defaultValue: "Kapat"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
