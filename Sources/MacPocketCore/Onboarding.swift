import CoreGraphics
import Foundation

/// The privacy permissions the first-run wizard walks through. Each one is optional: only the tools that use it
/// are affected when it is missing.
public enum OnboardingPermission: String, CaseIterable, Identifiable, Sendable {
    case accessibility, screenRecording, fullDiskAccess, inputMonitoring, location, notifications

    public var id: String { rawValue }

    /// The System Settings pane that holds the switch.
    public func settingsURL(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> URL {
        let anchor = switch self {
        case .accessibility: "com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording: "com.apple.preference.security?Privacy_ScreenCapture"
        case .fullDiskAccess: "com.apple.preference.security?Privacy_AllFiles"
        case .inputMonitoring: "com.apple.preference.security?Privacy_ListenEvent"
        case .location: "com.apple.preference.security?Privacy_LocationServices"
        case .notifications: "com.apple.Notifications-Settings.extension" + (bundleIdentifier.map { "?id=\($0)" } ?? "")
        }
        return URL(string: "x-apple.systempreferences:" + anchor)!
    }

    /// Panes with an app list that accepts a dragged app bundle; the wizard floats a drag card beside them.
    public var acceptsDraggedApp: Bool {
        switch self {
        case .accessibility, .screenRecording, .fullDiskAccess, .inputMonitoring: true
        case .location, .notifications: false
        }
    }

    /// Asked by macOS itself with a dialog the first time; the others are switched on in System Settings.
    public var hasSystemPrompt: Bool { self == .location || self == .notifications }

    /// macOS applies these to a running process only after a relaunch.
    public var mayNeedRelaunch: Bool { self == .screenRecording || self == .inputMonitoring }

    /// Shown first and marked "Recommended": they unlock the most tools.
    public var isRecommended: Bool { self == .accessibility || self == .fullDiskAccess }
}

public enum OnboardingPermissionState: Equatable, Sendable {
    case granted, notGranted, denied, unavailable

    public var isGranted: Bool { self == .granted }
}

public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome, permissions, preferences, finish

    public var id: Int { rawValue }
    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    public var isFirst: Bool { previous == nil }
    public var isLast: Bool { next == nil }
}

/// Whether the wizard still has to be shown, and where an interrupted run (a relaunch for a permission) resumes.
public enum OnboardingRecord {
    /// Bumped when the wizard gains a step every user should see once.
    public static let currentVersion = 1
    static let completedKey = "MacPocket.onboarding.completedVersion"
    static let resumeKey = "MacPocket.onboarding.resumeStep"

    public static func needsPresentation(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: completedKey) < currentVersion
    }

    public static func markCompleted(_ defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: completedKey)
        defaults.removeObject(forKey: resumeKey)
    }

    public static func resumeStep(_ defaults: UserDefaults = .standard) -> OnboardingStep {
        guard defaults.object(forKey: resumeKey) != nil else { return .welcome }
        return OnboardingStep(rawValue: defaults.integer(forKey: resumeKey)) ?? .welcome
    }

    public static func saveResumeStep(_ step: OnboardingStep, _ defaults: UserDefaults = .standard) {
        defaults.set(step.rawValue, forKey: resumeKey)
    }
}

/// macOS has no API that reports Full Disk Access; reading a file it protects is the accepted check.
public enum FullDiskAccessProbe {
    public static var protectedFiles: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/Library/Application Support/com.apple.TCC/TCC.db",
                home + "/Library/Safari/Bookmarks.plist",
                "/Library/Application Support/com.apple.TCC/TCC.db"]
    }

    /// True when any of the files exists and opens for reading. Files that don't exist prove nothing.
    public static func granted(checking paths: [String] = protectedFiles) -> Bool {
        paths.contains { path in
            let descriptor = open(path, O_RDONLY)
            guard descriptor >= 0 else { return false }
            close(descriptor)
            return true
        }
    }
}

/// Where the floating "drag MacPocket here" card goes next to the System Settings window. All rectangles use
/// AppKit's bottom-left screen coordinates.
public enum PermissionHelperPlacement {
    public static func frame(panel size: CGSize, beside window: CGRect, within screen: CGRect, gap: CGFloat = 12) -> CGRect {
        // Right of the window, aligned to its top: the list the app is dropped on sits on the right half.
        let right = CGRect(x: window.maxX + gap, y: window.maxY - size.height, width: size.width, height: size.height)
        if screen.contains(right) { return right }
        // Below the window, centred.
        let below = CGRect(x: window.midX - size.width / 2, y: window.minY - gap - size.height, width: size.width, height: size.height)
        if screen.contains(below) { return below }
        // Left of the window.
        let left = CGRect(x: window.minX - gap - size.width, y: window.maxY - size.height, width: size.width, height: size.height)
        if screen.contains(left) { return left }
        // No room outside: overlap the window's bottom-right corner, kept on screen.
        var inside = CGRect(x: window.maxX - size.width - gap, y: window.minY + gap, width: size.width, height: size.height)
        inside.origin.x = min(max(inside.minX, screen.minX), screen.maxX - size.width)
        inside.origin.y = min(max(inside.minY, screen.minY), screen.maxY - size.height)
        return inside
    }

    /// CGWindowList bounds are top-left based on the primary display; AppKit is bottom-left.
    public static func appKitRect(fromWindowList bounds: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: primaryScreenHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }
}
