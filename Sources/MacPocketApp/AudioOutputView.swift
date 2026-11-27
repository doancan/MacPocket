import AppKit
import CoreAudio
import MacPocketCore
import SwiftUI

@MainActor
final class AudioOutputService: ObservableObject {
    static let shared = AudioOutputService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("AudioOutputService")
    #endif

    @Published var settings = AudioOutputSettings.load(from: .standard) {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            registerShortcut()
        }
    }
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var current: AudioObjectID?
    @Published private(set) var failure: String?
    var recordingShortcut = false { didSet { registerShortcut() } }
    private lazy var hotKey = PocketGlobalHotKey { [weak self] in self?.switchToNext() }
    private var previous: AudioOutputDevice?
    private(set) var moduleRunning = false
    private let audioObservers = AudioPropertyObservers()

    private init() {}

    func start() {
        guard !moduleRunning, PocketModule.audioOutput.isAvailable() else { return }
        moduleRunning = true
        reload()
        previous = devices.first { $0.objectID == current }
        audioObservers.add(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] _, _ in
            MainActor.assumeIsolated { if self?.moduleRunning == true { self?.outputChanged() } }
        }
        audioObservers.add(kAudioHardwarePropertyDevices) { [weak self] _, _ in
            MainActor.assumeIsolated { if self?.moduleRunning == true { self?.reload() } }
        }
        registerShortcut()
    }

    func stopForModule() {
        moduleRunning = false
        hotKey.unregister()
        audioObservers.removeAll()
        previous = nil
    }

    private func registerShortcut() {
        if let shortcut = settings.shortcut, moduleRunning, !recordingShortcut { hotKey.register(shortcut) } else { hotKey.unregister() }
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
            failure = nil
            PocketToast.show(String(localized: "Ses çıkışı: \(device.name)"), symbol: device.kind.symbol)
        } else {
            failure = String(localized: "Ses çıkışı değiştirilemedi. Aygıtın bağlantısını kontrol edip yeniden dene.")
        }
    }

    func switchToNext() {
        guard moduleRunning else { return }
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
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Ses Çıkışı",
                                  subtitle: "Hoparlör, kulaklık ve monitör sesi arasında tek tıkla ya da kısayolla geç; kulaklık ayrılınca ses kendiliğinden kısılsın.",
                                  icon: "hifispeaker.2") {
                    Button { service.reload() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                }
                if let failure = service.failure { PocketMessage(failure, tone: .warning) }
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    PocketSectionHeader("Çıkışlar", icon: "speaker.wave.2")
                    if service.devices.isEmpty {
                        ContentUnavailableView("Ses çıkışı bulunamadı", systemImage: "speaker.slash",
                                               description: Text("Bir ses aygıtı bağla veya Yenile ile yeniden kontrol et."))
                    }
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
                                .disabled(service.devices.count == 1 || service.settings.cycle == [device.uid])
                                .help("Kısayol döngüsünde en az bir çıkış kalmalı.")
                                .accessibilityLabel(Text("\(device.name) kısayol döngüsünde"))
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

#if DEBUG
extension AudioOutputService {
    var moduleDiagnosticResources: [String: Int] { ["listeners": audioObservers.count] }
}
#endif
