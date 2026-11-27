import AppKit
import MacPocketCore
import SwiftUI
import MacPocketShared

/// Staged edits of hidden settings. Nothing is written until Apply; then every change goes out at once and
/// each affected process (Dock, Finder, SystemUIServer) restarts a single time.
@MainActor
final class HiddenSettingsModel: ObservableObject {
    struct Message: Equatable {
        let text: String
        let tone: PocketTone
    }

    @Published private(set) var states: [String: HiddenSettingState] = [:]
    @Published private(set) var drafts: [String: HiddenSettingChange] = [:]
    @Published private(set) var applying = false
    @Published private(set) var message: Message?
    private let service = HiddenSettingsService()

    func reload() {
        states = Dictionary(uniqueKeysWithValues: HiddenSetting.catalog.map { ($0.id, service.state(of: $0)) })
    }

    func state(_ setting: HiddenSetting) -> HiddenSettingState {
        states[setting.id] ?? HiddenSettingState(value: setting.systemDefault, isCustomized: false, isUnrecognized: false)
    }

    /// What the control shows: the staged value, else the value in effect.
    func value(_ setting: HiddenSetting) -> HiddenSettingValue {
        switch drafts[setting.id] {
        case let .set(_, value)?: value
        case .reset?: setting.systemDefault
        case nil: state(setting).value
        }
    }

    /// Stages `value`; staging what is already in effect drops the draft instead.
    func stage(_ setting: HiddenSetting, _ value: HiddenSettingValue) {
        let current = state(setting)
        let unchanged = current.isCustomized ? (!current.isUnrecognized && current.value == value) : value == setting.systemDefault
        drafts[setting.id] = unchanged ? nil : .set(id: setting.id, value: value)
        message = nil
    }

    func stageReset(_ setting: HiddenSetting) {
        drafts[setting.id] = state(setting).isCustomized ? .reset(id: setting.id) : nil
        message = nil
    }

    func discard() { drafts = [:] }

    var customizedCount: Int { states.values.filter(\.isCustomized).count }

    /// Processes Apply will restart, in the order it restarts them.
    var pendingRestarts: [HiddenSettingRestart] {
        let effects = drafts.keys.compactMap { HiddenSetting.setting(id: $0)?.effect }
        return HiddenSettingRestart.allCases.filter { effects.contains(.restarts($0)) }
    }

    func apply() async {
        guard !drafts.isEmpty, !applying else { return }
        applying = true
        defer { applying = false }
        let changes = HiddenSetting.catalog.compactMap { drafts[$0.id] }
        let deferred = changes.contains { change in
            guard let effect = HiddenSetting.setting(id: change.id)?.effect else { return false }
            return effect == .reopenApps || effect == .nextLogin
        }
        do {
            let report = try await service.apply(changes)
            for id in report.written { drafts[id] = nil }
            reload()
            message = Self.message(for: report, deferred: deferred)
        } catch {
            message = Message(text: error.localizedDescription, tone: .warning)
        }
    }

    private static func message(for report: HiddenSettingsApplyReport, deferred: Bool) -> Message {
        if !report.failed.isEmpty {
            let titles = report.failed.compactMap { HiddenSetting.setting(id: $0)?.title }.joined(separator: ", ")
            return Message(text: String(localized: "Şu ayarlar kaydedilemedi: \(titles)"), tone: .warning)
        }
        if !report.restartFailures.isEmpty {
            let names = report.restartFailures.map(\.title).joined(separator: ", ")
            return Message(text: String(localized: "Ayarlar kaydedildi ama \(names) yeniden başlatılamadı; oturumu kapatıp açınca etkili olur."),
                           tone: .warning)
        }
        var parts = [String(localized: "\(report.written.count) ayar kaydedildi.")]
        if !report.restarted.isEmpty {
            parts.append(String(localized: "Yeniden başlatıldı: \(report.restarted.map(\.title).joined(separator: ", ")).", comment: "List of restarted system processes"))
        }
        if deferred {
            parts.append(String(localized: "Bazı değişiklikler uygulamalar ya da oturum yeniden açılınca etkili olur."))
        }
        return Message(text: parts.joined(separator: " "), tone: .success)
    }
}

/// Tools → Gizli Ayarlar: macOS preferences that exist only as Terminal `defaults` commands.
struct HiddenSettingsView: View {
    @StateObject private var model = HiddenSettingsModel()
    @State private var group = HiddenSettingGroup.performance
    @PocketReduceMotion private var reduceMotion

    private var settings: [HiddenSetting] { HiddenSetting.catalog.filter { $0.group == group } }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86) }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Gizli Ayarlar",
                              subtitle: "Sistem Ayarları’nda bulunmayan, normalde Terminal’de defaults komutuyla değiştirilen macOS ayarları.",
                              icon: "terminal") {
                if model.customizedCount > 0 {
                    PocketStatusBadge(text: "\(model.customizedCount) özelleştirilmiş", systemImage: "slider.horizontal.3", tone: .accent)
                }
            }
            .pocketPageSections(HiddenSettingGroup.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol) },
                                selection: $group, label: "Ayar grubu")
            if let message = model.message {
                PocketMessage(message.text, tone: message.tone)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(settings.enumerated()), id: \.element.id) { index, setting in
                        if index > 0 { Divider().padding(.vertical, PocketSpacing.m) }
                        HiddenSettingRow(setting: setting, model: model, motion: motion)
                    }
                }
                .pocketCard()
                .padding(.bottom, PocketSpacing.xxl * 2)
            }
            .scrollIndicators(.automatic)
        }
        .pocketPage()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HiddenSettingsApplyBar(model: model, motion: motion)
                .padding(.bottom, PocketSpacing.l)
        }
        .onAppear { model.reload() }
    }
}

private struct HiddenSettingRow: View {
    let setting: HiddenSetting
    @ObservedObject var model: HiddenSettingsModel
    let motion: Animation?
    @State private var showsCommand = false

    var body: some View {
        let state = model.state(setting)
        let draft = model.drafts[setting.id]
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(alignment: .top, spacing: PocketSpacing.l) {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    HStack(spacing: PocketSpacing.s) {
                        Text(setting.title).font(.body.weight(.medium))
                        if draft != nil {
                            PocketStatusBadge(text: "Uygulanmadı", systemImage: "clock", tone: .warning)
                        } else if state.isUnrecognized {
                            PocketStatusBadge(text: "Tanınmayan değer", systemImage: "questionmark.circle", tone: .warning)
                        } else if state.isCustomized {
                            PocketStatusBadge(text: "Özel", systemImage: "checkmark.circle", tone: .accent)
                        }
                    }
                    Text(setting.detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PocketSpacing.m)
                control
            }
            HStack(spacing: PocketSpacing.m) {
                Label(setting.effect.title, systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Değişikliğin ne zaman etkili olacağı")
                Spacer(minLength: PocketSpacing.s)
                Button {
                    withAnimation(motion) { showsCommand.toggle() }
                } label: {
                    Label(showsCommand ? "Komutu gizle" : "Terminal komutu", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if state.isCustomized || draft != nil {
                    Button { withAnimation(motion) { model.stageReset(setting) } } label: {
                        Label("macOS varsayılanı", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Ayarı silerek macOS’un kendi varsayılanına döndür")
                    .disabled(draft == .reset(id: setting.id))
                }
            }
            if showsCommand {
                HiddenSettingCommand(lines: commandLines)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The command that produces what the control shows, plus the way back.
    private var commandLines: [String] {
        let value = model.value(setting)
        var lines = model.drafts[setting.id] == .reset(id: setting.id) ? [setting.deleteCommand]
                                                                         : [setting.writeCommand(value), setting.deleteCommand]
        if let restart = setting.restartCommand { lines.append(restart) }
        return lines
    }

    @ViewBuilder private var control: some View {
        switch setting.kind {
        case .toggle:
            Toggle(isOn: Binding(get: { model.value(setting) == .bool(true) },
                                 set: { isOn in withAnimation(motion) { model.stage(setting, .bool(isOn)) } })) {
                Text(setting.title)
            }
            .labelsHidden()
            .pocketSwitch()
        case let .seconds(range, step, _):
            HStack(spacing: PocketSpacing.s) {
                Slider(value: Binding(get: { if case let .number(number) = model.value(setting) { number } else { range.lowerBound } },
                                      set: { model.stage(setting, .number(($0 / step).rounded() * step)) }),
                       in: range, step: step) {
                    Text(setting.title)
                }
                .labelsHidden()
                .frame(width: 170)
                Text(seconds(model.value(setting)))
                    .font(.callout).monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
        case let .choice(options, _):
            Picker(selection: Binding(get: { if case let .text(text) = model.value(setting) { text } else { "" } },
                                      set: { value in withAnimation(motion) { model.stage(setting, .text(value)) } })) {
                ForEach(options) { option in Text(option.title).tag(option.value) }
            } label: {
                Text(setting.title)
            }
            .labelsHidden()
            .fixedSize()
                .pocketMenuPicker()
        }
    }

    private func seconds(_ value: HiddenSettingValue) -> String {
        guard case let .number(number) = value else { return "—" }
        return String(localized: "\(number.formatted(.number.precision(.fractionLength(0...2)).locale(pocketLocale))) sn")
    }
}

private struct HiddenSettingCommand: View {
    let lines: [String]
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: PocketSpacing.s) {
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            Spacer(minLength: PocketSpacing.s)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.first ?? "", forType: .string)
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("İlk komutu panoya kopyala")
            .accessibilityLabel("Komutu kopyala")
        }
        .padding(PocketSpacing.s)
        .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
        .onChange(of: lines) { _, _ in copied = false }
    }
}

/// Floating summary + Discard/Apply. Glass (functional layer over the scrolling list):
/// one container, so the summary capsule and buttons blend and materialize together.
private struct HiddenSettingsApplyBar: View {
    @ObservedObject var model: HiddenSettingsModel
    let motion: Animation?

    var body: some View {
        GlassEffectContainer(spacing: PocketSpacing.s) { content }
        .animation(motion, value: model.drafts.isEmpty)
    }

    @ViewBuilder private var content: some View {
        if !model.drafts.isEmpty {
            HStack(spacing: PocketSpacing.s) {
                summary
                Button("Vazgeç") { withAnimation(motion) { model.discard() } }
                    .buttonStyle(.pocketSecondary)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.applying)
                Button {
                    Task { await model.apply() }
                } label: {
                    if model.applying { ProgressView().controlSize(.small) } else { Text("Uygula") }
                }
                .buttonStyle(.pocketPrimary)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.applying)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var summary: some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: "terminal").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(model.drafts.count) değişiklik bekliyor").font(.callout.weight(.semibold))
                if !model.pendingRestarts.isEmpty {
                    Text("Uygulanınca yeniden başlatılır: \(model.pendingRestarts.map(\.title).joined(separator: ", "))")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, PocketSpacing.l)
        .frame(minHeight: 40)
        .modifier(HiddenSettingsSummarySurface())
        .accessibilityElement(children: .combine)
    }
}

private struct HiddenSettingsSummarySurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.adaptiveGlass(.regular, in: .capsule)
    }
}
