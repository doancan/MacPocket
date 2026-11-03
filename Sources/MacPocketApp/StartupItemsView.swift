import AppKit
import MacPocketCore
import ServiceManagement
import SwiftUI

@MainActor
final class StartupItemsModel: ObservableObject {
    @Published private(set) var snapshot: StartupItems.Snapshot?
    @Published private(set) var loading = false

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        snapshot = await StartupItems.load()
    }
}

/// Tools → Başlangıç Öğeleri: every launchd job that starts by itself, grouped by who may change it.
struct StartupItemsView: View {
    @StateObject private var model = StartupItemsModel()
    @State private var search = ""
    @State private var showsReadOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Başlangıç Öğeleri",
                              subtitle: "Oturum açıldığında ya da Mac başladığında kendiliğinden çalışan öğeleri gör; kime ait olduklarını ve açık mı kapalı mı olduklarını öğren.",
                              icon: "power") {
                HStack(spacing: PocketSpacing.s) {
                    Button { SMAppService.openSystemSettingsLoginItems() } label: {
                        Label("Giriş Öğeleri Ayarları", systemImage: "gearshape")
                    }
                    Button { Task { await model.load() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                        .disabled(model.loading)
                }
            }
            if let snapshot = model.snapshot {
                if !snapshot.stateKnown {
                    PocketMessage("Açık/kapalı durumu macOS’tan okunamadı; yalnız dosyaların kendi bilgisi gösteriliyor.", tone: .warning)
                }
                content(snapshot.items)
            } else {
                PocketProgressRow(message: "Okunuyor…")
            }
        }
        .pocketPage()
        .task { await model.load() }
    }

    private func content(_ all: [StartupItem]) -> some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let items = query.isEmpty ? all : all.filter {
            $0.label.localizedCaseInsensitiveContains(query) || ($0.appName ?? "").localizedCaseInsensitiveContains(query)
        }
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSearchField("Ara", text: $search).frame(maxWidth: 320)
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    ForEach(StartupClass.allCases) { kind in
                        let group = items.filter { $0.kind == kind }
                        if !group.isEmpty { section(kind, group) }
                    }
                    if items.isEmpty {
                        ContentUnavailableView("Öğe bulunamadı", systemImage: "power",
                                               description: Text("Bu aramayla eşleşen başlangıç öğesi yok."))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                    Label("Öğeleri açıp kapatmak için Giriş Öğeleri ayarlarını kullan; bu sayfa yalnız gösterir.", systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
    }

    @ViewBuilder
    private func section(_ kind: StartupClass, _ items: [StartupItem]) -> some View {
        let collapsed = kind == .readOnly && !showsReadOnly && search.isEmpty
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(kind.title).font(.headline)
                    Text(kind.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: PocketSpacing.m)
                Text("\(items.count) öğe").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                if kind == .readOnly, search.isEmpty {
                    Button(showsReadOnly ? "Gizle" : "Göster") { showsReadOnly.toggle() }.controlSize(.small)
                }
            }
            if !collapsed {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        StartupItemRow(item: item)
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

private struct StartupItemRow: View {
    let item: StartupItem

    var body: some View {
        HStack(spacing: PocketSpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.appName ?? item.label).lineLimit(1).truncationMode(.middle)
                Text(item.appName == nil ? (item.program ?? item.plistURL.lastPathComponent) : item.label)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: PocketSpacing.s)
            if item.runsAtLoad { PocketStatusBadge(text: "Açılışta", systemImage: "play.fill", tone: .neutral) }
            if item.keepsAlive { PocketStatusBadge(text: "Sürekli çalışır", systemImage: "arrow.triangle.2.circlepath", tone: .neutral) }
            if item.isEnabled {
                PocketStatusBadge(text: "Açık", systemImage: "checkmark.circle", tone: .success)
            } else {
                PocketStatusBadge(text: "Kapalı", systemImage: "pause.circle", tone: .warning)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plistURL]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Finder’da göster")
                .accessibilityLabel(Text("\(item.label) Finder’da göster"))
        }
        .padding(.vertical, PocketSpacing.xs)
        .help(item.plistURL.path)
    }
}
