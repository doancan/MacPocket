import Foundation

/// Bounded capture work for a switcher viewport. Selection takes precedence over the batch limit;
/// scrolling requests the newly visible cards instead of repeatedly capturing the first page.
public enum WindowThumbnailPlan {
    public static func targets(_ windows: [SwitchableWindow], selection: String?, visibleIDs: Set<String>,
                               limit: Int = 48) -> [SwitchableWindow] {
        guard limit > 0 else { return [] }
        let eligible = windows.filter { $0.windowID != nil && !$0.minimized }
        var result: [SwitchableWindow] = []
        var included = Set<String>()
        func append(_ window: SwitchableWindow) {
            if result.count < limit, included.insert(window.id).inserted { result.append(window) }
        }
        if let selected = eligible.first(where: { $0.id == selection }) { append(selected) }
        if visibleIDs.isEmpty {
            for window in eligible { append(window) }
        } else {
            for window in eligible where visibleIDs.contains(window.id) { append(window) }
        }
        return result
    }
}
