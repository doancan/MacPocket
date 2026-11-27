import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

struct MouseButtonsView: View {
    @ObservedObject private var service: MouseButtonService
    @State private var application: String?
    @State private var extra = MouseButtonInput(rawValue: 5)!
    init(service: MouseButtonService = .shared, initialApplication: String? = nil) {
        self.service = service
        _application = State(initialValue: initialApplication)
    }

    private var inputs: [MouseButtonInput] {
        let profile = application.flatMap { service.settings.profiles[$0] } ?? [:]
        let keys = Array(service.settings.bindings.keys) + Array(profile.keys)
        return Array(Set(MouseButtonInput.common + keys.compactMap { Int($0).flatMap(MouseButtonInput.init(rawValue:)) }
                         + (service.detected.map { [$0] } ?? []))).sorted { $0.rawValue < $1.rawValue }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Fare Tuşları", subtitle: "Yan tuşlara ve yan tekere kısayol ata; her uygulama için ayrı seçim yap.", icon: "computermouse") {
                Toggle("Fare tuşu atamalarını aç", isOn: $service.settings.enabled).pocketSwitch()
                    .accessibilityLabel("Fare tuşu atamalarını aç").accessibilityIdentifier("mouse-buttons.enabled")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if service.settings.enabled && !service.trusted {
                        VStack(alignment: .leading, spacing: PocketSpacing.s) {
                            PocketMessage("Fare tuşlarını değiştirmek için Erişilebilirlik izni gerekir.", tone: .warning)
                            HStack {
                                Button("İzin ver…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                                Button("İzin Durumunu Yenile") { service.refreshPermission() }
                            }
                        }
                    }
                    if let failure = service.failure {
                        PocketMessage(failure, tone: .warning)
                        Button("Yeniden Dene") { service.refreshPermission() }
                    }
                    assignments
                    exclusions
                    Text("Sol ve sağ tıklama değişmez. Geri/ileri, bu kısayolları destekleyen Finder ve tarayıcılarda çalışır. Trackpad ve Magic Mouse kaydırma hareketleri atama tetiklemez. Yan teker, hareket serisi başına bir kez tetikler.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .pocketPage().background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { service.stopCapture(); service.recordingShortcut = false }
    }

    private var assignments: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Tuş atamaları", icon: "cursorarrow.click")
            ViewThatFits(in: .horizontal) {
                HStack { profilePicker; profileButtons }
                VStack(alignment: .leading) { profilePicker; profileButtons }
            }
            if let application, service.settings.excludedBundleIDs.contains(application) {
                Label("Bu uygulama hariç tutuluyor; kayıtlı atamalar uygulanmaz.", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(inputs) { input in
                bindingRow(input)
                if input != inputs.last { Divider() }
            }
            HStack {
                Picker("Ek tuş", selection: $extra) {
                    ForEach(MouseButtonInput.allCases.filter { !MouseButtonInput.common.contains($0) }) { input in
                        Text(input.localizedTitle).tag(input)
                    }
                }.frame(maxWidth: 260, alignment: .leading)
                    .pocketMenuPicker()
                Button("Satır ekle") { service.settings.set(.init(.native), for: extra, application: application) }
                    .disabled(inputs.contains(extra))
            }
            HStack {
                Button(service.capturing ? "Algılamayı iptal et" : "Tuşu algıla…") {
                    service.capturing ? service.stopCapture() : service.beginCapture()
                }
                if service.capturing { Text("10 saniye içinde bu pencerenin üzerinde bir yan tuşa bas veya yan tekeri çevir.").font(.caption).foregroundStyle(.secondary) }
                else if let detected = service.detected { Text(detected.localizedTitle).font(.caption).foregroundStyle(.secondary) }
            }
            Text("Uygulama profilleri, değiştirmediğin tuşlarda genel atamaları kullanır. Kapalı MacPocket modüllerinin eylemleri uygulanmaz; o tuşun normal davranışı korunur.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).pocketCard()
    }
    private var profilePicker: some View {
        Picker("Profil", selection: $application) {
            Text("Tüm uygulamalar").tag(nil as String?)
            ForEach(service.settings.profiles.keys.sorted(), id: \.self) { id in Text(verbatim: appName(id)).tag(Optional(id)) }
        }.frame(maxWidth: 350, alignment: .leading)
            .pocketMenuPicker()
    }
    private var profileButtons: some View {
        HStack {
            Button("Uygulama profili ekle…") {
                guard let id = chooseApps(multiple: false).first else { return }
                if service.settings.profiles[id] == nil { service.settings.profiles[id] = [:] }
                application = id
            }
            if let application {
                Button("Profili kaldır") { service.settings.profiles[application] = nil; self.application = nil }
            }
        }
    }
    @ViewBuilder private func bindingRow(_ input: MouseButtonInput) -> some View {
        let explicit = service.settings.explicitBinding(for: input, application: application)
        let inherited = service.settings.bindings[input.key] ?? .init(.native)
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(input.localizedTitle).frame(width: 130, alignment: .leading); actionPicker(input, explicit); Spacer(minLength: 4); removeRow(input) }
                VStack(alignment: .leading) { Text(input.localizedTitle); HStack { actionPicker(input, explicit); removeRow(input) } }
            }
            if explicit?.action == .shortcut {
                KeyComboRecorder(combo: Binding(get: { service.settings.explicitBinding(for: input, application: application)?.shortcut }, set: {
                    service.settings.set(.init(.shortcut, shortcut: $0), for: input, application: application)
                }), allowsClearing: true, requiresModifier: false, recording: { service.recordingShortcut = $0 })
                .accessibilityLabel(Text("\(input.localizedTitle) kısayolu"))
                if explicit?.isExecutable != true { Text("Kısayol kaydedilene kadar bu tuş değiştirilmez.").font(.caption).foregroundStyle(.secondary) }
            }
            if application != nil && explicit == nil {
                Text("Genel atama: \(inherited.action.localizedTitle)").font(.caption).foregroundStyle(.secondary)
            }
            let effective = explicit ?? inherited
            if !service.actionAvailable(effective.action) {
                Label("Bu eylem şu anda kapalı. İlgili aracı veya modülü etkinleştir.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func actionPicker(_ input: MouseButtonInput, _ binding: MouseButtonBinding?) -> some View {
        Picker("Eylem", selection: Binding<MouseButtonAction?>(get: { binding?.action ?? (application == nil ? .native : nil) }, set: { kind in
            let shortcut = service.settings.explicitBinding(for: input, application: application)?.shortcut
            service.settings.set(kind.map { .init($0, shortcut: shortcut) }, for: input, application: application)
        })) {
            if application != nil { Text("Genel atamayı kullan").tag(nil as MouseButtonAction?) }
            ForEach(MouseButtonAction.allCases) { action in Text(action.localizedTitle).tag(Optional(action)) }
        }
        .labelsHidden().frame(maxWidth: 280)
        .accessibilityLabel(Text("\(input.localizedTitle) eylemi"))
        .accessibilityIdentifier("mouse-buttons.action." + input.key)
            .pocketMenuPicker()
    }
    @ViewBuilder private func removeRow(_ input: MouseButtonInput) -> some View {
        if !MouseButtonInput.common.contains(input), service.settings.explicitBinding(for: input, application: application) != nil || service.detected == input {
            Button {
                service.settings.set(nil, for: input, application: application)
                service.clearDetected(input)
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).accessibilityLabel(Text("\(input.localizedTitle) atamasını kaldır"))
        }
    }
    private var exclusions: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Dokunulmayacak uygulamalar", icon: "app.badge")
            ForEach(service.settings.excludedBundleIDs, id: \.self) { id in
                HStack {
                    Text(verbatim: appName(id))
                    Spacer()
                    Button { service.settings.excludedBundleIDs.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityLabel(Text("\(appName(id)) hariç tutmasını kaldır"))
                }
            }
            Button("Uygulama ekle…") {
                for id in chooseApps(multiple: true) where !service.settings.excludedBundleIDs.contains(id) { service.settings.excludedBundleIDs.append(id) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pocketCard()
    }
    private func appName(_ id: String) -> String {
        if id == Bundle.main.bundleIdentifier { return Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MacPocket" }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
    }
    private func chooseApps(multiple: Bool) -> [String] {
        service.stopCapture()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = multiple
        return panel.runModal() == .OK ? panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier } : []
    }
}
