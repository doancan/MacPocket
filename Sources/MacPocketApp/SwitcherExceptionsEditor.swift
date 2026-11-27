import AppKit
import MacPocketCore
import SwiftUI

/// One editor for legacy exact-match exclusions and conditional rules. Drafts are committed
/// explicitly, so Cancel never changes a working VM/remote-desktop shortcut exception.
struct SwitcherExceptionsEditor: View {
    let defaults: UserDefaults
    @State private var rules: [SwitcherExceptionRule]
    @State private var loadError: String?
    @State private var editing: SwitcherExceptionRule?
    @State private var confirmsReset = false
    @State private var saveError = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = SwitcherExceptionStore.load(defaults)
        _rules = State(initialValue: loaded.rules)
        _loadError = State(initialValue: loaded.error)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Okunamayan kural kaydını sıfırla…") { confirmsReset = true }
            }
            if saveError { Text("İstisna kaydedilemedi. Kural sayısını ve uygulama hedefini kontrol et.").foregroundStyle(.red) }
            if rules.isEmpty {
                Text("Henüz istisna yok. Bir uygulamanın pencerelerini gizleyebilir veya öndeyken kısayolları ona bırakabilirsin.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rules) { rule in
                HStack(alignment: .top, spacing: PocketSpacing.s) {
                    Toggle("Kural etkin", isOn: Binding(get: { rule.enabled }, set: { value in
                        var edited = rules
                        if let index = edited.firstIndex(where: { $0.id == rule.id }) { edited[index].enabled = value; persist(edited) }
                    })).labelsHidden().toggleStyle(.checkbox)
                        .accessibilityLabel("\(rule.value) kuralı etkin")
                    VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                        Text(verbatim: rule.value).font(.subheadline.weight(.medium)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(rule.target.localizedTitle).font(.caption).foregroundStyle(.secondary)
                        Text(rule.visibility.localizedTitle).font(.caption)
                        if rule.visibility == .titleContains {
                            Text(verbatim: rule.titlePatterns.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(rule.shortcuts.localizedTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Düzenle") { editing = rule }.buttonStyle(.borderless)
                        .accessibilityLabel("\(rule.value) kuralını düzenle")
                    Button { persist(rules.filter { $0.id != rule.id }) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Listeden çıkar")
                        .accessibilityLabel("\(rule.value) kuralını kaldır")
                }
                .disabled(loadError != nil)
            }
            HStack {
                Button { editing = .init(target: .bundleIdentifier, value: "", visibility: .alwaysHide) } label: {
                    Label("İstisna Ekle", systemImage: "plus")
                }.disabled(loadError != nil || rules.count >= SwitcherExceptionStore.maximumCount)
                Spacer()
                Text("\(rules.count) / \(SwitcherExceptionStore.maximumCount)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { draft in
            SwitcherExceptionRuleForm(rule: draft) { edited in
                var updated = rules
                if let index = updated.firstIndex(where: { $0.id == edited.id }) { updated[index] = edited }
                else { updated.append(edited) }
                return persist(updated)
            }
        }
        .confirmationDialog("Okunamayan kurallar sıfırlansın mı?", isPresented: $confirmsReset) {
            Button("Kuralları Sıfırla", role: .destructive) { persist(rules) }
        } message: { Text("Okunamayan kayıt kaldırılır. Önceki basit istisnalar korunur.") }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let loaded = SwitcherExceptionStore.load(defaults)
            rules = loaded.rules
            loadError = loaded.error
        }
    }
    @discardableResult private func persist(_ updated: [SwitcherExceptionRule]) -> Bool {
        guard SwitcherExceptionStore.save(updated, defaults) else { saveError = true; return false }
        rules = updated
        loadError = nil
        saveError = false
        return true
    }
}

struct SwitcherExceptionRuleForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: SwitcherExceptionRule
    @State private var patterns: String
    @State private var submitted = false
    @State private var saveFailed = false
    let save: (SwitcherExceptionRule) -> Bool
    init(rule: SwitcherExceptionRule, save: @escaping (SwitcherExceptionRule) -> Bool) {
        _rule = State(initialValue: rule)
        _patterns = State(initialValue: rule.titlePatterns.joined(separator: "\n"))
        self.save = save
    }
    private var candidate: SwitcherExceptionRule {
        var value = rule
        value.value = value.value.trimmingCharacters(in: .whitespacesAndNewlines)
        value.titlePatterns = patterns.split(whereSeparator: \.isNewline).map(String.init)
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Text("Pencere geçişi istisnası").font(.title2.weight(.semibold))
            Form {
                Picker("Uygulama eşleştirmesi", selection: $rule.target) {
                    ForEach(SwitcherExceptionTarget.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
                }
                    .pocketMenuPicker()
                TextField("Uygulama hedefi", text: $rule.value).textFieldStyle(.bordered).textInputBorderShape(.roundedRectangle)
                    .accessibilityIdentifier("switcher-exception-target")
                Menu("Uygulamadan Doldur") {
                    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                    ForEach(apps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? String(localized: "Uygulama")) { fill(app.bundleURL) }
                    }
                    Divider()
                    Button("Uygulama Seç…") { choose() }
                }
                if rule.target == .bundlePrefix {
                    Text("Bu önekle başlayan bütün bundle kimlikleri eşleşir. Örneğin com.example. bir uygulama ailesini kapsar.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Picker("Pencere görünürlüğü", selection: $rule.visibility) {
                    ForEach(SwitcherExceptionVisibility.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
                }
                    .pocketMenuPicker()
                if rule.visibility == .titleContains {
                    VStack(alignment: .leading, spacing: PocketSpacing.s) {
                        Text("Başlık metinleri (satır başına bir tane)").font(.subheadline)
                        TextEditor(text: $patterns).frame(minHeight: 70, maxHeight: 110)
                            .accessibilityLabel("Başlık metinleri (satır başına bir tane)")
                            .accessibilityIdentifier("switcher-exception-patterns")
                        Text("Metinler büyük/küçük harfe duyarlıdır; herhangi biri başlıkta geçerse pencere gizlenir. Düzenli ifade kullanılmaz.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Picker("Global kısayollar", selection: $rule.shortcuts) {
                    ForEach(SwitcherExceptionShortcuts.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
                }
                    .pocketMenuPicker()
                if rule.shortcuts == .fullscreen {
                    Text("Yalnız öndeki pencerenin gerçek tam ekran durumu kullanılır. Erişilebilirlik izni yoksa veya durum okunamazsa kısayollar etkin kalır.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Kural etkin", isOn: $rule.enabled)
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
            if submitted, let message = candidate.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if saveFailed {
                Text("İstisna kaydedilemedi. Kural sayısını ve uygulama hedefini kontrol et.").foregroundStyle(.red)
            }
            HStack {
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("İstisnayı Kaydet") {
                    submitted = true
                    saveFailed = false
                    guard candidate.validationMessage == nil else { return }
                    if save(candidate) { dismiss() } else { saveFailed = true }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(PocketSpacing.l).background(Color(nsColor: .windowBackgroundColor)).frame(minWidth: 520, idealWidth: 580, maxWidth: 700, minHeight: 600, idealHeight: 700, maxHeight: 900)
    }
    private func fill(_ url: URL?) {
        guard let url else { return }
        if rule.target == .applicationPath { rule.value = url.path }
        else if let id = Bundle(url: url)?.bundleIdentifier { rule.value = id }
    }
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Seç")
        if panel.runModal() == .OK { fill(panel.url) }
    }
}
