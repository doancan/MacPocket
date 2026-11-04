import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SystemToolsView: View {
    @State private var selected: SystemDiagnostic = .memoryPressure
    @State private var report: DiagnosticReport?
    @State private var reportScope = ""
    @State private var processID = ""
    @State private var outputSearch = ""
    @State private var showRawOutput = true
    @State private var running = false
    @State private var cancelling = false
    @State private var failure: String?
    @State private var operation: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Sistem Raporları",
                              subtitle: "Sistem durumunu incelemek için \(SystemDiagnostic.allCases.count) salt okunur rapor.",
                              icon: "terminal") {
                PocketStatusBadge(text: "Salt okunur", systemImage: "eye", tone: .accent)
                    .help("Raporlar yalnızca okur; sistemde ayar değiştirmez veya bellek boşaltmaz.")
            }
            HStack(spacing: 0) {
                diagnosticList
                Divider()
                detail
            }
            .pocketCard(padding: 0, radius: PocketRadius.medium)
        }
        .pocketPage()
        .onDisappear { operation?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in
            if report != nil { showRawOutput = true; searchFocused = true }
        }
        .alert("Rapor işlemi tamamlanamadı", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("Tamam", role: .cancel) { failure = nil }
        } message: {
            Text(verbatim: failure ?? "")
        }
    }

    private var diagnosticList: some View {
        List(selection: Binding<SystemDiagnostic?>(get: { selected }, set: { value in
            guard let value, !running, value != selected else { return }
            selected = value
            report = nil
            outputSearch = ""
        })) {
            Section("Raporlar") {
                ForEach(SystemDiagnostic.allCases, id: \.self) { diagnostic in
                    Label {
                        VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                            Text(diagnostic.title)
                            Text(shortDescription(for: diagnostic))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: icon(for: diagnostic))
                    }
                    .padding(.vertical, PocketSpacing.xxs)
                    .tag(diagnostic)
                }
            }
        }
        .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 34)
        .frame(width: 250)
        .disabled(running)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                    Label(selected.title, systemImage: icon(for: selected))
                        .font(.title3.weight(.semibold))
                    Text(description(for: selected))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PocketSpacing.m)
                if running {
                    Button(cancelling ? "İptal ediliyor…" : "İptal Et", role: .cancel) {
                        cancelling = true
                        operation?.cancel()
                    }
                    .disabled(cancelling)
                } else {
                    Button(action: runDiagnostic) {
                        Label(report == nil ? "Raporu Oluştur" : "Raporu Yenile",
                              systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.pocketPrimary)
                    .disabled(!validProcessID)
                }
            }
            if selected == .openFiles {
                HStack(spacing: PocketSpacing.s) {
                    Text("Süreç PID").font(.callout.weight(.medium))
                    TextField("Boş bırak: kendi kullanıcının süreçleri", text: $processID)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        .disabled(running)
                        .onChange(of: processID) { _, _ in report = nil }
                    if !validProcessID {
                        Label("Pozitif bir PID gir.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
            }
            if running {
                PocketProgressRow(message: cancelling ? "Tanılama süreci durduruluyor…" : "Güncel sistem raporu alınıyor…")
            }
            if let report {
                reportSummary(report)
                HStack(spacing: PocketSpacing.s) {
                    Toggle("Ham çıktı", isOn: $showRawOutput).toggleStyle(.checkbox)
                    if showRawOutput {
                        PocketSearchField("Çıktıda ara…", text: $outputSearch, focus: $searchFocused)
                            .frame(maxWidth: 280)
                            .accessibilityLabel("Rapor çıktısında ara")
                    }
                    Spacer()
                    Button { copyReport(report) } label: { Label("Kopyala", systemImage: "doc.on.doc") }
                        .help("Raporu panoya kopyala")
                    Button { exportReport(report) } label: { Label("Dışa Aktar…", systemImage: "square.and.arrow.up") }
                        .help("Raporu metin dosyası olarak kaydet")
                }
                .controlSize(.small)
                if showRawOutput {
                    ScrollView([.horizontal, .vertical]) {
                        Text(filteredOutput(report))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(PocketSpacing.m)
                    }
                    .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous)
                            .strokeBorder(PocketTheme.line.opacity(0.6), lineWidth: 0.5)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            } else if !running {
                ContentUnavailableView("Güncel rapor henüz alınmadı", systemImage: icon(for: selected),
                                       description: Text("Raporu Oluştur ile mevcut sistem durumunu oku."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(PocketSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reportSummary(_ report: DiagnosticReport) -> some View {
        let warning = report.partial || report.exitCode != 0
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack {
                Label(statusTitle(report), systemImage: report.partial ? "exclamationmark.circle" : "doc.text")
                    .font(.headline)
                    .foregroundStyle(warning ? Color.orange : PocketTheme.accent)
                Spacer()
                Text(report.capturedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: PocketSpacing.xl) {
                summaryValue("Kapsam", value: reportScope)
                summaryValue("Çıktı", value: String(localized: "\(report.output.utf8.count.formatted()) bayt"))
                summaryValue("Çıkış kodu", value: report.exitCode.map(String.init) ?? String(localized: "Alınamadı"))
            }
            if report.partial {
                Text(report.truncated
                     ? "Çıktı boyut sınırına ulaştı. Gösterilen kayıt kısmi ve kesilmiştir."
                     : "Tanılama süre sınırına ulaştı. Gösterilen kayıt kısmi olabilir.")
                    .font(.callout).foregroundStyle(.orange)
            } else if report.exitCode != 0 {
                Text("Komut sıfır dışında bir çıkış kodu döndürdü. Ayrıntılar ham çıktıda bulunur.")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
    }

    private func summaryValue(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit().textSelection(.enabled)
        }
    }

    private var validProcessID: Bool {
        selected != .openFiles || processID.trimmingCharacters(in: .whitespaces).isEmpty
            || (Int32(processID.trimmingCharacters(in: .whitespaces)).map { $0 > 0 } ?? false)
    }

    private func runDiagnostic() {
        guard !running, validProcessID else { return }
        let choice = selected
        let pid = choice == .openFiles ? Int32(processID.trimmingCharacters(in: .whitespaces)) : nil
        reportScope = pid.map { "PID \($0)" } ?? (choice == .openFiles ? String(localized: "Kendi kullanıcım") : String(localized: "Bu Mac"))
        running = true
        cancelling = false
        report = nil
        operation = Task { @MainActor in
            defer {
                running = false
                cancelling = false
                operation = nil
            }
            do {
                let result = try await SystemDiagnostics.run(choice, processID: pid)
                try Task.checkCancellation()
                report = result
            } catch is CancellationError {
                // The core cancels only the diagnostic process it owns.
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func statusTitle(_ report: DiagnosticReport) -> String {
        switch report.completion {
        case .complete: return report.exitCode == 0 ? String(localized: "Rapor alındı") : String(localized: "Komut tamamlanamadı")
        case .outputLimit: return String(localized: "Kısmi rapor · boyut sınırı")
        case .timedOut: return String(localized: "Kısmi rapor · süre sınırı")
        }
    }

    private func filteredOutput(_ report: DiagnosticReport) -> String {
        guard !outputSearch.isEmpty else { return report.output.isEmpty ? String(localized: "Çıktı yok.") : report.output }
        let lines = report.output.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(outputSearch) }
        return lines.isEmpty ? String(localized: "Eşleşen satır yok.") : lines.joined(separator: "\n")
    }

    private func reportText(_ report: DiagnosticReport) -> String {
        let exitCode = report.exitCode.map(String.init) ?? String(localized: "alınamadı")
        let date = report.capturedAt.formatted()
        let header = String(localized: "MacPocket — \(report.title)\nTarih: \(date)\nKapsam: \(reportScope)\nDurum: \(statusTitle(report))\nÇıkış kodu: \(exitCode)")
        return header + "\n\n" + report.output
    }

    private func copyReport(_ report: DiagnosticReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText(report), forType: .string)
    }

    private func exportReport(_ report: DiagnosticReport) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Sistem raporunu dışa aktar")
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "MacPocket-\(report.id).txt"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try reportText(report).write(to: destination, atomically: true, encoding: .utf8) }
        catch { failure = error.localizedDescription }
    }

    private func shortDescription(for diagnostic: SystemDiagnostic) -> String {
        switch diagnostic {
        case .memoryPressure: return String(localized: "Belleğin güncel baskı durumu")
        case .swap: return String(localized: "Disk üzerindeki sanal bellek")
        case .powerAssertions: return String(localized: "Uykuyu engelleyen süreçler")
        case .powerSettings: return String(localized: "Etkin güç ve uyku tercihleri")
        case .thermal: return String(localized: "Sistemin bildirdiği termal koşullar")
        case .disks: return String(localized: "Mount ve alan kullanımı")
        case .network: return String(localized: "Arayüz sayaçları ve hatalar")
        case .openFiles: return String(localized: "Süreçlerin açık kaynakları")
        }
    }

    private func description(for diagnostic: SystemDiagnostic) -> String {
        switch diagnostic {
        case .memoryPressure: return String(localized: "Sistemin bildirdiği bellek baskısını sorgular. Bellek boşaltma işlemi yapmaz.")
        case .swap: return String(localized: "macOS'un disk üzerindeki swap alanı kullanımını gösterir.")
        case .powerAssertions: return String(localized: "Mac'in otomatik uyumasını engelleyen mevcut assertion ve kaynak süreçleri listeler.")
        case .powerSettings: return String(localized: "Bu Mac'in mevcut güç kaynağına ait güç ve uyku ayarlarını okur.")
        case .thermal: return String(localized: "macOS'un sunduğu termal uyarı ve performans sınırı bilgisini okur; sensör sıcaklığı ölçmez.")
        case .disks: return String(localized: "Bağlı dosya sistemleri için kapasite ve kullanılabilir alan raporu alır. APFS volume alanları paylaşılabilir.")
        case .network: return String(localized: "Ağ arayüzlerinin aktarım, paket ve hata sayaçlarını listeler; yeni ağ bağlantısı başlatmaz.")
        case .openFiles: return String(localized: "Seçilen PID'nin veya kendi kullanıcınızın süreçlerinin açık dosya ve bağlantılarını listeler. Erişim ve çıktı sınırları sonucu etkileyebilir.")
        }
    }

    private func icon(for diagnostic: SystemDiagnostic) -> String {
        switch diagnostic {
        case .memoryPressure: return "memorychip"
        case .swap: return "arrow.left.arrow.right.square"
        case .powerAssertions: return "moon.zzz"
        case .powerSettings: return "powerplug"
        case .thermal: return "thermometer.medium"
        case .disks: return "internaldrive"
        case .network: return "network"
        case .openFiles: return "doc.text.magnifyingglass"
        }
    }
}
