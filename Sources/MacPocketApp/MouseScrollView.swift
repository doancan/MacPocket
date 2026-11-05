import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MouseScrollService: ObservableObject {
    static let shared = MouseScrollService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("MouseScrollService")
    #endif
    private(set) var moduleRunning = false

    @Published var settings = MouseScrollSettings.load(from: .standard) {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            configureTap()
        }
    }
    @Published private(set) var tapActive = false

    private var activationObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var scroller = SmoothScroller()
    private var frameTimer: Timer?
    nonisolated static let marker: Int64 = 0x4D50_5343
    private var glideTarget: pid_t?
    private static let frameRate = 60.0

    private init() {}

    func stopForModule() {
        moduleRunning = false
        configureTap()
        frameTimer?.invalidate()
        frameTimer = nil
        scroller = SmoothScroller()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        glideTarget = nil
    }

    func start() {
        guard !moduleRunning, PocketModule.mouseScroll.isAvailable() else { return }
        moduleRunning = true
        configureTap()
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureTap() }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopGlide() }
        }
    }

    func configureTap() {
        let wanted = moduleRunning && settings.enabled && AXIsProcessTrusted()
        if wanted && tap == nil {
            let callback: CGEventTapCallBack = { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MouseScrollService>.fromOpaque(context).takeUnretainedValue()
                let keep: Bool = MainActor.assumeIsolated { service.handle(type, event) }
                return keep ? Unmanaged.passUnretained(event) : nil
            }
            if let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue), callback: callback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) {
                let runLoopSource = CFMachPortCreateRunLoopSource(nil, created, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: created, enable: true)
                tap = created
                source = runLoopSource
            }
        } else if !wanted, let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            self.tap = nil
            source = nil
        }
        if !wanted { frameTimer?.invalidate(); frameTimer = nil; scroller = SmoothScroller() }
        tapActive = tap != nil
    }

    /// Returns false to drop the event (replaced by a glide).
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard type == .scrollWheel, event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return true }
        if MouseInputClaims.claims(event) { stopGlide(); return true }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, settings.excludedBundleIDs.contains(front) { return true }
        let plan = MouseScrollTransform.plan(vertical: Int32(clamping: event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                                             horizontal: Int32(clamping: event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                                             isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                                             settings: settings)
        switch plan {
        case .pass:
            return true
        case let .lines(vertical, horizontal):
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(vertical))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(horizontal))
            // Apps that read point or fixed-point deltas must see the same distance.
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(vertical))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(horizontal))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(Double(vertical) * MouseScrollSettings.pointsPerLine))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(Double(horizontal) * MouseScrollSettings.pointsPerLine))
            return true
        case let .glide(vertical, horizontal):
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if glideTarget != pid { stopGlide() }
            glideTarget = pid
            let duration = min(400, max(80, settings.smoothDurationMilliseconds))
            let frames = Int((Double(duration) / 1000 * Self.frameRate).rounded())
            scroller.add(vertical: vertical, horizontal: horizontal, frames: frames)
            startGlide()
            return false
        }
    }

    private func startGlide() {
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / Self.frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.glideFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func glideFrame() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == glideTarget else { stopGlide(); return }
        let step = scroller.nextFrame()
        if step.vertical != 0 || step.horizontal != 0,
           let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(step.vertical.rounded()), wheel2: Int32(step.horizontal.rounded()), wheel3: 0) {
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            event.post(tap: .cgSessionEventTap)
        }
        if scroller.isIdle {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    private func stopGlide() {
        frameTimer?.invalidate(); frameTimer = nil; scroller = SmoothScroller(); glideTarget = nil
    }
}

/// Tools → Fare Kaydırma.
struct MouseScrollView: View {
    @ObservedObject private var service = MouseScrollService.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Fare Kaydırma",
                                  subtitle: "Farenin tekerleğini trackpad’den bağımsız ayarla: yön, sabit hız, yumuşak kaydırma. Trackpad ve Magic Mouse etkilenmez.",
                                  icon: "computermouse") {
                    Toggle("Fare kaydırma", isOn: $service.settings.enabled).toggleStyle(.switch).labelsHidden()
                }
                if service.settings.enabled && !trusted {
                    HStack(spacing: PocketSpacing.m) {
                        PocketMessage("Kaydırmayı değiştirmek için Erişilebilirlik izni gerekir.", tone: .warning)
                        Button("İzin ver…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: PocketSpacing.m) {
                    PocketSectionHeader("Yön", icon: "arrow.up.arrow.down")
                    Toggle("Dikey kaydırmayı ters çevir", isOn: $service.settings.reverseVertical)
                    Toggle("Yatay kaydırmayı ters çevir", isOn: $service.settings.reverseHorizontal)
                    Text("Trackpad’de doğal kaydırmayı açık bırakıp farede klasik yönü kullanabilirsin.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pocketCard()
                VStack(alignment: .leading, spacing: PocketSpacing.m) {
                    PocketSectionHeader("Hız ve his", icon: "speedometer")
                    Toggle("Doğrusal kaydırma (hızlı çevirince hızlanmasın)", isOn: $service.settings.linear)
                    Stepper(value: $service.settings.linesPerNotch, in: MouseScrollSettings.linesRange) {
                        Text("Çentik başına \(service.settings.linesPerNotch) satır")
                    }
                    .disabled(!service.settings.linear)
                    HStack {
                        Text("Hız")
                        Slider(value: $service.settings.speed, in: MouseScrollSettings.speedRange, step: 0.25) { Text("Hız") }
                            .labelsHidden().frame(maxWidth: 240)
                        Text(verbatim: "×" + service.settings.speed.formatted(.number.precision(.fractionLength(0...2)).locale(pocketLocale)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Toggle("Yumuşak kaydırma", isOn: $service.settings.smooth)
                    HStack {
                        Text("Kayma süresi")
                        Slider(value: Binding(get: { Double(service.settings.smoothDurationMilliseconds) },
                                              set: { service.settings.smoothDurationMilliseconds = Int($0) }),
                               in: Double(MouseScrollSettings.durationRange.lowerBound)...Double(MouseScrollSettings.durationRange.upperBound), step: 20) {
                            Text("Kayma süresi")
                        }
                        .labelsHidden().frame(maxWidth: 240)
                        Text("\(service.settings.smoothDurationMilliseconds) ms").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .disabled(!service.settings.smooth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pocketCard()
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    PocketSectionHeader("Dokunulmayacak uygulamalar", icon: "app.badge")
                    ForEach(service.settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: PocketSpacing.s) {
                            PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), size: 18)
                            Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
                            Spacer()
                            Button { service.settings.excludedBundleIDs.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Listeden çıkar")
                        }
                    }
                    Button { addExcluded() } label: { Label("Uygulama ekle…", systemImage: "plus") }
                    Text("Örneğin kendi kaydırma ayarı olan oyunlar ve tasarım uygulamaları.").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pocketCard()
                Spacer(minLength: 0)
            }
            .pocketPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private func addExcluded() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !service.settings.excludedBundleIDs.contains($0) }
        service.settings.excludedBundleIDs.append(contentsOf: ids)
    }
}

#if DEBUG
extension MouseScrollService {
    var moduleDiagnosticResources: [String: Int] { ["observer": (activationObserver == nil ? 0 : 1) + (workspaceObserver == nil ? 0 : 1), "tap": tapActive ? 1 : 0, "timer": frameTimer?.isValid == true ? 1 : 0] }
}
#endif
