import AppKit
import Combine
import MacPocketAIUsage
import MacPocketCore
import SwiftUI
import UserNotifications

/// UI lifecycle and account login are owned by MacPocket. UsageCore never launches a paid prompt.
@MainActor
final class AIUsageIntegration: NSObject {
    static let shared = AIUsageIntegration()
    let service = AIUsageService.shared
    private var floating: AIUsageFloatingPanel?
    private var pendingLogins = Set<UUID>()
    private var activationObserver: NSObjectProtocol?
    var openSettingsWindow: (() -> Void)?

    private override init() {
        super.init()
        service.onAlerts = { [weak self] notices in self?.post(notices) }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finishPendingLogin() }
            }
    }

    func configure(preferences: MenuBarPreferences) {
        let wanted = (preferences.enabled.contains(.aiUsage) && preferences.visible) || service.settings.floatingPanel
        service.setEnabled(wanted)
        if wanted && service.settings.floatingPanel {
            if floating == nil { floating = AIUsageFloatingPanel(service: service) }
            floating?.show(horizontal: service.settings.floatingHorizontal)
        } else { floating?.hide() }
    }
    func stop() { floating?.hide(); service.stop() }

    func enableMenuBar() {
        var preferences = MenuBarSettingsStore.shared.preferences
        preferences.enabled.insert(.aiUsage)
        preferences.visible = true
        MenuBarSettingsStore.shared.preferences = preferences
        configure(preferences: preferences)
    }

    func beginClaudeLogin(_ account: AIUsageAccount) throws {
        #if DEBUG
        if AIUsageFixtures.requested { throw CocoaError(.userCancelled) }
        #endif
        guard case .claudeProfile(let directory, _) = account.source else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The script contains only an environment path and a fixed CLI command, never credentials.
        let scripts = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/MacPocket/AIUsage/Login")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = scripts.appending(path: "claude-\(account.id.uuidString).command")
        let text = ClaudeProfileLogin.script(directory: directory)
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        guard NSWorkspace.shared.open(script) else { throw CocoaError(.fileReadUnknown) }
        pendingLogins.insert(account.id)
    }
    private func finishPendingLogin() {
        guard !pendingLogins.isEmpty else { return }
        let services = AIUsageCredentials.claudeEntries()
        for id in pendingLogins {
            guard var account = service.settings.accounts.first(where: { $0.id == id }),
                  case .claudeProfile(let directory, let existing) = account.source else {
                pendingLogins.remove(id)
                continue
            }
            // Bind only this directory's expected namespace. An unrelated new keychain entry
            // is never sufficient evidence of account ownership, including concurrent logins.
            let expected = AIUsageCredentials.claudeServiceCandidate(directory: directory)
            let resolved = services.first { $0.service == expected }?.service ?? existing
            let file = URL(fileURLWithPath: directory).appending(path: ".credentials.json")
            guard resolved != nil || FileManager.default.fileExists(atPath: file.path) else { continue }
            account.source = .claudeProfile(directory: directory, service: resolved)
            service.update(account)
            pendingLogins.remove(id)
            Task { await service.refresh(manual: true, only: id) }
        }
    }

    func requestAlerts() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    private func post(_ notices: [AIUsageNotice]) {
        for notice in notices {
            let content = UNMutableNotificationContent()
            content.title = notice.level == .critical ? String(localized: "AI kotası kritik seviyede") : String(localized: "AI kota uyarısı")
            let percent = AIUsageService.percent(notice.limit.percentUsed)
            let label = AIUsageText.limitTitle(notice.limit)
            content.body = String(localized: "\(notice.accountName): \(label) kotasının \(percent) kullanıldı.")
            let request = UNNotificationRequest(identifier: "MacPocket.aiUsage.\(notice.accountID).\(notice.limit.id).\(notice.level.rawValue)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }
    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
        NSPasteboard.general.setString(service.diagnostics(), forType: .string)
    }
}

private final class AIUsagePanelWindow: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor
private final class AIUsageFloatingPanel: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let service: AIUsageService
    private var horizontal: Bool?
    private var accountCount = 0
    init(service: AIUsageService) {
        self.service = service
        panel = AIUsagePanelWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 260),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = String(localized: "AI Kotaları")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrameAutosaveName("MacPocket.AIUsage.floating")
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: AIUsageFloatingView(service: service).pocketAppearanceRoot(rebuildsOnTokenChange: false))
        if !panel.setFrameUsingName("MacPocket.AIUsage.floating") { panel.center() }
    }
    func show(horizontal: Bool) {
        let count = max(1, service.enabledAccounts.count)
        if self.horizontal != horizontal || accountCount != count {
            self.horizontal = horizontal
            accountCount = count
            let size = horizontal ? NSSize(width: CGFloat(min(860, max(220, count * 159 + 47))), height: 88)
                                  : NSSize(width: 96, height: CGFloat(min(720, max(152, 40 + count * 121))))
            panel.setContentSize(size)
            if let screen = panel.screen ?? NSScreen.main {
                var frame = panel.frame
                frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
                panel.setFrame(frame, display: true)
            }
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() { panel.orderOut(nil) }
    func windowWillClose(_ notification: Notification) {
        var settings = service.settings
        settings.floatingPanel = false
        service.setSettings(settings)
    }
}
