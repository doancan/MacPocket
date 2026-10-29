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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Divider().overlay(DiagnosticColors.border)
            HStack(alignment: .top, spacing: 0) {
                diagnosticList
                Divider().overlay(DiagnosticColors.border)
                detail
            }
        }
        .background(DiagnosticColors.background)
        .foregroundStyle(DiagnosticColors.text)
        .onDisappear { operation?.cancel() }
        .alert("Rapor işlemi tamamlanamadı", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("Tamam", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var heading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sistem Araçları").font(.system(size: 25, weight: .semibold))
                Text("Sistem durumunu incelemek için 8 salt okunur rapor")
                    .font(.system(size: 12)).foregroundStyle(DiagnosticColors.secondary)
            }
            Spacer()
            Label("Salt okunur", systemImage: "eye")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DiagnosticColors.accent)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(DiagnosticColors.accent.opacity(0.1), in: Capsule())
        }
        .padding(24)
    }

    private var diagnosticList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(SystemDiagnostic.allCases, id: \.rawValue) { diagnostic in
                    Button {
                        selected = diagnostic
                        report = nil
                        outputSearch = ""
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: icon(for: diagnostic))
                                .font(.system(size: 15))
                                .frame(width: 20).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(diagnostic.title).font(.system(size: 12, weight: .semibold))
                                Text(shortDescription(for: diagnostic))
                                    .font(.system(size: 10))
                                    .foregroundStyle(DiagnosticColors.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(selected == diagnostic ? DiagnosticColors.accent : DiagnosticColors.text)
                        .background(selected == diagnostic ? DiagnosticColors.accent.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(running)
                }
            }.padding(12)
        }
        .frame(width: 230)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selected.title).font(.system(size: 20, weight: .semibold))
                    Text(description(for: selected))
                        .font(.system(size: 12)).foregroundStyle(DiagnosticColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
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
                    .buttonStyle(.borderedProminent).tint(DiagnosticColors.accent)

                    .disabled(!validProcessID)
                }
            }
            if selected == .openFiles {
                HStack(spacing: 10) {
                    Text("Süreç PID").font(.system(size: 12, weight: .medium))
                    TextField("Boş bırak: kendi kullanıcının süreçleri", text: $processID)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        .disabled(running)
                        .onChange(of: processID) { _, _ in report = nil }
                    if !validProcessID {
                        Text("Pozitif bir PID girin.").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            }
            if running {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(cancelling ? "Tanılama süreci durduruluyor…" : "Güncel sistem raporu alınıyor…")
                        .font(.system(size: 12)).foregroundStyle(DiagnosticColors.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(DiagnosticColors.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            if let report {
                reportSummary(report)
                HStack {
                    Toggle("Ham çıktı", isOn: $showRawOutput).toggleStyle(.checkbox)
                        .font(.system(size: 12))
                    Spacer()
                    Button { copyReport(report) } label: { Label("Kopyala", systemImage: "doc.on.doc") }
                    Button { exportReport(report) } label: { Label("Dışa Aktar", systemImage: "square.and.arrow.up") }
                }
                .buttonStyle(.bordered).controlSize(.small)
                if showRawOutput {
                    TextField("Çıktıda ara…", text: $outputSearch)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    ScrollView([.horizontal, .vertical]) {
                        Text(filteredOutput(report))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(14)
                    }
                    .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DiagnosticColors.border))
                } else {
                    Spacer(minLength: 0)
                }
            } else if !running {
                VStack(spacing: 12) {
                    Image(systemName: icon(for: selected)).font(.system(size: 34, weight: .light))
                        .foregroundStyle(DiagnosticColors.accent.opacity(0.8))
                    Text("Güncel rapor henüz alınmadı").font(.system(size: 15, weight: .medium))
                    Text("Raporu Oluştur ile mevcut sistem durumunu okuyun.")
                        .font(.system(size: 12)).foregroundStyle(DiagnosticColors.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reportSummary(_ report: DiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(statusTitle(report), systemImage: report.partial ? "exclamationmark.circle" : "doc.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(report.partial || report.exitCode != 0 ? Color.orange : DiagnosticColors.accent)
                Spacer()
                Text(report.capturedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 10)).foregroundStyle(DiagnosticColors.secondary)
            }
            HStack(spacing: 24) {
                summaryValue("Kapsam", value: reportScope)
                summaryValue("Çıktı", value: "\(report.output.utf8.count.formatted()) bayt")
                summaryValue("Çıkış kodu", value: report.exitCode.map(String.init) ?? "Alınamadı")
            }
            if report.partial {
                Text(report.truncated
                     ? "Çıktı boyut sınırına ulaştı. Gösterilen kayıt kısmi ve kesilmiştir."
                     : "Tanılama süre sınırına ulaştı. Gösterilen kayıt kısmi olabilir.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            } else if report.exitCode != 0 {
                Text("Komut sıfır dışında bir çıkış kodu döndürdü. Ayrıntılar ham çıktıda bulunur.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .padding(15).background(DiagnosticColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DiagnosticColors.border))
    }

    private func summaryValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DiagnosticColors.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
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
        reportScope = pid.map { "PID \($0)" } ?? (choice == .openFiles ? "Kendi kullanıcım" : "Bu Mac")
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
        case .complete: return report.exitCode == 0 ? "Rapor alındı" : "Komut tamamlanamadı"
        case .outputLimit: return "Kısmi rapor · boyut sınırı"
        case .timedOut: return "Kısmi rapor · süre sınırı"
        }
    }

    private func filteredOutput(_ report: DiagnosticReport) -> String {
        guard !outputSearch.isEmpty else { return report.output.isEmpty ? "Çıktı yok." : report.output }
        let lines = report.output.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(outputSearch) }
        return lines.isEmpty ? "Eşleşen satır yok." : lines.joined(separator: "\n")
    }

    private func reportText(_ report: DiagnosticReport) -> String {
        "MacPocket — \(report.title)\nTarih: \(report.capturedAt.formatted())\nKapsam: \(reportScope)\nDurum: \(statusTitle(report))\nÇıkış kodu: \(report.exitCode.map(String.init) ?? "alınamadı")\n\n\(report.output)"
    }

    private func copyReport(_ report: DiagnosticReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText(report), forType: .string)
    }

    private func exportReport(_ report: DiagnosticReport) {
        let panel = NSSavePanel()
        panel.title = "Sistem raporunu dışa aktar"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "MacPocket-\(report.id).txt"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try reportText(report).write(to: destination, atomically: true, encoding: .utf8) }
        catch { failure = error.localizedDescription }
    }

    private func shortDescription(for diagnostic: SystemDiagnostic) -> String {
        switch diagnostic {
        case .memoryPressure: return "Belleğin güncel baskı durumu"
        case .swap: return "Disk üzerindeki sanal bellek"
        case .powerAssertions: return "Uykuyu engelleyen süreçler"
        case .powerSettings: return "Etkin güç ve uyku tercihleri"
        case .thermal: return "Sistemin bildirdiği termal koşullar"
        case .disks: return "Mount ve alan kullanımı"
        case .network: return "Arayüz sayaçları ve hatalar"
        case .openFiles: return "Süreçlerin açık kaynakları"
        }
    }

    private func description(for diagnostic: SystemDiagnostic) -> String {
        switch diagnostic {
        case .memoryPressure: return "Sistemin bildirdiği bellek baskısını sorgular. Bellek boşaltma işlemi yapmaz."
        case .swap: return "macOS'un disk üzerindeki swap alanı kullanımını gösterir."
        case .powerAssertions: return "Mac'in otomatik uyumasını engelleyen mevcut assertion ve kaynak süreçleri listeler."
        case .powerSettings: return "Bu Mac'in mevcut güç kaynağına ait güç ve uyku ayarlarını okur."
        case .thermal: return "macOS'un sunduğu termal uyarı ve performans sınırı bilgisini okur; sensör sıcaklığı ölçmez."
        case .disks: return "Bağlı dosya sistemleri için kapasite ve kullanılabilir alan raporu alır. APFS volume alanları paylaşılabilir."
        case .network: return "Ağ arayüzlerinin aktarım, paket ve hata sayaçlarını listeler; yeni ağ bağlantısı başlatmaz."
        case .openFiles: return "Seçilen PID'nin veya kendi kullanıcınızın süreçlerinin açık dosya ve bağlantılarını listeler. Erişim ve çıktı sınırları sonucu etkileyebilir."
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

private enum DiagnosticColors {
    static let background = PocketTheme.background
    static let surface = PocketTheme.panel
    static let border = PocketTheme.line
    static let text = Color.primary
    static let secondary = Color.secondary
    static let accent = PocketTheme.accent
}
