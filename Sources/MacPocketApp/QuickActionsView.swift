import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class QuickActionService: ObservableObject {
    static let shared = QuickActionService()

    struct Outcome: Equatable {
        let text: String
        let tone: PocketTone
    }

    @Published private(set) var running: QuickAction?
    @Published private(set) var outcome: Outcome?

    private init() {}

    func perform(_ action: QuickAction, completion: (@MainActor (Outcome?) -> Void)? = nil) {
        guard running == nil else {
            completion?(Outcome(text: String(localized: "Devam eden hızlı işlemin bitmesini bekle."), tone: .warning))
            return
        }
        running = action
        outcome = nil
        Task {
            let result = await Self.run(action)
            running = nil
            outcome = result
            completion?(result)
        }
    }

    func dismiss() { outcome = nil }

    private static func run(_ action: QuickAction) async -> Outcome? {
        switch action {
        case .lockScreen:
            if lockScreen() { return nil }
            return run("/usr/bin/pmset", ["displaysleepnow"])
        case .sleepDisplay:
            return run("/usr/bin/pmset", ["displaysleepnow"])
        case .sleepMac:
            return run("/usr/bin/pmset", ["sleepnow"])
        case .toggleDarkMode:
            return await appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
                                     success: nil)
        case .toggleDesktopIcons:
            return await toggleDesktopIcons()
        case .ejectDisks:
            return ejectDisks()
        case .emptyTrash:
            return await appleScript("tell application \"Finder\" to empty trash", success: String(localized: "Çöp boşaltıldı."))
        }
    }

    /// The login framework's immediate lock, the same call the menu bar lock item uses.
    private static func lockScreen() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias Lock = @convention(c) () -> Int32
        return unsafeBitCast(symbol, to: Lock.self)() == 0
    }

    private static func run(_ path: String, _ arguments: [String]) -> Outcome? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? nil
                : Outcome(text: String(localized: "İşlem tamamlanamadı (\(process.terminationStatus))."), tone: .warning)
        } catch {
            return Outcome(text: error.localizedDescription, tone: .warning)
        }
    }

    /// Through osascript, off the main thread with a time limit, so a busy Finder can't stall MacPocket.
    private static func appleScript(_ source: String, success: String?) async -> Outcome? {
        let result: BoundedProcess.Result
        do {
            result = try await BoundedProcess.run("/usr/bin/osascript", ["-e", source], timeout: 60)
        } catch {
            return Outcome(text: error.localizedDescription, tone: .warning)
        }
        guard result.status != 0 else { return success.map { Outcome(text: $0, tone: .success) } }
        if result.errorOutput.contains("-1743") {
            return Outcome(text: String(localized: "macOS izin vermedi. Sistem Ayarları › Gizlilik ve Güvenlik › Otomasyon’da MacPocket’e izin ver."),
                           tone: .warning)
        }
        if result.errorOutput.contains("-128") { return nil } // the user cancelled Finder's own confirmation
        let message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return Outcome(text: message.isEmpty ? String(localized: "İşlem tamamlanamadı.") : message, tone: .warning)
    }

    private static func toggleDesktopIcons() async -> Outcome? {
        let shown = desktopIconsVisible
        do { try await setDesktopIcons(visible: !shown) } catch { return Outcome(text: error.localizedDescription, tone: .warning) }
        return Outcome(text: shown ? String(localized: "Masaüstü simgeleri gizlendi.") : String(localized: "Masaüstü simgeleri gösteriliyor."),
                       tone: .success)
    }

    static var desktopIconsVisible: Bool {
        (SystemHiddenSettingsStore().read("CreateDesktop", domain: .finder) as? NSNumber)?.boolValue ?? true
    }

    /// Showing again deletes the key, leaving Finder exactly as macOS ships it. Restarts Finder.
    static func setDesktopIcons(visible: Bool) async throws {
        guard SystemHiddenSettingsStore().write(visible ? nil : .bool(false), key: "CreateDesktop", domain: .finder) else {
            throw NSError(domain: "MacPocket.desktop", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Finder ayarı kaydedilemedi.")])
        }
        try await KillallRestarter().restart(.finder)
    }

    static func ejectableVolumes() -> [MountedVolume] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey,
                                      .volumeIsRootFileSystemKey, .volumeLocalizedNameKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return MountedVolume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent,
                                 isEjectable: values.volumeIsEjectable ?? false, isRemovable: values.volumeIsRemovable ?? false,
                                 isInternal: values.volumeIsInternal ?? true, isRoot: values.volumeIsRootFileSystem ?? false)
        }
        .filter(\.canEject)
    }

    private static func ejectDisks() -> Outcome {
        let volumes = ejectableVolumes()
        guard !volumes.isEmpty else { return Outcome(text: String(localized: "Çıkarılacak disk yok."), tone: .neutral) }
        var busy: [String] = []
        for volume in volumes {
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url) } catch { busy.append(volume.name) }
        }
        let ejected = volumes.count - busy.count
        if busy.isEmpty { return Outcome(text: String(localized: "\(ejected) disk çıkarıldı."), tone: .success) }
        return Outcome(text: String(localized: "\(ejected) disk çıkarıldı; kullanımda olduğu için çıkarılamayan: \(busy.joined(separator: ", "))."),
                       tone: .warning)
    }
}

/// Tools → Hızlı İşlemler: one-click system actions in a grid of equal tiles.
struct QuickActionsView: View {
    @ObservedObject private var service = QuickActionService.shared
    @State private var confirming: QuickAction?
    @State private var volumes = QuickActionService.ejectableVolumes()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Hızlı İşlemler", subtitle: "Sık yapılan sistem işlemlerini tek tıkla çalıştır.", icon: "bolt.circle")
                if let outcome = service.outcome { PocketMessage(outcome.text, tone: outcome.tone) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: PocketSpacing.m)], spacing: PocketSpacing.m) {
                    ForEach(QuickAction.allCases) { action in
                        QuickActionTile(action: action, running: service.running == action,
                                        detail: action == .ejectDisks ? ejectDetail : action.detail) {
                            action.needsConfirmation ? (confirming = action) : service.perform(action)
                        }
                        .disabled(service.running != nil || (action == .ejectDisks && volumes.isEmpty))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .pocketPage()
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in volumes = QuickActionService.ejectableVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in volumes = QuickActionService.ejectableVolumes() }
        .confirmationDialog(confirming?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            if let action = confirming {
                Button(action.title, role: action == .emptyTrash ? .destructive : nil) { service.perform(action) }
            }
        } message: {
            Text(confirming == .emptyTrash ? "Çöp’teki öğeler kalıcı olarak silinir; geri alınamaz." : "Açık işler uyku boyunca bekler.")
        }
    }

    private var ejectDetail: String {
        volumes.isEmpty ? String(localized: "Takılı harici disk yok.")
            : String(localized: "Çıkarılacak: \(volumes.map(\.name).joined(separator: ", "))")
    }
}

private struct QuickActionTile: View {
    let action: QuickAction
    let running: Bool
    let detail: String
    let perform: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        Button(action: perform) {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                ZStack {
                    PocketIconTile(symbol: action.symbol, tint: action.tint, size: PocketIconSize.item)
                    if running { ProgressView().controlSize(.small).tint(.white) }
                }
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(action.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pocketCard()
        .overlay {
            let shape = RoundedRectangle(cornerRadius: PocketRadius.large, style: .continuous)
            let lit = hovering && isEnabled
            shape.fill(action.tint.opacity(lit ? 0.06 : 0))
                .overlay { shape.strokeBorder(action.tint.opacity(lit ? 0.5 : 0), lineWidth: 1) }
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .opacity(isEnabled ? 1 : 0.55)
        .onHover { hovering = $0 }
        .accessibilityHint(Text(detail))
    }
}

extension QuickAction {
    var tint: Color {
        switch self {
        case .lockScreen: Color(hex: 0x5F6B7E)
        case .sleepDisplay: PocketTheme.brand
        case .sleepMac: Color(hex: 0x5B4BFF)
        case .toggleDarkMode: Color(hex: 0x2C2C34)
        case .toggleDesktopIcons: Color(hex: 0x00A6C8)
        case .ejectDisks: PocketTheme.disk
        case .emptyTrash: Color(hex: 0xF2545B)
        }
    }
}
