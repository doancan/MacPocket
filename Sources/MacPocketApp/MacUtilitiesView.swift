import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

struct MacUtilitiesView: View {
    @State private var selected: MacUtility
    @State private var report: DiagnosticReport?
    @State private var running = false
    @State private var operation: Task<Void, Never>?
    @State private var failure: String?
    @State private var search = ""
    @State private var outputSearch = ""
    @FocusState private var searchFocused: Bool

    init(initialTool: MacUtility = .timeMachine) { _selected = State(initialValue: initialTool) }
    private var visible: [MacUtility] {
        MacUtility.allCases.filter { search.isEmpty || "\($0.title) \($0.category)".localizedCaseInsensitiveContains(search) }
    }
    /// Must match `MacUtility.category`, which is localized the same way.
    private static var groups: [String] {
        [String(localized: "Disk ve Arama"), String(localized: "Ağ"), String(localized: "Sistem"), String(localized: "Güvenlik")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "macOS Araçları",
                              subtitle: "Disk, ağ, oturum ve güvenlik için gerçek sistem sorguları.",
                              icon: "wrench.and.screwdriver") {
                Menu {
                    Button("Gizlilik ve Güvenlik…") { openSettings("x-apple.systempreferences:com.apple.preference.security") }
                    Button("Yazılım Güncelleme…") { openSettings("x-apple.systempreferences:com.apple.Software-Update-Settings.extension") }
                } label: {
                    Label("Sistem Ayarları", systemImage: "gearshape")
                }
                .fixedSize()
                .help("İlgili macOS Sistem Ayarları bölümünü aç")
            }
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            .pocketCard(padding: 0, radius: PocketRadius.medium)
            Label("Araçlar ayar değiştirmez. Paylaşmadan önce raporlardaki yerel adresleri ve yolları incele.", systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(.secondary)
                .help("Bazı sorgular ek macOS erişimi gerektirebilir; eksik erişim ve hata çıktısı rapora olduğu gibi eklenir.")
        }
        .pocketPage()
        .onDisappear { operation?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            PocketSearchField("Araç ara…", text: $search, focus: $searchFocused)
                .accessibilityLabel("macOS aracı ara")
                .padding(PocketSpacing.s)
            Divider()
            List(selection: Binding<MacUtility?>(get: { selected }, set: { value in
                guard let value, !running, value != selected else { return }
                selected = value; report = nil; outputSearch = ""; failure = nil
            })) {
                ForEach(Self.groups, id: \.self) { group in
                    let tools = visible.filter { $0.category == group }
                    if !tools.isEmpty {
                        Section(group) {
                            ForEach(tools) { tool in Label(tool.title, systemImage: tool.symbol).tag(tool) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 34)
            .overlay {
                if visible.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }
        .frame(width: 250)
        .disabled(running)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                    Label(selected.title, systemImage: selected.symbol).font(.title3.weight(.semibold))
                    Text(selected.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PocketSpacing.m)
                if running {
                    Button("İptal Et", role: .cancel) { operation?.cancel() }
                } else {
                    Button(action: run) {
                        Label(report == nil ? "Sorgula" : "Yenile", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.pocketPrimary)
                }
            }
            if let failure { PocketMessage(failure, error: true) }
            if running { PocketProgressRow(message: "Sistem sorgulanıyor…" as LocalizedStringKey) }
            if let report {
                reportHeader(report)
                HStack(spacing: PocketSpacing.s) {
                    PocketSearchField("Çıktıda ara…", text: $outputSearch)
                        .accessibilityLabel("Sorgu çıktısında ara")
                    Button { copy(report) } label: { Label("Kopyala", systemImage: "doc.on.doc") }
                        .help("Sonucu panoya kopyala")
                    Button { export(report) } label: { Label("Dışa Aktar…", systemImage: "square.and.arrow.up") }
                        .help("Sonucu metin dosyası olarak kaydet")
                }
                .controlSize(.small)
                ScrollView([.horizontal, .vertical]) {
                    Text(filtered(report))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(PocketSpacing.m)
                }
                .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous)
                        .strokeBorder(PocketTheme.line.opacity(0.6), lineWidth: 0.5)
                }
            } else if !running {
                ContentUnavailableView("Güncel sonuç henüz alınmadı", systemImage: selected.symbol,
                                       description: Text("Sorgula ile bu Mac’ten salt okunur rapor al."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(PocketSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reportHeader(_ report: DiagnosticReport) -> some View {
        let warning = report.partial || report.exitCode != 0
        return VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            HStack(spacing: PocketSpacing.s) {
                PocketStatusBadge(text: report.partial ? "Kısmi sonuç" : report.exitCode == 0 ? "Sorgu tamamlandı" : "Çıkış kodunu incele",
                                  systemImage: report.partial ? "exclamationmark.circle" : "doc.text",
                                  tone: warning ? .warning : .success)
                Spacer()
                Text(report.capturedAt.formatted(date: .abbreviated, time: .shortened))
                Text("Çıkış: \(exitDescription(report))").monospacedDigit()
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if report.partial {
                Text("8 saniye veya 256 KiB sınırına ulaşıldı; sonuç eksik olabilir.")
                    .font(.subheadline).foregroundStyle(.orange)
            }
        }
    }

    private func copy(_ report: DiagnosticReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportText(report), forType: .string)
    }

    private func run() {
        guard !running else { return }
        let tool = selected
        running = true; report = nil; failure = nil
        operation = Task { @MainActor in
            defer { running = false; operation = nil }
            do { let value = try await MacUtilityService.run(tool); try Task.checkCancellation(); report = value }
            catch is CancellationError { failure = String(localized: "Sorgu iptal edildi.") }
            catch { failure = error.localizedDescription }
        }
    }
    private func filtered(_ report: DiagnosticReport) -> String {
        guard !outputSearch.isEmpty else { return report.output.isEmpty ? String(localized: "Çıktı yok.") : report.output }
        let result = report.output.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.localizedCaseInsensitiveContains(outputSearch) }.joined(separator: "\n")
        return result.isEmpty ? String(localized: "Eşleşen satır yok.") : result
    }
    private func exportText(_ report: DiagnosticReport) -> String {
        let summary = String(localized: "Çıkış: \(exitDescription(report)) · Kısmi: \(String(report.partial))")
        return "\(report.title)\n\(report.capturedAt.formatted())\n\(summary)\n\n\(report.output)"
    }
    private func exitDescription(_ report: DiagnosticReport) -> String {
        report.exitCode.map(String.init) ?? String(localized: "alınamadı")
    }
    private func export(_ report: DiagnosticReport) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "MacPocket-\(report.id).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try exportText(report).write(to: url, atomically: true, encoding: .utf8) }
            catch { failure = error.localizedDescription }
        }
    }
    private func openSettings(_ address: String) {
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else { failure = String(localized: "macOS ayarları açılamadı."); return }
    }
}
