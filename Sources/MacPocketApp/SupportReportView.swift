import AppKit
import MacPocketCore
import SwiftUI
import SystemConfiguration
import UniformTypeIdentifiers

/// Tools → Destek Raporu: a Markdown snapshot of this Mac to paste into a support request.
struct SupportReportView: View {
    @ObservedObject var model: PocketModel
    @StateObject private var ports = PortManagerModel()
    @State private var options = SupportReport.Options()
    @State private var text = ""
    @State private var preparing = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Destek Raporu",
                              subtitle: "Mac’in durumunu tek tıkla paylaşılabilir bir rapora dök: donanım, depolama, bellek, ısı, süreçler ve ağa açık portlar.",
                              icon: "doc.text.below.ecg") {
                HStack(spacing: PocketSpacing.s) {
                    Button { Task { await prepare() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                        .disabled(preparing)
                    Button { copy() } label: { Label("Kopyala", systemImage: "doc.on.doc") }
                        .disabled(text.isEmpty)
                    Button { save() } label: { Label("Kaydet…", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.pocketPrimary)
                        .disabled(text.isEmpty)
                }
            }
            HStack(spacing: PocketSpacing.l) {
                Toggle("Kişisel bilgileri gizle", isOn: $options.maskPrivateDetails)
                    .help("Bilgisayar adı, kullanıcı adı, yerel IP adresi ve yollar maskelenir.")
                Toggle("Süreçleri ekle", isOn: $options.includeProcesses)
                Toggle("Ağa açık portları ekle", isOn: $options.includePorts)
                Spacer()
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
            .toggleStyle(.checkbox)
            ScrollView {
                Text(verbatim: text.isEmpty ? String(localized: "Rapor hazırlanıyor…") : text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PocketSpacing.l)
            }
            .pocketCard(padding: 0)
        }
        .pocketPage()
        .task { await prepare() }
        .onChange(of: options) { _, _ in render() }
    }

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        await model.refresh(includeProcesses: true)
        await ports.load()
        render()
    }

    private func render() {
        let processes = model.processes
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(10)
            .map { SupportReport.ProcessLine(name: $0.name, cpuPercent: $0.cpuPercent, memoryBytes: $0.residentBytes) }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let input = SupportReport.Input(
            generatedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            osVersion: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            computerName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "",
            userName: NSUserName(),
            snapshot: model.system,
            processes: Array(processes),
            ports: ports.owners,
            attention: MenuBarAttention.reasons(model.system, diskFreeThreshold: ResourceAlertSettings.load(from: .standard).diskFreePercent))
        text = SupportReport.markdown(input, options: options) { pocketBytes($0) }
        status = nil
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = String(localized: "Panoya kopyalandı.")
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "MacPocket-rapor-\(Date().formatted(.iso8601.year().month().day())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            status = String(localized: "Kaydedildi.")
        } catch {
            status = error.localizedDescription
        }
    }
}
