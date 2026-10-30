import AppKit
import CoreAudio
import MacPocketCore
import SwiftUI

@MainActor
final class AudioOutputService: ObservableObject {
    static let shared = AudioOutputService()

    @Published var settings = AudioOutputSettings.load(from: .standard) {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            registerShortcut()
        }
    }
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var current: AudioObjectID?
    var recordingShortcut = false { didSet { registerShortcut() } }
    private lazy var hotKey = PocketGlobalHotKey { [weak self] in self?.switchToNext() }
    private var previous: AudioOutputDevice?

    private init() {}

    func start() {
        reload()
        previous = devices.first { $0.objectID == current }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
        var listAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(system, &listAddress, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        registerShortcut()
    }

    private func registerShortcut() {
        if let shortcut = settings.shortcut, !recordingShortcut { hotKey.register(shortcut) } else { hotKey.unregister() }
    }

    func reload() {
        devices = AudioOutputSystem.outputDevices()
        current = AudioOutputSystem.defaultOutput
    }

    /// Any change of the default output, whoever made it: applies the "speakers after headphones" volume.
    private func outputChanged() {
        reload()
        let now = devices.first { $0.objectID == current }
        if let level = AudioOutputRules.volumeAfterSwitch(from: previous, to: now, settings: settings), let now {
            AudioOutputSystem.setVolume(level, of: now.objectID)
            PocketToast.show(String(localized: "\(now.name): ses \(pocketPercent(level * 100)) seviyesine indirildi"), symbol: "speaker.wave.1")
        }
        previous = now
    }

    func select(_ device: AudioOutputDevice) {
        if AudioOutputSystem.setDefaultOutput(device.objectID) {
            PocketToast.show(String(localized: "Ses çıkışı: \(device.name)"), symbol: device.kind.symbol)
        }
    }

    func switchToNext() {
        reload()
        let uid = devices.first { $0.objectID == current }?.uid
        guard let next = AudioOutputRules.next(after: uid, devices: devices, cycle: settings.cycle) else { return }
        select(next)
    }
}

/// Tools → Ses Çıkışı.
struct AudioOutputView: View {
    @ObservedObject private var service = AudioOutputService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ses Çıkışı",
                              subtitle: "Hoparlör, kulaklık ve monitör sesi arasında tek tıkla ya da kısayolla geç; kulaklık ayrılınca ses kendiliğinden kısılsın.",
                              icon: "hifispeaker.2") {
                Button { service.reload() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                PocketSectionHeader("Çıkışlar", icon: "speaker.wave.2")
                ForEach(service.devices) { device in
                    HStack(spacing: PocketSpacing.m) {
                        Image(systemName: device.kind.symbol).frame(width: 24).foregroundStyle(device.objectID == service.current ? Color.accentColor : .secondary)
                        Text(device.name).fontWeight(device.objectID == service.current ? .semibold : .regular)
                        if device.objectID == service.current {
                            PocketStatusBadge(text: "Kullanılıyor", systemImage: "checkmark.circle.fill", tone: .success)
                        }
                        Spacer()
                        Toggle("Kısayol döngüsünde", isOn: Binding(get: { service.settings.cycle.isEmpty || service.settings.cycle.contains(device.uid) },
                                                                   set: { include in toggleCycle(device, include: include) }))
                            .toggleStyle(.checkbox)
                            .font(.callout)
                        Button("Seç") { service.select(device) }
                            .disabled(device.objectID == service.current)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard()
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                PocketSectionHeader("Seçenekler", icon: "slider.horizontal.3")
                LabeledContent("Sonraki çıkışa geç") {
                    KeyComboRecorder(combo: $service.settings.shortcut, allowsClearing: true, recording: { service.recordingShortcut = $0 })
                }
                Toggle("Kulaklık ayrılıp ses hoparlöre geçince sesi kıs", isOn: Binding(
                    get: { service.settings.speakerVolumeAfterHeadphones != nil },
                    set: { service.settings.speakerVolumeAfterHeadphones = $0 ? 0.25 : nil }))
                if let level = service.settings.speakerVolumeAfterHeadphones {
                    HStack {
                        Text("Hoparlör sesi")
                        Slider(value: Binding(get: { level }, set: { service.settings.speakerVolumeAfterHeadphones = $0 }), in: 0...1) {
                            Text("Hoparlör sesi")
                        }
                        .labelsHidden().frame(maxWidth: 240)
                        Text(verbatim: pocketPercent(level * 100)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard()
            Spacer(minLength: 0)
        }
        .pocketPage()
        .onAppear { service.reload() }
    }

    /// An empty cycle means "every device"; the first exclusion turns it into an explicit list.
    private func toggleCycle(_ device: AudioOutputDevice, include: Bool) {
        var cycle = service.settings.cycle.isEmpty ? service.devices.map(\.uid) : service.settings.cycle
        if include { if !cycle.contains(device.uid) { cycle.append(device.uid) } } else { cycle.removeAll { $0 == device.uid } }
        service.settings.cycle = Set(cycle) == Set(service.devices.map(\.uid)) ? [] : cycle
    }
}

extension AudioOutputDevice.Kind {
    var symbol: String {
        switch self {
        case .builtIn: "hifispeaker"
        case .headphones: "headphones"
        case .bluetooth: "airpodspro"
        case .usb: "cable.connector"
        case .display: "display"
        case .airPlay: "airplayaudio"
        case .virtual: "waveform"
        case .other: "speaker"
        }
    }
}
