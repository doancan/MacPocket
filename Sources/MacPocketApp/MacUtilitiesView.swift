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
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PocketPageHeading(title: "macOS Araçları", subtitle: "Disk, ağ, oturum ve güvenlik için gerçek sistem sorguları.", icon: "wrench.and.screwdriver")
            HStack {
                TextField("Araç ara…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300).focused($searchFocused)
                Spacer()
                Button("Gizlilik ve Güvenlik…") { openSettings("x-apple.systempreferences:com.apple.preference.security") }
                Button("Yazılım Güncelleme…") { openSettings("x-apple.systempreferences:com.apple.Software-Update-Settings.extension") }
            }
            HStack(spacing: 0) {
                List(selection: Binding<MacUtility?>(get: { selected }, set: { value in
                    guard let value, !running else { return }; selected = value; report = nil; outputSearch = ""; failure = nil
                })) {
                    ForEach(["Disk ve Arama", "Ağ", "Sistem", "Güvenlik"], id: \.self) { group in
                        let tools = visible.filter { $0.category == group }
                        if !tools.isEmpty {
                            Section(group) { ForEach(tools) { tool in Label(tool.title, systemImage: tool.symbol).tag(tool) } }
                        }
                    }
                }.listStyle(.sidebar).frame(width: 240).disabled(running)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(selected.title, systemImage: selected.symbol).font(.title3.weight(.semibold))
                        Spacer()
                        if running { Button("İptal Et") { operation?.cancel() } }
                        else { Button(report == nil ? "Sorgula" : "Yenile", action: run).buttonStyle(.borderedProminent) }
                    }
                    Text(selected.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let failure { PocketMessage(failure, error: true) }
                    if running { HStack { ProgressView().controlSize(.small); Text("Sistem sorgulanıyor…").font(.callout) } }
                    if let report {
                        HStack {
                            Label(report.partial ? "Kısmi sonuç" : report.exitCode == 0 ? "Sorgu tamamlandı" : "Çıkış kodunu incele", systemImage: report.partial ? "exclamationmark.circle" : "doc.text")
                                .foregroundStyle(report.partial || report.exitCode != 0 ? Color.orange : Color.secondary)
                            Spacer()
                            Text(report.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            Text("Çıkış: \(report.exitCode.map(String.init) ?? "alınamadı")")
                        }.font(.caption)
                        if report.partial { Text("8 saniye veya 256 KiB sınırına ulaşıldı; sonuç eksik olabilir.").font(.caption).foregroundStyle(.orange) }
                        HStack {
                            TextField("Çıktıda ara…", text: $outputSearch).textFieldStyle(.roundedBorder)
                            Button("Kopyala") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(exportText(report), forType: .string) }
                            Button("Dışa Aktar…") { export(report) }
                        }.controlSize(.small)
                        ScrollView([.horizontal, .vertical]) {
                            Text(filtered(report)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
                        }.background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    } else if !running {
                        ContentUnavailableView("Güncel sonuç henüz alınmadı", systemImage: selected.symbol,
                                               description: Text("Sorgula ile bu Mac’ten salt okunur rapor al."))
                    } else { Spacer(minLength: 0) }
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            Text("Araçlar ayar değiştirmez. Bazı sorgular ek macOS erişimi gerektirebilir; eksik erişim ve hata çıktısı saklanır. Paylaşmadan önce raporlardaki yerel adresleri ve yolları incele.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { operation?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
    }
    private func run() {
        guard !running else { return }
        let tool = selected
        running = true; report = nil; failure = nil
        operation = Task { @MainActor in
            defer { running = false; operation = nil }
            do { let value = try await MacUtilityService.run(tool); try Task.checkCancellation(); report = value }
            catch is CancellationError { failure = "Sorgu iptal edildi." }
            catch { failure = error.localizedDescription }
        }
    }
    private func filtered(_ report: DiagnosticReport) -> String {
        guard !outputSearch.isEmpty else { return report.output.isEmpty ? "Çıktı yok." : report.output }
        let result = report.output.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.localizedCaseInsensitiveContains(outputSearch) }.joined(separator: "\n")
        return result.isEmpty ? "Eşleşen satır yok." : result
    }
    private func exportText(_ report: DiagnosticReport) -> String {
        "\(report.title)\n\(report.capturedAt.formatted())\nÇıkış: \(report.exitCode.map(String.init) ?? "alınamadı") · Kısmi: \(report.partial)\n\n\(report.output)"
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
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else { failure = "macOS ayarları açılamadı."; return }
    }
}
