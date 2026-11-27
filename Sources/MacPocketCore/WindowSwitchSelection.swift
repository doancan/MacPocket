import Foundation

public enum WindowNavigationIntent: Equatable, Sendable {
    case linear(Int)
    case row(backwards: Bool)
}

/// Selection uses the foreground PID captured BEFORE our panel takes focus.
public enum WindowSwitchSelection {
    /// Rows wrap, while an incomplete destination row clamps to its closest available column.
    /// Avoid count + columns arithmetic so even extreme diagnostic inputs cannot overflow.
    public static func rowDestination(index: Int, windowCount: Int, columns: Int, backwards: Bool) -> Int? {
        guard windowCount > 0 else { return nil }
        let width = min(windowCount, max(1, columns))
        let remainder = index % windowCount
        let current = remainder < 0 ? remainder + windowCount : remainder
        let rows = (windowCount - 1) / width + 1, row = current / width, column = current % width
        let targetRow = backwards ? (row == 0 ? rows - 1 : row - 1) : (row == rows - 1 ? 0 : row + 1)
        let start = targetRow * width
        return start + min(column, windowCount - start - 1)
    }

    /// Replay ordered intent against the fresh list and its current layout. Collapsing an up/down
    /// press into a numeric offset loses the column when a row is incomplete or the list changes.
    public static func applying(_ intents: [WindowNavigationIntent], to windows: [SwitchableWindow], preserving id: String?, columns: Int) -> String? {
        guard !windows.isEmpty else { return nil }
        var index = windows.firstIndex { $0.id == id } ?? 0
        for intent in intents {
            switch intent {
            case .linear(let step):
                let delta = step % windows.count
                index = ((index + delta) % windows.count + windows.count) % windows.count
            case .row(let backwards): index = rowDestination(index: index,windowCount: windows.count,columns: columns,backwards: backwards) ?? index
            }
        }
        return windows[index].id
    }

    /// Rebuild a live session after its Space/display changes. Preserve the selected target when
    /// still eligible; otherwise start at the first new result. Queued input is applied once.
    public static func refreshed(_ windows: [SwitchableWindow], preserving id: String?, queuedSteps: Int = 0) -> String? {
        guard !windows.isEmpty else { return nil }
        let count = windows.count
        let anchor = windows.firstIndex { $0.id == id } ?? 0
        return windows[((anchor + queuedSteps % count) % count + count) % count].id
    }

    public static func initial(_ windows: [SwitchableWindow], foregroundPID: Int32?, backwards: Bool, queuedSteps: Int = 0) -> String? {
        guard !windows.isEmpty else { return nil }
        let start: Int
        if let foregroundPID,
           let index = windows.firstIndex(where: { $0.processID == foregroundPID && $0.frontmost })
            ?? windows.firstIndex(where: { $0.processID == foregroundPID }) {
            start = index + (backwards ? -1 : 1)
        } else { start = backwards ? windows.count - 1 : 0 }
        let count = windows.count
        let index = ((start + queuedSteps % count) % count + count) % count
        return windows[index].id
    }
}
