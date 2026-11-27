import AppKit
import SSHConfigKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        let sections = SidebarBuilder.sections(
            document: model.store.document, included: model.store.includedHosts, search: model.searchText)
        // One lint pass per render, not one per row. Key hints stay on the editor's IdentityFile rows.
        let lint = model.lintIssueMap().mapValues { $0.filter(\.isHostWarning) }
        let onlyUnnamed = sections.hostGroups.allSatisfy { $0.name == nil }
        let filterName = model.statusFilter?.localizedName
        List(selection: Binding(get: { model.selection }, set: { new in
            guard let new, new != model.selection else { return }
            model.requestSelect(new)
        })) {
            if let filterName {
                HStack {
                    Text(String(localized: "SSH.status.filter %@", defaultValue: "Gösterilen: \(filterName)")).font(.callout)
                    Spacer()
                    Button(String(localized: "SSH.status.filter.clear", defaultValue: "Tümünü Göster")) { model.statusFilter = nil }
                        .buttonStyle(.link)
                        .fixedSize()
                }
            }
            ForEach(sections.hostGroups) { group in
                section(groupTitle(group, onlyUnnamed: onlyUnnamed), rows: group.rows, icon: "server.rack", editable: true, lint: lint)
            }
            section(String(localized: "SSH.sidebar.section.patterns", defaultValue: "Desenler"), rows: sections.patterns, icon: "asterisk", editable: true, lint: lint)
            section(String(localized: "SSH.sidebar.section.included", defaultValue: "Dahil Edilen"), rows: sections.included, icon: "lock", editable: false, lint: [:])
            section(String(localized: "SSH.sidebar.section.match", defaultValue: "Match"), rows: sections.matches, icon: "lock", editable: false, lint: [:])
        }
        .onDeleteCommand {
            if let item = model.selection { model.requestDelete(item) }
        }
    }

    private func groupTitle(_ group: SidebarGroup, onlyUnnamed: Bool) -> String {
        if let name = group.name { return name }
        return onlyUnnamed ? String(localized: "SSH.sidebar.section.hosts", defaultValue: "Hostlar") : String(localized: "SSH.sidebar.section.ungrouped", defaultValue: "Diğer Hostlar")
    }

    @ViewBuilder
    private func section(_ title: String, rows: [SidebarRow], icon: String, editable: Bool,
                         lint: [SidebarItem: [HostIssue]]) -> some View {
        let rows = rows.filter { model.passesStatusFilter($0.item) }
        if !rows.isEmpty {
            // Group names are user text; section titles of fixed sections are already localized strings.
            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label(row.title, systemImage: icon)
                            Spacer()
                            if let issues = lint[row.item], !issues.isEmpty {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(issues.map(Messages.text(for:)).joined(separator: "\n"))
                                    .accessibilityLabel(issues.map(Messages.text(for:)).joined(separator: ". "))
                            }
                            if let alias = model.connectableAlias(for: row.item) {
                                if model.memory.isFavorite(alias) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                        .accessibilityLabel(String(localized: "SSH.quick.favorite.accessibility", defaultValue: "Favori"))
                                }
                                ConnectionStatusBadge(model: model.connectionTests, alias: alias, showsTitle: false)
                            }
                        }
                        if !row.subtitle.isEmpty {
                            Text(verbatim: row.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 24)
                        }
                    }
                    .tag(row.item)
                    .contextMenu {
                        if model.connectableAlias(for: row.item) != nil {
                            connectItems(for: row.item)
                            if editable { Divider() }
                        }
                        if editable {
                            menu(for: row.item)
                        }
                    }
                }
            } header: {
                Text(verbatim: title)
            }
        }
    }

    @ViewBuilder
    private func connectItems(for item: SidebarItem) -> some View {
        if let alias = model.connectableAlias(for: item) {
            Button(String(localized: "SSH.action.connect", defaultValue: "Bağlan")) { Task { await model.connect(alias: alias) } }
            Button(model.memory.isFavorite(alias) ? String(localized: "SSH.favorite.remove", defaultValue: "Favorilerden Çıkar") : String(localized: "SSH.favorite.add", defaultValue: "Favorilere Ekle")) {
                model.toggleFavorite(alias)
            }
            Button(String(localized: "SSH.action.test", defaultValue: "Test Et")) {
                Task { await model.test(alias: alias) }
            }
            Button(String(localized: "SSH.action.removeKnownHost", defaultValue: "known_hosts Kaydını Sil…")) {
                model.startHostKeyRemoval(alias: alias)
            }
        }
    }

    @ViewBuilder
    private func menu(for item: SidebarItem) -> some View {
        Button(String(localized: "SSH.action.duplicate", defaultValue: "Çoğalt")) {
            model.duplicateHost(item)
        }
        if HostCommands.sshCommand(for: item, document: model.store.document, builder: model.commandBuilder) != nil {
            Button(String(localized: "SSH.action.copySSHCommand", defaultValue: "SSH Komutunu Kopyala")) {
                model.copySSHCommand(item) { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
        Divider()
        Button(String(localized: "SSH.action.delete", defaultValue: "Sil"), role: .destructive) { model.requestDelete(item) }
    }
}
