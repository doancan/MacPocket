import AppKit
import ApplicationServices
import MacPocketCore

/// Global shortcuts that move and resize the focused window.
@MainActor
final class WindowLayoutService: ObservableObject {
    static let shared = WindowLayoutService()

    @Published var settings: WindowLayoutSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            registerShortcuts()
        }
    }
    /// Shortcuts macOS refused (usually taken by another app).
    @Published private(set) var refused: [WindowLayoutAction] = []
    @Published private(set) var message: String?
    /// Suspends every shortcut while one is being recorded in Settings.
    var recording = false { didSet { registerShortcuts() } }

    private var hotKeys: [WindowLayoutAction: PocketGlobalHotKey] = [:]
    private var lastPress: (action: WindowLayoutAction, step: Int, at: Date, window: FocusedWindow)?
    /// Frames before each change, newest last, so Restore can step back. Bounded.
    private var undo: [(window: FocusedWindow, frame: CGRect)] = []
    private static let undoLimit = 50

    private init() {
        settings = WindowLayoutSettings.load(from: .standard)
    }

    func start() { registerShortcuts() }

    private func registerShortcuts() {
        let active = settings.enabled && !recording
        let conflicts = Set(settings.conflicts)
        var refused: [WindowLayoutAction] = []
        for action in WindowLayoutAction.allCases {
            let hotKey = hotKeys[action] ?? PocketGlobalHotKey { [weak self] in self?.perform(action) }
            hotKeys[action] = hotKey
            guard active, !conflicts.contains(action), let combo = settings.shortcut(for: action) else {
                hotKey.unregister()
                continue
            }
            if !hotKey.register(combo) { refused.append(action) }
        }
        self.refused = refused
    }

    // MARK: Performing

    func perform(_ action: WindowLayoutAction) {
        guard AXIsProcessTrusted() else {
            message = String(localized: "Pencereleri taşımak için MacPocket’e Erişilebilirlik izni ver.")
            return
        }
        guard let window = FocusedWindow.current(), let axFrame = window.frame,
              let primaryHeight = NSScreen.screens.first?.frame.maxY else {
            NSSound.beep()
            return
        }
        let frame = WindowLayoutGeometry.flip(axFrame, primaryHeight: primaryHeight)
        guard let screen = Self.screen(for: frame) else { return }

        if action == .restore {
            guard let index = undo.lastIndex(where: { $0.window.isSame(as: window) }) else { NSSound.beep(); return }
            let previous = undo.remove(at: index).frame
            window.setFrame(WindowLayoutGeometry.flip(previous, primaryHeight: primaryHeight))
            lastPress = nil
            return
        }

        let target: CGRect?
        switch action {
        case .nextDisplay, .previousDisplay:
            lastPress = nil
            target = Self.neighbour(of: screen, forward: action == .nextDisplay)
                .map { WindowLayoutGeometry.move(frame, from: screen.visibleFrame, to: $0.visibleFrame) }
        default:
            let previous = lastPress.flatMap { $0.window.isSame(as: window) ? ($0.action, $0.step, $0.at) : nil }
            let step = WindowLayoutGeometry.nextStep(previous: previous, action: action, now: Date(), cycling: settings.cycleOnRepeat)
            target = WindowLayoutGeometry.frame(for: action, in: screen.visibleFrame, gap: settings.gap, step: step, current: frame)
            lastPress = (action, step, Date(), window)
        }
        guard let target else { NSSound.beep(); return }
        remember(window, frame)
        if !window.setFrame(WindowLayoutGeometry.flip(target, primaryHeight: primaryHeight)) {
            message = String(localized: "Bu pencere taşınmaya veya yeniden boyutlandırılmaya izin vermiyor.")
        }
    }

    private func remember(_ window: FocusedWindow, _ frame: CGRect) {
        // A cycle of repeated presses counts as one change: keep only the frame before the first press.
        if let last = undo.last, last.window.isSame(as: window), lastPress.map({ $0.step > 0 }) == true { return }
        undo.append((window, frame))
        if undo.count > Self.undoLimit { undo.removeFirst(undo.count - Self.undoLimit) }
    }

    /// The screen holding most of the window.
    private static func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area } ?? NSScreen.main
    }

    /// Screens ordered left to right (then top to bottom), wrapping around.
    private static func neighbour(of screen: NSScreen, forward: Bool) -> NSScreen? {
        let ordered = NSScreen.screens.sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
        guard ordered.count > 1, let index = ordered.firstIndex(of: screen) else { return nil }
        return ordered[(index + (forward ? 1 : ordered.count - 1)) % ordered.count]
    }

    func dismissMessage() { message = nil }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
