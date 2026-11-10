import AppKit
import Combine
import ApplicationServices
import CoreGraphics
import CoreLocation
import IOKit.hid
import MacPocketCore
import SwiftUI
import UserNotifications

// MARK: - Permission titles

extension OnboardingPermission {
    var title: LocalizedStringKey {
        switch self {
        case .accessibility: "Erişilebilirlik"
        case .screenRecording: "Ekran ve Sistem Sesi Kaydı"
        case .fullDiskAccess: "Tam Disk Erişimi"
        case .inputMonitoring: "Giriş İzleme"
        case .location: "Konum Servisleri"
        case .notifications: "Bildirimler"
        }
    }

    var reason: LocalizedStringKey {
        switch self {
        case .accessibility: "Pencereleri yönetmek, kısayolları ve fare tekerleğini dinlemek için."
        case .screenRecording: "Ekran görüntüsü, ekran kaydı ve pencere geçişindeki canlı önizlemeler için."
        case .fullDiskAccess: "Temizlik ve disk analizinin korunan klasörlerdeki önbellek ve kalıntıları görmesi için."
        case .inputMonitoring: "Logitech fare ve klavyelerin pil seviyesini okumak için."
        case .location: "Wi-Fi ağ adlarını göstermek ve gece modunda gün batımını hesaplamak için. Konum bu Mac’ten çıkmaz."
        case .notifications: "Düşük pil, dolan disk ve aşırı ısınma uyarıları için."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .fullDiskAccess: "internaldrive"
        case .inputMonitoring: "keyboard"
        case .location: "location.fill"
        case .notifications: "bell.badge.fill"
        }
    }

    var tint: Color {
        switch self {
        case .accessibility: Color(hex: 0x0A84FF)
        case .screenRecording: Color(hex: 0xFF375F)
        case .fullDiskAccess: Color(hex: 0x8E8E93)
        case .inputMonitoring: Color(hex: 0x5E5CE6)
        case .location: Color(hex: 0x0A84FF)
        case .notifications: Color(hex: 0xFF453A)
        }
    }
}

// MARK: - Live state

@MainActor
enum PermissionProbe {
    static func state(of permission: OnboardingPermission, location: CLLocationManager) async -> OnboardingPermissionState {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .fullDiskAccess:
            return FullDiskAccessProbe.granted() ? .granted : .notGranted
        case .inputMonitoring:
            switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
            case kIOHIDAccessTypeGranted: return .granted
            case kIOHIDAccessTypeDenied: return .denied
            default: return .notGranted
            }
        case .location:
            switch location.authorizationStatus {
            case .authorizedAlways: return .granted
            case .denied, .restricted: return .denied
            default: return .notGranted
            }
        case .notifications:
            guard PocketAlertNotifier.isAvailable else { return .unavailable }
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional: return .granted
            case .denied: return .denied
            default: return .notGranted
            }
        }
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep
    @Published private(set) var forward = true
    @Published private(set) var states: [OnboardingPermission: OnboardingPermissionState] = [:]
    @Published private(set) var requested: Set<OnboardingPermission> = []
    @Published private(set) var availableModules = Set(PocketModule.allCases.filter { $0.isAvailable() })
    private let location = CLLocationManager()
    private var polling: Task<Void, Never>?
    private(set) var finished = false

    init() {
        step = OnboardingRecord.resumeStep()
    }

    var permissions: [OnboardingPermission] { OnboardingPermission.allCases }
    var applicable: [OnboardingPermission] { permissions.filter { states[$0] != .unavailable && usage($0).isRelevant } }
    var grantedCount: Int { applicable.filter { states[$0] == .granted }.count }
    var missing: [OnboardingPermission] { applicable.filter { states[$0] != .granted } }

    /// macOS applies Screen Recording and Input Monitoring to a running app only after a relaunch.
    var relaunchSuggested: Bool { requested.contains { $0.mayNeedRelaunch && states[$0] != .granted && usage($0).isRelevant } }

    func usage(_ permission: OnboardingPermission) -> PermissionUsage { PermissionUsageMap.usage(permission, availableModules: availableModules) }

    func state(_ permission: OnboardingPermission) -> OnboardingPermissionState { states[permission] ?? .notGranted }

    func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPolling() {
        polling?.cancel()
        polling = nil
    }

    func refresh() async {
        let enabled = Set(PocketModule.allCases.filter { $0.isAvailable() })
        if availableModules != enabled { availableModules = enabled }
        var next: [OnboardingPermission: OnboardingPermissionState] = [:]
        for permission in permissions { next[permission] = await PermissionProbe.state(of: permission, location: location) }
        if next != states { states = next }
        if let shown = PermissionDragHelper.shared.permission, next[shown] == .granted || !usage(shown).isRelevant { PermissionDragHelper.shared.hide() }
    }

    func go(to target: OnboardingStep) {
        guard target != step else { return }
        forward = target.rawValue > step.rawValue
        step = target
        OnboardingRecord.saveResumeStep(target)
        if target != .permissions { PermissionDragHelper.shared.hide() }
    }

    func advance() { if let next = step.next { go(to: next) } }
    func back() { if let previous = step.previous { go(to: previous) } }

    func request(_ permission: OnboardingPermission) {
        let available = Set(PocketModule.allCases.filter { $0.isAvailable() })
        guard PermissionUsageMap.usage(permission, availableModules: available).isRelevant else { return }
        requested.insert(permission)
        OnboardingRecord.saveResumeStep(.permissions)
        switch permission {
        case .location where location.authorizationStatus == .notDetermined:
            location.requestWhenInUseAuthorization()
        case .notifications where state(.notifications) == .notGranted:
            Task { _ = await PocketAlertNotifier.requestAuthorization(); await refresh() }
        default:
            NSWorkspace.shared.open(permission.settingsURL())
            if permission.acceptsDraggedApp { PermissionDragHelper.shared.show(for: permission) }
        }
    }

    func finish() {
        finished = true
        OnboardingRecord.markCompleted()
        PermissionDragHelper.shared.hide()
        stopPolling()
    }
}

// MARK: - Drag card beside System Settings

/// A small floating card that follows the System Settings window and lets the user drag MacPocket's icon straight
/// into the permission list, the way macOS expects a non-prompting permission to be added.
@MainActor
final class PermissionDragHelper {
    static let shared = PermissionDragHelper()
    private(set) var permission: OnboardingPermission?
    private var panel: NSPanel?
    private var timer: Timer?
    private var shownAt = Date()
    private var sawSettings = false
    private static let size = CGSize(width: 340, height: 132)

    func show(for permission: OnboardingPermission) {
        self.permission = permission
        shownAt = Date()
        sawSettings = false
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: PermissionDragCard(permission: permission, close: { [weak self] in self?.hide() })
            .pocketAppearanceRoot(rebuildsOnTokenChange: false))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { PermissionDragHelper.shared.follow() }
        }
        follow()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        permission = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func follow() {
        guard let panel else { return }
        guard let window = Self.settingsWindowFrame() else {
            // System Settings still launching: wait a little; once it was seen and is gone, the card goes too.
            if sawSettings || Date().timeIntervalSince(shownAt) > 15 { hide() } else { panel.orderOut(nil) }
            return
        }
        sawSettings = true
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: window.midX, y: window.midY)) } ?? NSScreen.main
        let frame = PermissionHelperPlacement.frame(panel: Self.size, beside: window, within: screen?.visibleFrame ?? window)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Window bounds are readable without Screen Recording; only titles need it.
    private static func settingsWindowFrame() -> CGRect? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first?.frame.height else { return nil }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary), bounds.width > 200 else { continue }
            return PermissionHelperPlacement.appKitRect(fromWindowList: bounds, primaryScreenHeight: primary)
        }
        return nil
    }
}

private struct PermissionDragCard: View {
    let permission: OnboardingPermission
    let close: () -> Void
    @State private var nudge = false
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .offset(x: nudge ? 6 : 0)
                .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                .help("Sürükle ve listeye bırak")
                .accessibilityLabel(Text("MacPocket simgesi"))
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(permission.title).font(.headline)
                    Spacer(minLength: 0)
                    Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Kapat")
                }
                Text("Simgeyi Sistem Ayarları’ndaki listeye sürükle, ardından MacPocket’ın anahtarını aç.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("İzin verilince bu kart kendiliğinden kapanır.", systemImage: "arrow.left.and.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(PocketSpacing.l)
        .frame(width: 340, height: 132)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { nudge = true }
        }
    }
}

// MARK: - Wizard

struct OnboardingView: View {
    @ObservedObject var loginItem: LoginItemController
    @StateObject private var model = OnboardingModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        ZStack {
            if model.step == .welcome {
                OnboardingWelcome(start: model.advance)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                VStack(spacing: 0) {
                    OnboardingStepper(current: model.step)
                        .padding(.top, PocketSpacing.s).padding(.horizontal, PocketSpacing.xxl)
                    ZStack {
                        page
                            .id(model.step)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: model.forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: model.forward ? .leading : .trailing).combined(with: .opacity)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    footer
                }
                .background(OnboardingBackdrop())
                .transition(.opacity)
            }
        }
        .frame(width: 780, height: 640)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86), value: model.step)
        .onAppear { model.startPolling(); loginItem.refresh() }
        .onDisappear {
            model.stopPolling()
            PermissionDragHelper.shared.hide()
            // Closing the window counts as "seen". Quitting doesn't: macOS quits and reopens the app after a
            // permission like Full Disk Access is switched on, and the wizard must resume where it was.
            if !model.finished && !PocketLaunch.terminating && !PocketRelaunch.pending { OnboardingRecord.markCompleted() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
            Task { await model.refresh() }
        }
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .permissions: OnboardingPermissions(model: model)
        case .preferences: OnboardingPreferences(loginItem: loginItem)
        case .finish: OnboardingFinish(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: PocketSpacing.m) {
            if !model.step.isFirst {
                Button { model.back() } label: { Label("Geri", systemImage: "chevron.left") }
                    .buttonStyle(.bordered).controlSize(.large)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            Spacer()
            if model.step == .permissions && model.grantedCount < model.applicable.count {
                Button("Şimdilik geç") { model.advance() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button(action: primaryAction) {
                Text(primaryTitle).frame(minWidth: 120).padding(.vertical, 2)
            }
            .buttonStyle(.pocketPrimary)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, PocketSpacing.xxl)
        .padding(.vertical, PocketSpacing.l)
        .background(.bar.opacity(0.6))
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.step {
        case .welcome: "Başlayalım"
        case .permissions, .preferences: "Devam"
        case .finish: "MacPocket’ı Kullanmaya Başla"
        }
    }

    private func primaryAction() {
        guard model.step.isLast else { return model.advance() }
        model.finish()
        showPocketWindow(openWindow)
        dismissWindow(id: "onboarding")
    }
}

private struct OnboardingBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PocketTheme.background
            Circle().fill(PocketTheme.cobalt).frame(width: 420).blur(radius: 140)
                .offset(x: -300, y: -260).opacity(colorScheme == .dark ? 0.35 : 0.18)
            Circle().fill(PocketTheme.brandSecondary).frame(width: 380).blur(radius: 140)
                .offset(x: 320, y: 240).opacity(colorScheme == .dark ? 0.30 : 0.14)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingStepper: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: PocketSpacing.s) {
            ForEach(OnboardingStep.allCases) { step in
                let done = step.rawValue < current.rawValue
                let active = step == current
                HStack(spacing: PocketSpacing.s) {
                    ZStack {
                        Circle().fill(active || done ? AnyShapeStyle(PocketTheme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Text(verbatim: "\(step.rawValue + 1)").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(active ? .white : .secondary)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(step.title).font(.callout.weight(active ? .semibold : .regular))
                        .foregroundStyle(active ? .primary : .secondary)
                        .fixedSize()
                }
                if !step.isLast {
                    Capsule().fill(done ? AnyShapeStyle(PocketTheme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                        .frame(height: 2).frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Adım \(current.rawValue + 1) / \(OnboardingStep.allCases.count)")))
    }
}

private extension OnboardingStep {
    var title: LocalizedStringKey {
        switch self {
        case .welcome: "Hoş geldin"
        case .permissions: "İzinler"
        case .preferences: "Tercihler"
        case .finish: "Hazır"
        }
    }
}

// MARK: Steps

private struct OnboardingWelcome: View {
    let start: () -> Void
    @State private var appeared = false
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrbit(reduceMotion: reduceMotion)
                .frame(height: 300)
                .padding(.top, PocketSpacing.s)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.85)
            VStack(spacing: PocketSpacing.m) {
                Text("Hoş geldin")
                    .font(.callout.weight(.semibold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, PocketSpacing.m).padding(.vertical, 5)
                    .glassEffect(.regular.tint(.white.opacity(0.08)), in: .capsule)
                Text(verbatim: "MacPocket")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xD8E2FF)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(hex: 0x0A1A6B).opacity(0.45), radius: 18, y: 8)
                Text("Mac’in için cep boyu kontrol merkezi: izle, temizle, düzenle.")
                    .font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
            }
            .offset(y: appeared ? 0 : 18).opacity(appeared ? 1 : 0)
            HStack(spacing: PocketSpacing.s) {
                pill("waveform.path.ecg", "Canlı izleme")
                pill("sparkles", "Akıllı temizlik")
                pill("macwindow.on.rectangle", "Pencere ve pano")
                pill("wifi", "Wi-Fi ve donanım")
            }
            .padding(.top, PocketSpacing.l)
            .offset(y: appeared ? 0 : 18).opacity(appeared ? 1 : 0)
            Spacer(minLength: PocketSpacing.m)
            VStack(spacing: PocketSpacing.s) {
                Button(action: start) {
                    HStack(spacing: PocketSpacing.s) {
                        Text("Başlayalım")
                        Image(systemName: "arrow.right")
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x1638C9))
                    .padding(.horizontal, 34).padding(.vertical, 13)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(OnboardingPressStyle())
                .keyboardShortcut(.defaultAction)
                Label("Yaklaşık bir dakika sürer · Hiçbir veri bu Mac’ten çıkmaz", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.bottom, PocketSpacing.xl)
            .offset(y: appeared ? 0 : 24).opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingAurora(reduceMotion: reduceMotion).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { appeared = true }
        }
    }

    private func pill(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium)).foregroundStyle(.white)
            .padding(.horizontal, PocketSpacing.m).padding(.vertical, 7)
            .glassEffect(.regular.tint(.white.opacity(0.06)), in: .capsule)
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A slowly drifting brand-colour mesh behind the welcome page.
private struct OnboardingAurora: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let a = Float(sin(t * 0.35)) * 0.12, b = Float(cos(t * 0.27)) * 0.12, c = Float(sin(t * 0.21 + 1)) * 0.1
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + a, 0], [1, 0],
                [0, 0.5 + b], [0.5 + c, 0.45 - a], [1, 0.5 - c],
                [0, 1], [0.5 - b, 1], [1, 1],
            ], colors: [
                Color(hex: 0x0B1B6E), Color(hex: 0x1F4BFF), Color(hex: 0x6A3DF5),
                Color(hex: 0x0A5CFF), Color(hex: 0x4A5BFF), Color(hex: 0x9B4DFF),
                Color(hex: 0x07123F), Color(hex: 0x1B2FA8), Color(hex: 0x3A1D8F),
            ])
        }
        .overlay {
            // Soft vignette keeps the edges calm and the centre bright.
            RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 220, endRadius: 560)
        }
    }
}

/// The app icon with the toolbox orbiting it.
private struct OnboardingOrbit: View {
    let reduceMotion: Bool
    private let inner: [(String, Color)] = [("cpu", Color(hex: 0xFF8A00)), ("fanblades.fill", Color(hex: 0x30B0C7)),
                                            ("sparkles", Color(hex: 0x22A55B)), ("wifi", Color(hex: 0x0A84FF)),
                                            ("thermometer.medium", Color(hex: 0xFF453A)), ("battery.75percent", Color(hex: 0x34C759))]
    private let outer: [(String, Color)] = [("macwindow.on.rectangle", Color(hex: 0x5E5CE6)), ("doc.on.clipboard", Color(hex: 0xBF5AF2)),
                                            ("camera.viewfinder", Color(hex: 0xFF375F)), ("internaldrive", Color(hex: 0x8E8E93)),
                                            ("network", Color(hex: 0x64D2FF))]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(.white).frame(width: 170, height: 170).blur(radius: 60).opacity(0.35)
                Ellipse().strokeBorder(.white.opacity(0.18), lineWidth: 1).frame(width: 220, height: 220 * 0.82)
                Ellipse().strokeBorder(.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 6])).frame(width: 330, height: 330 * 0.82)
                ForEach(inner.indices, id: \.self) { index in
                    chip(inner[index], size: 34)
                        .offset(position(index: index, count: inner.count, radius: 110, angle: t * 0.25))
                }
                ForEach(outer.indices, id: \.self) { index in
                    chip(outer[index], size: 30)
                        .offset(position(index: index, count: outer.count, radius: 165, angle: -t * 0.15 + 0.4))
                        .opacity(0.9)
                }
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 124, height: 124)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
                    .offset(y: CGFloat(sin(t * 1.2)) * 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func position(index: Int, count: Int, radius: Double, angle: Double) -> CGSize {
        let theta = angle + Double(index) / Double(count) * 2 * .pi
        // A slightly flattened orbit reads as depth.
        return CGSize(width: cos(theta) * radius, height: sin(theta) * radius * 0.82)
    }

    private func chip(_ item: (String, Color), size: CGFloat) -> some View {
        Image(systemName: item.0)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(item.1.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
            .shadow(color: item.1.opacity(0.5), radius: 8, y: 3)
    }
}

private struct OnboardingPermissions: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(alignment: .center, spacing: PocketSpacing.l) {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("İzinler").font(.system(size: 26, weight: .bold))
                    Text("Her izin isteğe bağlı; eksik olan yalnız onu kullanan aracı etkiler. Durum canlı güncellenir.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PocketSpacing.m)
                progressRing
            }
            .padding(.horizontal, PocketSpacing.xxl)
            ScrollView {
                VStack(spacing: PocketSpacing.s) {
                    ForEach(model.permissions) { permission in
                        OnboardingPermissionRow(permission: permission, state: model.state(permission), usage: model.usage(permission),
                                                audioOnlyNote: permission == .screenRecording && model.availableModules.contains(.mixer),
                                                requested: model.requested.contains(permission),
                                                request: { model.request(permission) })
                    }
                    OnboardingHelperCard()
                    if model.relaunchSuggested {
                        HStack(spacing: PocketSpacing.m) {
                            Image(systemName: "arrow.clockwise.circle.fill").font(.title2).foregroundStyle(.orange)
                            Text("İzni açtıysan macOS’un uygulaması için MacPocket’ı yeniden başlat; sihirbaz kaldığı yerden sürer.")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: PocketSpacing.s)
                            Button("Yeniden Başlat") { PocketRelaunch.relaunch() }
                        }
                        .pocketCard(padding: PocketSpacing.m)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Text("Sonradan değiştirmek için: Sistem Ayarları › Gizlilik ve Güvenlik. Bu sihirbaza Ayarlar › Genel’den yeniden ulaşabilirsin.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, PocketSpacing.xs)
                }
                .padding(.horizontal, PocketSpacing.xxl)
                .padding(.bottom, PocketSpacing.l)
                .animation(.easeOut(duration: 0.25), value: model.relaunchSuggested)
            }
        }
        .padding(.top, PocketSpacing.l)
    }

    private var progressRing: some View {
        let total = max(model.applicable.count, 1)
        let fraction = Double(model.grantedCount) / Double(total)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(PocketTheme.brandGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fraction)
            VStack(spacing: 0) {
                Text(verbatim: "\(model.grantedCount)/\(model.applicable.count)").font(.system(size: 15, weight: .bold)).monospacedDigit()
                Text("verildi").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "\(model.grantedCount) / \(model.applicable.count) izin verildi")))
    }
}

struct OnboardingPermissionRow: View {
    let permission: OnboardingPermission
    let state: OnboardingPermissionState
    let usage: PermissionUsage
    let audioOnlyNote: Bool
    let requested: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.m) {
            PocketIconTile(symbol: permission.symbol, tint: permission.tint, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(permission.title).font(.headline)
                    if permission.isRecommended && usage.isRelevant { PocketStatusBadge(text: "Önerilen", tone: .accent) }
                }
                Text(permission.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if usage.isRelevant {
                    Text(usage.activeTitles.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Bu izni kullanan etkin modül yok.").font(.caption).foregroundStyle(.secondary)
                }
                if !usage.inactiveModules.isEmpty {
                    DisclosureGroup("Kapalı modüller") {
                        Text(usage.inactiveModules.map(\.localizedTitle).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.caption)
                }
                if audioOnlyNote {
                    Text("Bu satır ekran kaydı iznini ölçer. Ses Mikseri sistem sesi iznini ilk yönlendirmede ayrıca denetler.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if requested && usage.isRelevant && !state.isGranted { hint }
            }
            Spacer(minLength: PocketSpacing.m)
            Group {
                if usage.isRelevant { trailing }
                else { Text(state.isGranted ? "Verildi · kullanılmıyor" : "Etkin araç yok").font(.caption).foregroundStyle(.secondary) }
            }.frame(minWidth: 112, alignment: .trailing)
        }
        .pocketCard(padding: PocketSpacing.m)
        .overlay {
            RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
                .strokeBorder(PocketTheme.disk.opacity(state.isGranted ? 0.55 : 0), lineWidth: 1.2)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: state)
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .granted:
            Label("Verildi", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(PocketTheme.disk)
                .transition(.scale.combined(with: .opacity))
        case .unavailable:
            PocketStatusBadge(text: "Bu derlemede yok", tone: .neutral)
        case .denied:
            Button("Ayarları Aç", action: request).buttonStyle(.pocketSecondary)
        case .notGranted:
            Button(permission.hasSystemPrompt ? "İzin Ver" : "Ayarlarda Aç", action: request).buttonStyle(.pocketPrimary)
        }
    }

    @ViewBuilder private var hint: some View {
        let text: LocalizedStringKey = if state == .denied {
            "Daha önce reddedildi; Sistem Ayarları’nda MacPocket’ın anahtarını aç."
        } else if permission.hasSystemPrompt {
            "macOS’un sorduğu pencerede İzin Ver’i seç."
        } else if permission.mayNeedRelaunch {
            "Listede MacPocket’ı aç; macOS yeniden başlatmanı isteyebilir."
        } else {
            "Sistem Ayarları’nda listede MacPocket’ı aç ya da kartı sürükleyip bırak."
        }
        Label(text, systemImage: "hand.point.right").font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OnboardingPreferences: View {
    @ObservedObject var loginItem: LoginItemController
    @AppStorage(MenuBarPreferences.visibleKey) private var showMenuBar = true
    @AppStorage("MacPocket.menuBarCPU") private var menuBarCPU = true
    @AppStorage(PocketPreferenceKey.showInDock) private var showInDock = true
    @AppStorage(PocketPreferenceKey.showWindowAtLaunch) private var showWindowAtLaunch = true
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Tercihler").font(.system(size: 26, weight: .bold))
                    Text("MacPocket’ın nerede ve ne zaman görüneceğini seç. Hepsi Ayarlar’dan değiştirilebilir.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    row("power", tint: PocketTheme.disk, title: "Oturum açıldığında başlat",
                        detail: loginItem.status == .requiresApproval ? "macOS onay bekliyor: Sistem Ayarları › Giriş Öğeleri." : "İzleme ve menü çubuğu Mac açılır açılmaz hazır olur.",
                        isOn: Binding(get: { loginItem.status.isRegistered }, set: { value in Task { await loginItem.setEnabled(value) } }))
                        .disabled(loginItem.isUpdating)
                    Divider().padding(.leading, 52)
                    row("menubar.rectangle", tint: PocketTheme.cobalt, title: "Menü çubuğunda göster",
                        detail: "Hızlı bakış, sistem değerleri ve kısayollar bir tık uzakta.",
                        isOn: Binding(get: { showMenuBar }, set: { showMenuBar = $0; PocketDock.apply() }))
                    Divider().padding(.leading, 52)
                    row("cpu", tint: PocketTheme.power, title: "Menü çubuğunda işlemci yüzdesi",
                        detail: "Simgenin yanında anlık işlemci kullanımı.", isOn: $menuBarCPU)
                        .disabled(!showMenuBar)
                    Divider().padding(.leading, 52)
                    row("dock.rectangle", tint: PocketTheme.brandSecondary, title: "Dock’ta göster",
                        detail: showMenuBar ? "Kapalıyken MacPocket’a menü çubuğundan ulaşırsın." : "Menü çubuğu öğesi kapalıyken Dock simgesi her zaman görünür.",
                        isOn: Binding(get: { showInDock }, set: { showInDock = $0; PocketDock.apply() }))
                        .disabled(!showMenuBar)
                    Divider().padding(.leading, 52)
                    row("macwindow", tint: Color(hex: 0x30B0C7), title: "Açılışta ana pencereyi göster",
                        detail: "Kapalıysa MacPocket yalnız menü çubuğunda başlar.", isOn: $showWindowAtLaunch)
                    if updates.isAvailable {
                        Divider().padding(.leading, 52)
                        row("arrow.down.circle", tint: PocketTheme.disk, title: "Güncellemeleri otomatik denetle",
                            detail: "Günde bir kez GitHub’daki imzalı sürüm listesine bakar; Mac hakkında bilgi gönderilmez.",
                            isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.automaticallyChecks = $0 }))
                    }
                }
                .pocketCard(padding: PocketSpacing.m)
                if let error = loginItem.error {
                    PocketMessage(error, tone: .warning)
                }
            }
            .padding(.horizontal, PocketSpacing.xxl)
            .padding(.vertical, PocketSpacing.l)
        }
    }

    private func row(_ symbol: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: PocketSpacing.m) {
            PocketIconTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: PocketSpacing.m)
            Toggle(isOn: isOn) { Text(title) }.toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, PocketSpacing.s)
    }
}

private struct OnboardingFinish: View {
    @ObservedObject var model: OnboardingModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: PocketSpacing.l) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(PocketTheme.disk.opacity(0.18)).frame(width: 130, height: 130)
                    .scaleEffect(appeared ? 1 : 0.6)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.white, PocketTheme.disk)
                    .symbolEffect(.bounce, value: appeared)
            }
            VStack(spacing: PocketSpacing.s) {
                Text("Hazırsın").font(.system(size: 34, weight: .bold))
                Text(String(localized: "\(model.grantedCount) / \(model.applicable.count) izin verildi. Eksik izinleri buradan ya da onu kullanan aracın içinden sonra da verebilirsin."))
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 540)
            }
            if !model.missing.isEmpty {
                VStack(alignment: .leading, spacing: PocketSpacing.s) {
                    ForEach(model.missing) { permission in
                        HStack(spacing: PocketSpacing.s) {
                            PocketIconTile(symbol: permission.symbol, tint: permission.tint, size: 24)
                            Text(permission.title).font(.callout.weight(.medium))
                            Spacer(minLength: PocketSpacing.m)
                            Button("Şimdi Ver") { model.request(permission) }.buttonStyle(.pocketSecondary).controlSize(.small)
                        }
                    }
                }
                .frame(width: 400)
                .pocketCard(padding: PocketSpacing.m)
            }
            HStack(spacing: PocketSpacing.l) {
                tip("menubar.arrow.up.rectangle", "Menü çubuğundaki simgeden hızlı bakış")
                tip("command", "⌘1–⌘7 ile bölümler arasında geç")
                tip("gearshape", "⌘, ile Ayarlar")
            }
            .padding(.top, PocketSpacing.s)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PocketSpacing.xxl)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true } }
    }

    private func tip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
    }
}

/// Installs MacPocket's privileged helper (fan control today) from the wizard: one administrator approval in
/// System Settings › Login Items, then no further prompts for the features it serves.
private struct OnboardingHelperCard: View {
    @ObservedObject private var fans = FanControlService.shared

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.m) {
            PocketIconTile(symbol: "gearshape.2.fill", tint: Color(hex: 0x636366), size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Yardımcı servis").font(.headline)
                Text("Fan kontrolü ve otomatik MAC taraması gibi yönetici yetkisi gereken işler için. Bir kez kurulur ve onaylanır.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if case .unavailable(let reason) = fans.availability {
                    Text(reason).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                } else if fans.availability == .needsApproval {
                    Label("Sistem Ayarları › Giriş Öğeleri’nde MacPocket’ın arka plan öğesini aç.", systemImage: "hand.point.right")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: PocketSpacing.m)
            Group {
                switch fans.availability {
                case .ready:
                    Label("Kuruldu", systemImage: "checkmark.circle.fill").font(.callout.weight(.semibold)).foregroundStyle(PocketTheme.disk)
                case .needsApproval:
                    Button("Onayla") { fans.openApproval() }.buttonStyle(.pocketPrimary)
                case .notInstalled:
                    Button("Kur") { fans.installHelper() }.buttonStyle(.pocketPrimary)
                case .unavailable:
                    PocketStatusBadge(text: "Kullanılamıyor", tone: .neutral)
                }
            }
            .frame(minWidth: 112, alignment: .trailing)
        }
        .pocketCard(padding: PocketSpacing.m)
        // One polling loop for the card's lifetime; a Timer publisher built in `body` restarts on every update.
        .task {
            while !Task.isCancelled {
                fans.refreshAvailability()
                do { try await Task.sleep(for: .seconds(1), tolerance: .milliseconds(250)) } catch { return }
            }
        }
    }
}
