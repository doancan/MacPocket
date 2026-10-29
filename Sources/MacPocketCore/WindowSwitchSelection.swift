import Foundation

/// Selection uses the foreground PID captured BEFORE our panel takes focus.
public enum WindowSwitchSelection {
    public static func initial(_ windows: [SwitchableWindow], foregroundPID: Int32?, backwards: Bool, queuedSteps: Int = 0) -> String? {
        guard !windows.isEmpty else { return nil }
        let start: Int
        if let foregroundPID, let index = windows.firstIndex(where: { $0.processID == foregroundPID }) {
            start = index + (backwards ? -1 : 1)
        } else { start = backwards ? windows.count - 1 : 0 }
        let count = windows.count
        let index = ((start + queuedSteps % count) % count + count) % count
        return windows[index].id
    }
}
