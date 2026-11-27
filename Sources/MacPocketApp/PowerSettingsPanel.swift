import MacPocketCore
import SwiftUI

/// Every pmset setting per power source, with a confirm-then-authenticate edit flow.
struct PowerSettingsPanel: View {
    var center: PowerCenterModel
    @State private var selectedProfile: PMPowerProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            if let message = center.applyMessage {
                PocketMessage(message.text, tone: message.success ? .success : .warning)
            }
            if let error = center.settingsError {
                PocketMessage(error, error: true)
            }
            if center.profiles.isEmpty {
                if center.settingsLoading {
                    PocketProgressRow(message: "pmset -g custom okunuyor…")
                } else if center.settingsError == nil {
                    ContentUnavailableView("Güç ayarı bulunamadı", systemImage: "slider.horizontal.3",
                                           description: Text("pmset bu Mac için ayar bildirmedi."))
                        .frame(maxWidth: .infinity).pocketCard()
                }
            } else {
                settingsCard
            }
            footer
        }
    }

    private var profile: PMSettingsProfile? {
        let chosen = selectedProfile ?? center.profiles.first?.profile
        return center.profiles.first { $0.profile == chosen } ?? center.profiles.first
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Güç ayarları", icon: "slider.horizontal.3") {
                HStack(spacing: PocketSpacing.s) {
                    if center.profiles.count > 1 {
                        GlassTabBar(tabs: center.profiles.map { GlassTab(id: $0.profile, title: $0.profile.title) },
                                    selection: Binding(get: { profile?.profile ?? .ac }, set: { selectedProfile = $0 }))
                        .accessibilityLabel("Güç kaynağı")
                        .frame(width: 220)
                    } else if let profile {
                        Text(profile.profile.title)
                    }
                    Button { Task { await center.loadSettings() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Ayarları yeniden oku").disabled(center.settingsLoading)
                        .accessibilityLabel("Ayarları yeniden oku")
                }
            }
            if let profile {
                Text("Değişiklikler yalnızca \(profile.profile.title.lowercased()) profiline uygulanır ve yönetici parolası ister.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                ForEach(profile.terminalOnlyValues) { value in
                    PowerSettingRow(value: value, live: liveValue(for: value), profile: profile.profile, center: center)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    private func liveValue(for value: PMSettingValue) -> PMSettingValue? {
        center.live?.values.first { $0.name == value.name }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: PocketSpacing.m) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Burada yalnız Sistem Ayarları’nda karşılığı olmayan, normalde Terminal’de pmset ile değiştirilen ayarlar listelenir; uyku, Power Nap ve ağ erişimiyle uyandırma gibi ayarlar Sistem Ayarları’nda kalır. MacPocket değişikliği yalnızca `/usr/bin/pmset` ile, onayladığın tek bir komutla yapar; komut sabit bir ayar listesinden ve doğrulanmış sayılardan oluşturulur.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { center.openSystemSettings() } label: {
                Label(center.hasBattery ? "Sistem Ayarları › Pil" : "Sistem Ayarları › Enerji", systemImage: "arrow.up.forward.app")
            }
        }
        .padding(.horizontal, PocketSpacing.xs)
    }
}

struct PowerSettingRow: View {
    let value: PMSettingValue
    let live: PMSettingValue?
    let profile: PMPowerProfile
    var center: PowerCenterModel

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.m) {
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                HStack(spacing: PocketSpacing.s) {
                    Text(value.title).font(.callout.weight(.medium))
                    Text(value.name).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                Text(value.key?.explanation ?? String(localized: "macOS’un bildirdiği ek güç ayarı."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = live?.note ?? value.note {
                    Label(translate(note), systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: PocketSpacing.m)
            if let live, live.rawValue != value.rawValue {
                Text("Etkin: \(live.displayValue)").font(.subheadline).foregroundStyle(.secondary)
                    .help("Şu an kullanılan değer farklı (ör. başka bir güç kaynağı veya uygulama tarafından)")
            }
            control
        }
        .padding(.vertical, PocketSpacing.xs)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var control: some View {
        if let key = value.key, key.isEditable, let current = value.number {
            Menu {
                ForEach(PowerSettingPresets.values(for: key, current: current), id: \.self) { option in
                    Button {
                        center.request(profile: profile, key: key, value: option)
                    } label: {
                        if option == current { Label(key.display(option), systemImage: "checkmark") }
                        else { Text(key.display(option)) }
                    }
                    .disabled(option == current)
                }
                if PowerSettingPresets.allowsCustom(key) {
                    Divider()
                    Button("Özel değer…") { center.request(profile: profile, key: key, value: current) }
                }
            } label: {
                Text(value.displayValue).monospacedDigit()
            }
            .menuStyle(.borderedButton)
            .fixedSize()
            .disabled(center.applying)
            .accessibilityLabel("\(value.title): \(value.displayValue)")
        } else {
            HStack(spacing: PocketSpacing.xs) {
                Text(value.displayValue).monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "lock").font(.subheadline).foregroundStyle(.tertiary)
                    .help("Yalnızca görüntülenir")
            }
        }
    }

    private func translate(_ note: String) -> String {
        guard let range = note.range(of: "prevented by ") else { return note }
        let list = note[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        return String(localized: "Şu an engelleyenler: \(list)")
    }
}

enum PowerSettingPresets {
    static func values(for key: PMSettingKey, current: Int) -> [Int] {
        var options: [Int]
        switch key.kind {
        case .minutes: options = [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
        case .seconds: options = [0, 60, 300, 900, 1800, 3600, 10_800, 21_600, 43_200, 86_400]
        case .percent: options = [10, 20, 30, 40, 50, 60, 70, 80, 90]
        case .toggle: options = [1, 0]
        case let .choice(choices): options = choices.map(\.value)
        case .raw: options = []
        }
        if key.accepts(current), !options.contains(current) { options.append(current) }
        return options.filter(key.accepts).sorted { key.kind == .toggle ? $0 > $1 : $0 < $1 }
    }

    static func allowsCustom(_ key: PMSettingKey) -> Bool {
        switch key.kind {
        case .minutes, .seconds, .percent: true
        default: false
        }
    }

    static func range(for key: PMSettingKey) -> ClosedRange<Int>? {
        switch key.kind {
        case let .minutes(range), let .seconds(range): range
        case .percent: 0...100
        default: nil
        }
    }
}

/// Shows the exact command before anything privileged runs.
struct PowerChangeConfirmation: View {
    var center: PowerCenterModel
    @State var change: PowerSettingChange
    @Environment(\.dismiss) private var dismiss

    private var command: Result<PMSetCommand, Error> {
        Result { try PMSetCommand(scope: change.profile.scope, key: change.key, value: change.newValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: "lock.shield", tint: PocketTheme.power, size: PocketIconSize.feature)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Güç ayarını değiştir").font(.title3.weight(.semibold))
                    Text("\(change.key.title) · \(change.profile.title)").foregroundStyle(.secondary)
                }
            }
            Text(change.key.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: PocketSpacing.l, verticalSpacing: PocketSpacing.s) {
                GridRow {
                    Text("Şu anki").foregroundStyle(.secondary)
                    Text(change.currentValue.map(change.key.display) ?? "—").monospacedDigit()
                }
                GridRow {
                    Text("Yeni").foregroundStyle(.secondary)
                    HStack {
                        Text(change.key.display(change.newValue)).fontWeight(.semibold).monospacedDigit()
                        if let range = PowerSettingPresets.range(for: change.key) {
                            Stepper("Değer", value: $change.newValue, in: range, step: step)
                                .labelsHidden()
                            TextField("Değer", value: $change.newValue, format: .number)
                                .frame(width: 80).textFieldStyle(.bordered).textInputBorderShape(.roundedRectangle)
                                .accessibilityLabel("Yeni değer")
                        }
                    }
                }
            }
            .font(.callout)
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Text("Çalıştırılacak komut").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                switch command {
                case let .success(command):
                    Text(command.commandLine)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(PocketSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: PocketRadius.small))
                case let .failure(error):
                    PocketMessage(error.localizedDescription, error: true)
                }
            }
            Text("Onayladığında macOS yönetici parolanı soracak. Ayar kalıcıdır; aynı ekrandan geri alabilirsin.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let confirmed = change
                    Task {
                        await center.apply(confirmed)
                        dismiss()
                    }
                } label: {
                    if center.applying { ProgressView().controlSize(.small) } else { Text("Onayla ve Uygula") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pocketPrimary)
                .disabled(center.applying || isUnchanged || (try? command.get()) == nil)
            }
        }
        .padding(PocketSpacing.xl)
        .frame(width: 480)
        .interactiveDismissDisabled(center.applying)
    }

    private var isUnchanged: Bool { change.currentValue == change.newValue }

    private var step: Int {
        if case .seconds = change.key.kind { return 60 }
        return 1
    }
}
