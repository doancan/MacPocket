import CoreGraphics
import Foundation

public struct WindowTabInfo: Sendable {
    public let groupID: String
    public let controlID: String
    public let ordinal: Int
    public let count: Int
    public let selected: Bool
    public var localizedDescription: String { String(localized: "Sekme \(ordinal)/\(count)") }
}

/// A native AXTabButton, not a web-page tab inferred from an application name or title.
public struct WindowTabControl: Sendable, Equatable {
    public let id: String
    public let title: String
    public let selected: Bool
    public init(id: String, title: String, selected: Bool) { self.id = id; self.title = title; self.selected = selected }
}

public struct WindowTabBar: Sendable {
    public let groupID: String
    public let anchorID: String
    public let controls: [WindowTabControl]
    public init?(groupID: String, anchorID: String, controls: [WindowTabControl]) {
        guard !groupID.isEmpty, !anchorID.isEmpty, (2...128).contains(controls.count),
              controls.allSatisfy({ !$0.id.isEmpty }), Set(controls.map(\.id)).count == controls.count,
              controls.filter(\.selected).count == 1 else { return nil }
        self.groupID = groupID; self.anchorID = anchorID; self.controls = controls
    }
}

/// Raw surface facts are needed to distinguish a physical window-tab group from an app's own
/// NSTabView, sidebar or browser tab strip. A nil Space read is not proof of an inactive tab.
public struct WindowTabSurface: Sendable {
    public let id: UInt32
    public let processID: Int32
    public let frame: CGRect
    public let spaceIDs: Set<UInt64>?
    public init(id: UInt32, processID: Int32, frame: CGRect, spaceIDs: Set<UInt64>?) {
        self.id = id; self.processID = processID; self.frame = frame; self.spaceIDs = spaceIDs
    }
}

public struct WindowTabBinding: Sendable {
    public let anchorID: String
    public let controlID: String
    public let title: String
    public let expectedWindowID: UInt32?
}

public struct WindowTabProjection: Sendable {
    public let windows: [SwitchableWindow]
    public let bindings: [String: WindowTabBinding]
    public let observedFocus: [String: Date]
}

public enum WindowTabProjectionResolver {
    public static func project(_ windows: [SwitchableWindow], surfaces: [WindowTabSurface], bars: [WindowTabBar],
                               focusHistory: [String: Date] = [:], creationHistory: [String: WindowCreationObservation] = [:]) -> WindowTabProjection {
        var replacements: [String: [SwitchableWindow]] = [:], removed = Set<UInt32>()
        var bindings: [String: WindowTabBinding] = [:], observedFocus: [String: Date] = [:]
        let anchors = Dictionary(grouping: windows, by: \.id)
        let physical = Dictionary(grouping: surfaces, by: \.id)
        struct Candidate {
            let bar: WindowTabBar
            let anchor: SwitchableWindow
            let surface: WindowTabSurface
            let group: String
        }
        struct Cluster: Hashable {
            let pid: Int32
            let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
            init(_ surface: WindowTabSurface) {
                pid = surface.processID
                x = surface.frame.minX; y = surface.frame.minY
                width = surface.frame.width; height = surface.frame.height
            }
        }
        let candidates: [Candidate] = bars.compactMap { bar in
            guard let matches = anchors[bar.anchorID], matches.count == 1, let anchor = matches.first,
                  let windowID = anchor.windowID, anchor.frame != nil, let launchedAt = anchor.launchedAt,
                  let matches = physical[windowID], matches.count == 1, let surface = matches.first,
                  surface.processID == anchor.processID, surface.spaceIDs?.isEmpty == false,
                  surface.frame.width > 0, surface.frame.height > 0,
                  [surface.frame.minX, surface.frame.minY, surface.frame.width, surface.frame.height].allSatisfy(\.isFinite)
            else { return nil }
            let group = CatalogWindowIdentity.application(pid: anchor.processID, launchedAt: launchedAt) + "-" + bar.groupID
            return Candidate(bar: bar, anchor: anchor, surface: surface, group: group)
        }
        let groupCounts = Dictionary(grouping: candidates, by: \.group).mapValues(\.count)
        let anchorCounts = Dictionary(grouping: candidates, by: { $0.anchor.id }).mapValues(\.count)
        let controlCounts = Dictionary(grouping: candidates.flatMap { candidate in
            candidate.bar.controls.map { "\(candidate.anchor.processID)-" + $0.id }
        }, by: { $0 }).mapValues(\.count)
        // Several tab groups can be stacked at precisely the same WindowServer frame. Verify
        // their combined surface count; do not assign background IDs by title, index or order.
        for (cluster, members) in Dictionary(grouping: candidates, by: { Cluster($0.surface) }) {
            guard members.allSatisfy({ candidate in
                groupCounts[candidate.group] == 1 && anchorCounts[candidate.anchor.id] == 1
                    && candidate.bar.controls.allSatisfy { controlCounts["\(candidate.anchor.processID)-" + $0.id] == 1 }
            }) else { continue }
            let inactive = surfaces.filter { $0.spaceIDs?.isEmpty == true && Cluster($0) == cluster }
            let required = members.reduce(0) { $0 + $1.bar.controls.count - 1 }
            guard inactive.count == required, inactive.allSatisfy({ physical[$0.id]?.count == 1 }),
                  Set(members.map { $0.surface.id }).count == members.count else { continue }
            for candidate in members {
                let bar = candidate.bar, anchor = candidate.anchor, windowID = candidate.surface.id
                let group = candidate.group
                let frame = candidate.surface.frame
                let launchedAt = anchor.launchedAt
                var cards: [SwitchableWindow] = []
                for (index, control) in bar.controls.enumerated() {
                    let id = "native-tab-" + group + "-" + control.id
                    let tab = WindowTabInfo(groupID: group, controlID: control.id, ordinal: index + 1, count: bar.controls.count, selected: control.selected)
                    let focused = [focusHistory[id], control.selected ? anchor.lastFocusedAt : nil].compactMap { $0 }.max()
                    let card = SwitchableWindow(id: id, processID: anchor.processID, application: anchor.application,
                        title: control.title.isEmpty ? String(localized: "Başlıksız sekme") : control.title, applicationURL: anchor.applicationURL,
                        minimized: anchor.minimized, hidden: anchor.hidden, fullScreen: anchor.fullScreen,
                        frontmost: control.selected && anchor.frontmost, windowAccessible: control.selected && anchor.windowAccessible,
                        canClose: control.selected && anchor.canClose, canMinimize: control.selected && anchor.canMinimize,
                        canFullScreen: control.selected && anchor.canFullScreen, launchedAt: launchedAt, lastFocusedAt: focused,
                        windowID: control.selected ? windowID : nil, frame: frame, displayID: anchor.displayID,
                        otherSpace: anchor.otherSpace, zOrder: anchor.zOrder, canResize: control.selected && anchor.canResize,
                        spaceMembership: anchor.spaceMembership, nativeTab: tab,
                        creationObservation: control.selected ? anchor.creationObservation : creationHistory[id], bundleIdentifier: anchor.bundleIdentifier)
                    cards.append(card)
                    bindings[id] = .init(anchorID: anchor.id, controlID: control.id, title: control.title,
                                         expectedWindowID: control.selected ? windowID : nil)
                    if control.selected, let date = anchor.lastFocusedAt { observedFocus[id] = date }
                }
                replacements[anchor.id] = cards
                removed.insert(windowID)
            }
            removed.formUnion(inactive.map(\.id))
        }
        let result = windows.flatMap { window -> [SwitchableWindow] in
            if let replacement = replacements[window.id] { return replacement }
            if let id = window.windowID, removed.contains(id) { return [] }
            return [window]
        }
        return .init(windows: result, bindings: bindings, observedFocus: observedFocus)
    }

    /// Button identity and current label are checked at action time. A removed/rebuilt button
    /// cannot silently redirect a saved tab choice to a new button at the same numeric index.
    public static func activationIndex(controlID: String, title: String, in bar: WindowTabBar) -> Int? {
        bar.controls.firstIndex { $0.id == controlID && $0.title == title }
    }
}
