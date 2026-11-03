import AppKit
import MacPocketCore
@preconcurrency import ScreenCaptureKit

/// MacPocket's screenshot tool: shortcuts, freezing the screens, capturing an area, window or screen with
/// ScreenCaptureKit, then saving, copying, the preview card and the history.
@MainActor
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    @Published var settings: ScreenshotSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            registerShortcuts()
        }
    }
    @Published private(set) var history: ScreenshotHistory
    /// Modes whose shortcut macOS refused or that macOS's own screenshot shortcuts also use.
    @Published private(set) var failedShortcuts: Set<ScreenshotMode> = []
    /// A screenshot app that takes over ⇧⌘3/4/5 while running (e.g. CleanShot X).
    @Published private(set) var conflictingApp: String?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    var recordingShortcut = false { didSet { registerShortcuts() } }

    private var hotKeys: [ScreenshotMode: PocketGlobalHotKey] = [:]
    private var overlay: ScreenshotSelectionOverlay?
    private static let previousAreaKey = "MacPocket.screenshot.previousArea"
    private static let historyURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacPocket", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("screenshot-history.json")
    }()

    private init() {
        settings = ScreenshotSettings.load(from: .standard)
        history = (try? Data(contentsOf: Self.historyURL)).flatMap { try? JSONDecoder().decode(ScreenshotHistory.self, from: $0) } ?? ScreenshotHistory()
        history.prune(now: Date()) { FileManager.default.fileExists(atPath: $0) }
    }

    func start() {
        registerShortcuts()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkConflicts() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkConflicts() }
        }
    }

    /// macOS's own screenshot shortcuts and screenshot apps aren't refused by `RegisterEventHotKey`; look them up.
    func checkConflicts() {
        let symbolic = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        let system = ScreenshotShortcutConflicts.system(settings.shortcuts, symbolicHotKeys: symbolic)
        failedShortcuts = failedRegistrations.union(system)
        conflictingApp = ScreenshotShortcutConflicts.runningApp(bundleIDs: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private var failedRegistrations: Set<ScreenshotMode> = []

    private func registerShortcuts() {
        var failed: Set<ScreenshotMode> = []
        for mode in ScreenshotMode.allCases {
            let hotKey = hotKeys[mode] ?? PocketGlobalHotKey { [weak self] in self?.capture(mode) }
            hotKeys[mode] = hotKey
            if let combo = settings.shortcuts[mode], !recordingShortcut {
                if !hotKey.register(combo) { failed.insert(mode) }
            } else {
                hotKey.unregister()
            }
        }
        failedRegistrations = failed
        checkConflicts()
    }

    var folder: URL {
        settings.folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func dismissMessage() { message = nil }

    // MARK: Capturing

    func capture(_ mode: ScreenshotMode) {
        guard !busy, overlay == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            message = String(localized: "Ekran görüntüsü almak için MacPocket’e Ekran Kaydı izni ver; sonra tekrar dene.")
            return
        }
        Task { await run(mode) }
    }

    private func run(_ mode: ScreenshotMode) async {
        busy = true
        defer { busy = false }
        do {
            switch mode {
            case .fullscreen:
                guard let display = Self.displayUnderPointer() else { return }
                let image = try await Self.captureDisplay(display)
                finish(image, mode: .fullscreen)
            case .previousArea:
                try await capturePreviousArea()
            case .area, .window, .allInOne:
                let screens = try await freezeScreens()
                let selection = await select(on: screens, mode: mode)
                try await handle(selection, screens: screens, mode: mode)
            }
        } catch {
            message = String(localized: "Ekran görüntüsü alınamadı: \(error.localizedDescription)")
        }
    }

    private func handle(_ selection: ScreenshotSelection?, screens: [FrozenScreen], mode: ScreenshotMode) async throws {
        switch selection {
        case nil:
            return
        case let .area(display, rect):
            guard let screen = screens.first(where: { $0.display == display }),
                  let pixels = ScreenshotGeometry.pixelRect(rect, scale: screen.scale, imageSize: CGSize(width: screen.image.width, height: screen.image.height)),
                  let crop = screen.image.cropping(to: pixels) else { return }
            savePreviousArea(display: display, rect: rect)
            finish(crop, mode: .area)
        case let .fullscreen(display):
            if let screen = screens.first(where: { $0.display == display }) { finish(screen.image, mode: .fullscreen) }
        case let .window(id):
            finish(try await Self.captureWindow(id), mode: .window)
        case .previousArea:
            try await capturePreviousArea(frozen: screens)
        }
    }

    private func select(on screens: [FrozenScreen], mode: ScreenshotMode) async -> ScreenshotSelection? {
        let overlay = ScreenshotSelectionOverlay(screens: screens, windows: Self.windowsOnScreen(), startInWindowMode: mode == .window,
                                                 showsModeBar: mode == .allInOne, hasPreviousArea: loadPreviousArea() != nil)
        self.overlay = overlay
        defer { self.overlay = nil }
        return await withCheckedContinuation { continuation in
            overlay.begin { continuation.resume(returning: $0) }
        }
    }

    private func capturePreviousArea(frozen: [FrozenScreen]? = nil) async throws {
        guard let previous = loadPreviousArea() else {
            message = String(localized: "Henüz önceki bir alan yok; önce bir alan seç.")
            return
        }
        let image: CGImage
        if let screen = frozen?.first(where: { $0.display == previous.display }) {
            image = screen.image
        } else {
            image = try await Self.captureDisplay(previous.display)
        }
        let scale = NSScreen.screens.first { $0.displayID == previous.display }?.backingScaleFactor ?? 2
        guard let pixels = ScreenshotGeometry.pixelRect(previous.rect, scale: scale, imageSize: CGSize(width: image.width, height: image.height)),
              let crop = image.cropping(to: pixels) else { return }
        finish(crop, mode: .previousArea)
    }

    // MARK: After capture

    private func finish(_ image: CGImage, mode: ScreenshotMode) {
        if settings.playSound { NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif", byReference: true)?.play() }
        let date = Date()
        let scale = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?.backingScaleFactor ?? 2
        var savedURL: URL?
        if settings.saveToFolder {
            savedURL = write(image, to: ScreenshotFiles.url(in: folder, at: date, prefix: String(localized: "Ekran Resmi"), format: settings.format) {
                FileManager.default.fileExists(atPath: $0.path)
            })
            if let savedURL {
                history.add(ScreenshotHistoryEntry(path: savedURL.path, date: date, mode: mode, pixelWidth: image.width, pixelHeight: image.height))
                saveHistory()
            }
        }
        if settings.copyToClipboard { copy(image, scale: scale) }
        if settings.showOverlay {
            ScreenshotQuickAccess.shared.show(ScreenshotCapture(image: image, scale: scale, fileURL: savedURL, date: date, mode: mode))
        }
    }

    /// Writes the image in the chosen format; nil (with a message) on failure.
    @discardableResult
    func write(_ image: CGImage, to url: URL) -> URL? {
        do {
            let data = try ScreenshotEncoder.encode(image, as: ScreenshotFormat(rawValue: url.pathExtension.lowercased()) ?? settings.format,
                                                   quality: settings.quality)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            message = String(localized: "Ekran görüntüsü kaydedilemedi: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves a capture that wasn't saved automatically (from the preview card); returns the file.
    func save(_ capture: ScreenshotCapture) -> URL? {
        if let url = capture.fileURL { return url }
        guard let url = write(capture.image, to: ScreenshotFiles.url(in: folder, at: capture.date, prefix: String(localized: "Ekran Resmi"),
                                                                    format: settings.format) { FileManager.default.fileExists(atPath: $0.path) })
        else { return nil }
        history.add(ScreenshotHistoryEntry(path: url.path, date: capture.date, mode: capture.mode, pixelWidth: capture.image.width,
                                           pixelHeight: capture.image.height))
        saveHistory()
        return url
    }

    /// A temporary file for dragging an unsaved capture into another app.
    func temporaryFile(for capture: ScreenshotCapture) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket Screenshots", isDirectory: true)
            .appendingPathComponent(ScreenshotFiles.url(in: URL(fileURLWithPath: "/"), at: capture.date, prefix: String(localized: "Ekran Resmi"),
                                                        format: settings.format) { _ in false }.lastPathComponent)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return write(capture.image, to: url)
    }

    func copy(_ image: CGImage, scale: CGFloat) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    func removeFromHistory(_ id: UUID) {
        history.remove(id)
        saveHistory()
    }

    /// Re-saves the history after an edit overwrote or added a file.
    func noteSaved(_ url: URL, image: CGImage, mode: ScreenshotMode) {
        history.add(ScreenshotHistoryEntry(path: url.path, date: Date(), mode: mode, pixelWidth: image.width, pixelHeight: image.height))
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: Self.historyURL, options: .atomic) }
    }

    // MARK: Previous area

    private struct PreviousArea: Codable { var display: CGDirectDisplayID; var rect: CGRect }

    private func savePreviousArea(display: CGDirectDisplayID, rect: CGRect) {
        if let data = try? JSONEncoder().encode(PreviousArea(display: display, rect: rect)) { UserDefaults.standard.set(data, forKey: Self.previousAreaKey) }
    }

    private func loadPreviousArea() -> PreviousArea? {
        guard let area = UserDefaults.standard.data(forKey: Self.previousAreaKey).flatMap({ try? JSONDecoder().decode(PreviousArea.self, from: $0) }),
              NSScreen.screens.contains(where: { $0.displayID == area.display }) else { return nil }
        return area
    }

    // MARK: ScreenCaptureKit

    private func freezeScreens() async throws -> [FrozenScreen] {
        var frozen: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let display = screen.displayID else { continue }
            frozen.append(FrozenScreen(display: display, frame: screen.frame, scale: screen.backingScaleFactor,
                                       image: try await Self.captureDisplay(display)))
        }
        return frozen
    }

    /// The display at native resolution, without the pointer and without MacPocket's screenshot chrome.
    static func captureDisplay(_ id: CGDirectDisplayID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noDisplay }
        let chrome = Set(NSApp.windows.filter { $0 is ScreenshotChrome && $0.isVisible }.map { CGWindowID($0.windowNumber) })
        let excluded = content.windows.filter { chrome.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// One window on its own, with its shadow and a transparent background.
    static func captureWindow(_ id: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = false
        configuration.shouldBeOpaque = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    enum CaptureError: LocalizedError {
        case noDisplay, noWindow
        var errorDescription: String? {
            switch self {
            case .noDisplay: String(localized: "Ekran bulunamadı.")
            case .noWindow: String(localized: "Pencere artık açık değil.")
            }
        }
    }

    /// Normal windows on screen, front to back, in AppKit global coordinates; MacPocket's chrome is left out.
    private static func windowsOnScreen() -> [FrozenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let chrome = Set(NSApp.windows.filter { $0 is ScreenshotChrome }.map { CGWindowID($0.windowNumber) })
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID, !chrome.contains(number),
                  let boundsInfo = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width > 40, bounds.height > 40,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return FrozenWindow(id: number, frame: NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height))
        }
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.displayID
    }
}

/// One capture handed to the preview card and the editor.
struct ScreenshotCapture: Identifiable {
    let id = UUID()
    var image: CGImage
    var scale: CGFloat
    var fileURL: URL?
    let date: Date
    let mode: ScreenshotMode
}

extension NSScreen {
    var displayID: CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}
