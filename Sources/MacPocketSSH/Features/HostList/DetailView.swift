import SSHConfigKit
import SwiftUI

struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let item = model.selection {
            content(for: item)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(for item: SidebarItem) -> some View {
        switch item {
        case .host:
            VStack(spacing: 0) {
                ConnectionBar(model: model, alias: model.connectableAlias(for: item), showsSaveHint: model.isUnsavedHost(item))
                EffectiveSettingsView(model: model, alias: model.connectableAlias(for: item), isUnsaved: model.isUnsavedHost(item))
                Divider()
                HostEditorContainer(model: model)
                    .id(model.editorToken)
            }
        case .included:
            if let host = SidebarBuilder.includedHost(for: item, in: model.store.includedHosts) {
                VStack(spacing: 0) {
                    ConnectionBar(model: model, alias: model.connectableAlias(for: item))
                    EffectiveSettingsView(model: model, alias: model.connectableAlias(for: item), isUnsaved: false)
                    Divider()
                    IncludedHostView(host: host, displayPath: model.settings.displayPath(for: host.file))
                }
            } else {
                empty
            }
        case .match:
            if let match = SidebarBuilder.matchEntry(for: item, in: model.store.document) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "SSH.match.readOnly", defaultValue: "Match blokları salt okunur gösterilir."), systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .padding([.top, .horizontal])
                    CodeTextView(lines: match.text.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { ConfigLine(raw: String($0)) })
                }
            } else {
                empty
            }
        }
    }

    private var showsOnboarding: Bool {
        model.store.loadState == .loaded && model.store.document.hosts.allSatisfy(\.isPattern) && model.store.includedHosts.isEmpty
    }

    @ViewBuilder
    private var empty: some View {
        if model.selection == nil && showsOnboarding {
            OnboardingView(model: model)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            String(localized: "SSH.detail.empty.title", defaultValue: "Host Seçilmedi"),
            systemImage: "server.rack",
            description: Text(String(localized: "SSH.detail.empty.message", defaultValue: "Listeden bir host seçin ya da yeni bir host ekleyin.")))
    }
}

/// Owns the editor model for the current selection; rebuilt only when `editorToken` changes.
private struct HostEditorContainer: View {
    @Bindable var model: AppModel
    @State private var editor: HostEditorModel?

    var body: some View {
        Group {
            if let editor {
                VStack(spacing: 0) {
                    if let entry = SidebarBuilder.hostEntry(for: editor.item, in: model.store.document) {
                        // Patterns have no group; they get the IdentityFile checks only.
                        if !entry.isPattern { HostGroupRow(model: model, item: editor.item) }
                        LintIssuesList(issues: model.lintIssues(for: editor.item).filter(\.isHostWarning),
                                       fixPermissions: { model.restrictKeyPermissions($0) })
                        Divider()
                    }
                    HostEditorView(editor: editor, homeDirectory: model.settings.homeDirectory, keys: model.keys,
                                   unencryptedKeys: model.unencryptedIdentityFiles(for: editor.item)) { model.resetEditor() }
                }
            } else {
                ContentUnavailableView(String(localized: "SSH.edit.hostNotFound", defaultValue: "Bu host artık dosyada yok."), systemImage: "questionmark")
            }
        }
        .onAppear {
            if editor == nil, let item = model.selection {
                editor = model.editor(for: item)
            }
        }
    }
}

private struct HostGroupRow: View {
    let model: AppModel
    let item: SidebarItem

    var body: some View {
        let saved = model.savedGroup(for: item)
        let text = Binding(get: { model.groupDraft ?? saved }, set: { model.groupDraft = $0 })
        HStack {
            TextField(String(localized: "SSH.editor.group", defaultValue: "Grup"), text: text,
                      prompt: Text(String(localized: "SSH.editor.group.placeholder", defaultValue: "Grup yok")))
                .onSubmit(apply)
            let groups = model.existingGroups
            if !groups.isEmpty {
                Menu(String(localized: "SSH.editor.group.suggestions", defaultValue: "Mevcut Gruplar")) {
                    ForEach(groups, id: \.self) { name in
                        Button {
                            model.groupDraft = name
                            apply()
                        } label: { Text(verbatim: name) }
                    }
                }
                .fixedSize()
            }
            Button(String(localized: "SSH.editor.group.apply", defaultValue: "Uygula"), action: apply)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) == saved)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func apply() {
        // Leave the document alone when nothing changed (Return must not rewrite or dirty it).
        let saved = model.savedGroup(for: item)
        guard let draft = model.groupDraft, draft.trimmingCharacters(in: .whitespacesAndNewlines) != saved else {
            model.groupDraft = nil
            return
        }
        model.setGroup(item, to: draft)
    }
}

private struct LintIssuesList: View {
    let issues: [HostIssue]
    let fixPermissions: (String) -> Void

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(Messages.text(for: issue), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        Spacer(minLength: 8)
                        if case .keyPermissionsTooOpen(let path) = issue {
                            Button(String(localized: "SSH.issue.fixPermissions", defaultValue: "İzni Düzelt")) { fixPermissions(path) }
                                .controlSize(.small)
                                .fixedSize()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

private struct IncludedHostView: View {
    let host: IncludedHost
    let displayPath: String

    var body: some View {
        Form {
            Section {
                Label(String(localized: "SSH.included.readOnly %@", defaultValue: "\(displayPath) dosyasında tanımlı — salt okunur."), systemImage: "lock")
                    .foregroundStyle(.secondary)
                LabeledContent(String(localized: "SSH.editor.alias", defaultValue: "Alias")) { Text(verbatim: host.entry.patterns.joined(separator: " ")) }
                ForEach(Array(host.entry.directives.enumerated()), id: \.offset) { _, directive in
                    LabeledContent(directive.key) { Text(verbatim: directive.value).textSelection(.enabled) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
