import AppKit
import MacPocketAIUsage
import SwiftUI

struct ClaudeProfileSelector: View {
    @Binding var directory: String
    let accounts: [AIUsageAccount]
    let home: URL
    @State private var folders: [ClaudeProfileFolder] = []
    @State private var searching = true
    @State private var incomplete = false
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude klasörü").font(.callout.weight(.semibold))
                Spacer()
                Button("Claude Klasörlerini Bul", systemImage: "folder.badge.magnifyingglass") { revision += 1 }
                    .disabled(searching)
            }
            if searching {
                HStack { ProgressView().controlSize(.small); Text("Claude klasörleri aranıyor…").font(.caption).foregroundStyle(.secondary) }
            }
            ScrollView {
                VStack(spacing: 4) {
                    folderRow(home.appending(path: ".claude"), title: String(localized: "Varsayılan Claude Code oturumu"), isDefault: true)
                    ForEach(folders.filter { !$0.isDefault }) { folder in
                        folderRow(folder.directory, title: folder.name)
                    }
                }
            }
            .frame(height: min(180, CGFloat(max(1, folders.filter { !$0.isDefault }.count + 1)) * 52))
            if !searching && folders.isEmpty {
                Text("Ek profil klasörü bulunamadı. Varsayılan oturumu kullanabilir veya klasörü kendin seçebilirsin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if incomplete {
                Text("Bazı klasörler taranamadı. Aradığın profil görünmüyorsa Klasör Seç’i kullan.")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("Klasör yolu (ör. ~/.claude-work)", text: $directory)
                .textFieldStyle(.roundedBorder).font(.callout.monospaced())
            HStack {
                Text("Gizli klasörler de gösterilir.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Klasör Seç…", systemImage: "folder") { chooseFolder() }
            }
            Text("Arama; ana klasördeki .claude profillerini, CLAUDE_CONFIG_DIR ve MacPocket profil klasörlerini kontrol eder.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .task(id: revision) { await search() }
    }

    private func folderRow(_ url: URL, title: String, isDefault: Bool = false) -> some View {
        let selected = directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? isDefault
            : ClaudeProfileDiscovery.folderURL(directory, home: home)?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
        return Button { directory = isDefault ? "" : url.path } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "folder")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(displayPath(url)).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func displayPath(_ url: URL) -> String {
        url.path.hasPrefix(home.path + "/") ? "~" + url.path.dropFirst(home.path.count) : url.path
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.title = String(localized: "Claude Profil Klasörünü Seç")
        panel.prompt = String(localized: "Bu Profili Seç")
        let selected = ClaudeProfileDiscovery.folderURL(directory, home: home) ?? home.appending(path: ".claude")
        panel.directoryURL = FileManager.default.fileExists(atPath: selected.path) ? selected : home
        if panel.runModal() == .OK, let url = panel.url { directory = url.path }
    }
    private func search() async {
        searching = true
        let accounts = accounts, home = home
        let environment: [String: String]
        #if DEBUG
        environment = AIUsageFixtures.requested ? [:] : ProcessInfo.processInfo.environment
        #else
        environment = ProcessInfo.processInfo.environment
        #endif
        let work = Task.detached(priority: .userInitiated) { ClaudeProfileDiscovery.find(home: home, environment: environment, accounts: accounts) }
        let result = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        guard !Task.isCancelled else { return }
        folders = result.folders; incomplete = result.incomplete; searching = false
    }
}
