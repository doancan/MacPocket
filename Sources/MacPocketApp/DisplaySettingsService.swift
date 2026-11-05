import AppKit
import CoreGraphics
import MacPocketCore
import SwiftUI

/// Resolution, refresh rate, main display and mirroring for every connected display, including the HiDPI modes
/// System Settings hides. Every change is applied for the session first and asks "Keep this setting?" on the changed
/// display; without an answer it reverts after 15 seconds, so a blank or unreadable screen fixes itself.
@MainActor
final class DisplaySettingsService: ObservableObject {
    static let shared = DisplaySettingsService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("DisplaySettingsService")
    #endif
    private(set) var moduleRunning = false

    struct Display: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let isMain: Bool
        let isBuiltin: Bool
        let current: DisplayModeInfo
        let modes: [DisplayModeInfo]
        let mirroredFrom: CGDirectDisplayID?
        var native: (width: Int, height: Int)? { DisplayModeCatalog.nativePixels(modes) }
        static func == (lhs: Display, rhs: Display) -> Bool {
            lhs.id == rhs.id && lhs.current == rhs.current && lhs.isMain == rhs.isMain && lhs.modes == rhs.modes && lhs.mirroredFrom == rhs.mirroredFrom
        }
    }

    struct PendingChange {
        let display: CGDirectDisplayID
        let description: String
        let confirmation: DisplayChangeConfirmation
        let keep: () -> Void
        let revert: () -> Void
    }

    @Published private(set) var displays: [Display] = []
    @Published private(set) var pending: PendingChange?
    @Published private(set) var remaining = DisplayChangeConfirmation.seconds
    @Published private(set) var failure: String?
    @AppStorage("MacPocket.displays.showLowResolution") var showLowResolution = false

    private var cgModes: [CGDirectDisplayID: [Int32: CGDisplayMode]] = [:]
    private var countdown: Timer?
    private var observer: NSObjectProtocol?
    private let panel = DisplayConfirmationPanel()

    private init() {}

    func stopForModule() {
        moduleRunning = false
        revert()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        cgModes = [:]
        displays = []
    }

    func start() {
        guard !moduleRunning, PocketModule.displays.isAvailable() else { return }
        moduleRunning = true
        guard observer == nil else { return }
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                                          queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func refresh() {
        guard moduleRunning else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return }
        var result: [Display] = []
        var modeTable: [CGDirectDisplayID: [Int32: CGDisplayMode]] = [:]
        for id in ids.prefix(Int(count)) {
            guard let current = CGDisplayCopyDisplayMode(id) else { continue }
            let all = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
            var table: [Int32: CGDisplayMode] = [:]
            for mode in all { table[mode.ioDisplayModeID] = table[mode.ioDisplayModeID] ?? mode }
            table[current.ioDisplayModeID] = current
            modeTable[id] = table
            let mirror = CGDisplayMirrorsDisplay(id)
            result.append(Display(id: id, name: Self.name(of: id), isMain: CGDisplayIsMain(id) != 0, isBuiltin: CGDisplayIsBuiltin(id) != 0,
                                  current: Self.info(current), modes: all.map(Self.info), mirroredFrom: mirror == kCGNullDirectDisplay ? nil : mirror))
        }
        cgModes = modeTable
        displays = result.sorted { $0.isMain && !$1.isMain }
    }

    var isMirroring: Bool { displays.contains { $0.mirroredFrom != nil } }

    func resolutions(for display: Display) -> [DisplayResolution] {
        DisplayModeCatalog.resolutions(display.modes, includeLowResolution: showLowResolution)
    }

    // MARK: Changes

    func apply(_ mode: DisplayModeInfo, to display: Display) {
        guard pending == nil, mode != display.current,
              let target = cgModes[display.id]?[mode.id], let previous = cgModes[display.id]?[display.current.id] else { return }
        guard configure({ config in CGConfigureDisplayWithDisplayMode(config, display.id, target, nil) }, option: .forSession) else { return }
        let text = Self.describe(mode)
        begin(PendingChange(display: display.id, description: text, confirmation: DisplayChangeConfirmation(),
                            keep: { [weak self] in _ = self?.configure({ CGConfigureDisplayWithDisplayMode($0, display.id, target, nil) }, option: .permanently) },
                            revert: { [weak self] in _ = self?.configure({ CGConfigureDisplayWithDisplayMode($0, display.id, previous, nil) }, option: .forSession) }))
    }

    func makeMain(_ display: Display) {
        guard pending == nil, !display.isMain else { return }
        var origins: [UInt32: (x: Int32, y: Int32)] = [:]
        for item in displays { let bounds = CGDisplayBounds(item.id); origins[item.id] = (Int32(bounds.minX), Int32(bounds.minY)) }
        let moved = DisplayArrangement.originsMakingMain(display.id, origins: origins)
        _ = configure({ config in
            for (id, origin) in moved { CGConfigureDisplayOrigin(config, id, origin.x, origin.y) }
        }, option: .permanently)
    }

    func setMirroring(_ on: Bool) {
        guard pending == nil, let main = displays.first(where: \.isMain) else { return }
        let others = displays.filter { !$0.isMain }.map(\.id)
        guard configure({ config in
            for id in others { CGConfigureDisplayMirrorOfDisplay(config, id, on ? main.id : kCGNullDirectDisplay) }
        }, option: .forSession) else { return }
        begin(PendingChange(display: main.id, description: on ? String(localized: "Ekranlar yansıtılıyor") : String(localized: "Yansıtma kapalı"),
                            confirmation: DisplayChangeConfirmation(),
                            keep: { [weak self] in _ = self?.configure({ config in
                                for id in others { CGConfigureDisplayMirrorOfDisplay(config, id, on ? main.id : kCGNullDirectDisplay) } }, option: .permanently) },
                            revert: { [weak self] in _ = self?.configure({ config in
                                for id in others { CGConfigureDisplayMirrorOfDisplay(config, id, on ? kCGNullDirectDisplay : main.id) } }, option: .forSession) }))
    }

    func keep() {
        guard let change = pending else { return }
        finish()
        change.keep()
        refresh()
    }

    func revert() {
        guard let change = pending else { return }
        finish()
        change.revert()
        refresh()
    }

    func dismissFailure() { failure = nil }

    private func begin(_ change: PendingChange) {
        pending = change
        remaining = DisplayChangeConfirmation.seconds
        refresh()
        // Show the question once the display has settled into the new mode.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.pending != nil else { return }
            self.panel.show(on: change.display)
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let change = self.pending else { return }
                let now = Date()
                self.remaining = change.confirmation.remaining(at: now)
                if change.confirmation.expired(at: now) { self.revert() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    private func finish() {
        countdown?.invalidate()
        countdown = nil
        pending = nil
        panel.hide()
    }

    private func configure(_ body: (CGDisplayConfigRef) -> Void, option: CGConfigureOption) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            failure = String(localized: "Ekran ayarı değiştirilemedi.")
            return false
        }
        body(config)
        let status = CGCompleteDisplayConfiguration(config, option)
        if status != .success {
            failure = String(localized: "Ekran ayarı değiştirilemedi (\(status.rawValue)).")
            return false
        }
        return true
    }

    // MARK: Helpers

    static func info(_ mode: CGDisplayMode) -> DisplayModeInfo {
        DisplayModeInfo(id: mode.ioDisplayModeID, width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
                        pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate, usableForDesktop: mode.isUsableForDesktopGUI())
    }

    static func describe(_ mode: DisplayModeInfo) -> String {
        var text = "\(mode.width) × \(mode.height)"
        if mode.isHiDPI { text += " · HiDPI" }
        if mode.refreshRate > 0 { text += " · \(mode.roundedRefresh) Hz" }
        return text
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { $0.displayID == id }?.localizedName ?? String(localized: "Ekran \(id)")
    }
}

// MARK: - Confirmation panel

/// "Keep this display setting?" on the changed screen itself, so it can be answered even if the main window is elsewhere.
@MainActor
private final class DisplayConfirmationPanel {
    private var panel: NSPanel?

    func show(on display: CGDirectDisplayID) {
        let screen = NSScreen.screens.first { $0.displayID == display } ?? NSScreen.main
        guard let screen else { return }
        let panel = self.panel ?? {
            let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150), styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .modalPanel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: DisplayConfirmationView(service: DisplaySettingsService.shared))
            return panel
        }()
        self.panel = panel
        let size = NSSize(width: 380, height: 150)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() { panel?.orderOut(nil) }

    private final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }
}

private struct DisplayConfirmationView: View {
    @ObservedObject var service: DisplaySettingsService

    var body: some View {
        VStack(spacing: PocketSpacing.m) {
            Text("Bu ekran ayarı kalsın mı?").font(.headline)
            if let change = service.pending {
                Text(verbatim: change.description).font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: PocketSpacing.m) {
                Button("Geri Al (\(service.remaining))") { service.revert() }
                    .keyboardShortcut(.cancelAction)
                Button("Kalsın") { service.keep() }
                    .buttonStyle(.pocketPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(PocketSpacing.l)
        .frame(width: 360)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
extension DisplaySettingsService {
    var moduleDiagnosticResources: [String: Int] { ["observer": observer == nil ? 0 : 1, "timer": countdown?.isValid == true ? 1 : 0, "pending": pending == nil ? 0 : 1] }
}
#endif
