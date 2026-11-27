@preconcurrency import ApplicationServices
import Foundation

struct TabAction<Element> {
    let group: Element
    let button: Element
    let controlID: String
    let title: String
    var expectedWindowID: UInt32?
}
struct TabScan<Element> {
    let group: Element
    let bar: WindowTabBar
    let actions: [String: TabAction<Element>]
}
struct WindowTabProcess: Hashable { let pid: Int32; let launchedAt: Date }
struct TabWindowDiscovery<Element> {
    let windows: [Element]
    let cachedByWindowID: [UInt32: [TabScan<Element>]]
    let invalidGroups: Set<String>
    let partial: Bool
}

typealias WindowTabAction = TabAction<AXUIElement>
typealias WindowTabScan = TabScan<AXUIElement>
typealias WindowTabAccessibility = TabAccessibility<AXWindowTabIO>

/// Actor-owned discovery/action logic. The OS transport is separate so native in-process
/// NSAccessibility fixtures exercise the same identity/cache rules without a TCC bypass.
final class TabAccessibility<IO: WindowTabIO> {
    typealias Element = IO.Element
    private struct Token { let element: Element; let id: String; var touched: UInt64 }
    private struct Remembered { let process: WindowTabProcess; let scan: TabScan<Element> }
    private let io: IO
    private var tokens: [Token] = []
    private var serial: UInt64 = 0
    private var groups: [Remembered] = [] // Most recently verified first.
    private var cursors: [WindowTabProcess: Int] = [:]
    private let groupLimit: Int
    private let controlLimit: Int
    init(io: IO, groupLimit: Int = 128, controlLimit: Int = 2_048) {
        self.io = io
        self.groupLimit = max(0, groupLimit)
        self.controlLimit = max(0, controlLimit)
    }
    var rememberedGroupCount: Int { groups.count }
    func reset() { tokens.removeAll(); groups.removeAll(); cursors.removeAll(); serial = 0 }

    /// Re-read retained group references; never reuse cached titles, selection or window roots.
    /// Only previously corroborated groups can contribute a missing AX-window entry.
    func discoverWindows(listed: [Element], process: WindowTabProcess, physicalWindowIDs: Set<UInt32>, deadline: Date, limit: Int = 80,
                         recoveryBudget: TimeInterval = 0.2) -> TabWindowDiscovery<Element> {
        let maximum = max(0, limit)
        var windows = Array(listed.prefix(maximum)), partial = listed.count > maximum
        var byWindowID: [UInt32: [TabScan<Element>]] = [:], recovered: [UInt32: Element] = [:]
        var invalid = Set<String>()
        guard io.trusted else { return .init(windows: windows, cachedByWindowID: [:], invalidGroups: [], partial: partial) }
        guard !Task.isCancelled, Date() < deadline else { return .init(windows: windows, cachedByWindowID: [:], invalidGroups: [], partial: true) }
        let remembered = groups.filter { $0.process == process }
        for entry in remembered { restore(entry.scan) }
        let end = min(deadline, Date().addingTimeInterval(max(0, recoveryBudget)))
        let offset = remembered.isEmpty ? 0 : (cursors[process] ?? 0) % remembered.count
        var visited = 0
        for index in remembered.indices {
            guard !Task.isCancelled, Date() < end else { partial = true; break }
            visited += 1
            let entry = remembered[(offset + index) % remembered.count]
            io.setTimeout(entry.scan.group, seconds: 0.03)
            switch io.role(entry.scan.group) {
            case .invalid: invalid.insert(entry.scan.bar.groupID)
            continue
            case .value(let role) where role != kAXTabGroupRole as String: invalid.insert(entry.scan.bar.groupID)
            continue
            case .unavailable: partial = true
            continue
            default: break
            }
            guard let pid = io.processID(entry.scan.group) else { partial = true; continue }
            guard pid == process.pid else { invalid.insert(entry.scan.bar.groupID); continue }
            guard let window = groupWindow(entry.scan.group, processID: process.pid), let id = io.windowID(window) else {
                partial = true
                continue
            }
            // A retained AX object is not proof that its physical window still exists.
            guard physicalWindowIDs.contains(id) else { partial = true; continue }
            recovered[id] = window
            byWindowID[id, default: []].append(entry.scan)
        }
        if !remembered.isEmpty { cursors[process] = (offset + visited) % remembered.count }
        // Two different groups claiming one root are ambiguous. Do not choose the first one.
        for (id, scans) in byWindowID where scans.count != 1 {
            recovered.removeValue(forKey: id)
            invalid.formUnion(scans.map { $0.bar.groupID })
            partial = true
        }
        byWindowID = byWindowID.filter { recovered[$0.key] != nil }
        var seen = Set(windows.compactMap { io.windowID($0) })
        for entry in remembered {
            guard let item = byWindowID.first(where: { $0.value.first?.bar.groupID == entry.scan.bar.groupID }),
                  let window = recovered[item.key], seen.insert(item.key).inserted else { continue }
            if windows.count < maximum { windows.append(window) } else { partial = true }
        }
        return .init(windows: windows, cachedByWindowID: byWindowID, invalidGroups: invalid, partial: partial)
    }

    func scan(window: Element, anchorID: String, cached: [TabScan<Element>] = [], deadline: Date) -> TabScan<Element>? {
        guard io.trusted, !Task.isCancelled, Date() < deadline,
              let pid = io.processID(window), let expectedID = io.windowID(window), expectedID > 0 else { return nil }
        for previous in cached { restore(previous) }
        let end = min(deadline, Date().addingTimeInterval(0.04))
        if let children = io.children(window, limit: 64) {
            for child in children {
                guard !Task.isCancelled, Date() < end else { break }
                io.setTimeout(child, seconds: 0.03)
                guard io.role(child) == .value(kAXTabGroupRole as String) else { continue }
                if let scan = readGroup(child, window: window, processID: pid, expectedID: expectedID,
                                        anchorID: anchorID, deadline: min(deadline, Date().addingTimeInterval(0.06))) { return scan }
            }
        }
        // An off-Space AX window can be absent from AXWindows/AXChildren while the retained
        // group itself remains readable. The group/root/controls are freshly checked again.
        for previous in cached {
            guard !Task.isCancelled, Date() < deadline else { return nil }
            if let scan = readGroup(previous.group, window: window, processID: pid, expectedID: expectedID,
                                    anchorID: anchorID, deadline: min(deadline, Date().addingTimeInterval(0.06))) { return scan }
        }
        return nil
    }

    /// Called only by the latest committed catalog snapshot. Physical corroboration is a gate;
    /// an ordinary app's NSTabView cannot become a retained window-group discovery source.
    func commit(scans: [TabScan<Element>], processes: [String: WindowTabProcess], projection: WindowTabProjection,
                liveProcesses: Set<WindowTabProcess>, invalidGroups: Set<String> = []) {
        guard io.trusted else { reset(); return }
        groups = groups.filter { liveProcesses.contains($0.process) && !invalidGroups.contains($0.scan.bar.groupID) }
        cursors = cursors.filter { liveProcesses.contains($0.key) }
        let confirmed = Set(projection.bindings.values.map(\.anchorID))
        for scan in scans where confirmed.contains(scan.bar.anchorID) {
            guard let process = processes[scan.bar.anchorID], liveProcesses.contains(process) else { continue }
            groups.removeAll { $0.process == process && io.equal($0.scan.group, scan.group) }
            groups.insert(.init(process: process, scan: scan), at: 0)
        }
        var retainedControls = 0
        groups = Array(groups.prefix(groupLimit)).filter { entry in
            let next = retainedControls + entry.scan.bar.controls.count
            guard next <= controlLimit else { return false }
            retainedControls = next
            return true
        }
    }

    private func token(for element: Element, preferredID: String? = nil) -> String {
        serial &+= 1
        if let index = tokens.firstIndex(where: { io.equal($0.element, element) }) {
            let id = preferredID ?? tokens[index].id
            tokens[index] = .init(element: element, id: id, touched: serial)
            return id
        }
        let id = preferredID ?? UUID().uuidString
        tokens.append(.init(element: element, id: id, touched: serial))
        if tokens.count > 4_096 { tokens.sort { $0.touched > $1.touched }; tokens.removeLast(tokens.count - 4_096) }
        return id
    }
    private func restore(_ scan: TabScan<Element>) {
        _ = token(for: scan.group, preferredID: scan.bar.groupID)
        for action in scan.actions.values { _ = token(for: action.button, preferredID: action.controlID) }
    }
    private func groupWindow(_ group: Element, processID: Int32) -> Element? {
        io.setTimeout(group, seconds: 0.03)
        guard let window = io.element(group, attribute: kAXWindowAttribute), io.processID(window) == processID else { return nil }
        io.setTimeout(window, seconds: 0.03)
        guard io.role(window) == .value(kAXWindowRole as String), let id = io.windowID(window), id > 0 else { return nil }
        let subrole = io.string(window, attribute: kAXSubroleAttribute)
        guard subrole == nil || subrole == kAXStandardWindowSubrole as String || subrole == "AXDialog" else { return nil }
        return window
    }
    private func readGroup(_ group: Element, window: Element, processID: Int32, expectedID: UInt32,
                           anchorID: String, deadline: Date) -> TabScan<Element>? {
        guard io.trusted, !Task.isCancelled, Date() < deadline, io.processID(group) == processID,
              io.role(group) == .value(kAXTabGroupRole as String),
              let before = groupWindow(group, processID: processID), io.windowID(before) == expectedID, io.equal(before, window),
              let elements = io.children(group, limit: 160) else { return nil }
        var controls: [WindowTabControl] = [], actions: [String: TabAction<Element>] = [:]
        for element in elements {
            guard !Task.isCancelled, Date() < deadline else { return nil }
            io.setTimeout(element, seconds: 0.03)
            guard let attributes = io.tabAttributes(element) else { return nil }
            guard attributes.subrole == "AXTabButton" else { continue }
            guard io.processID(element) == processID else { return nil }
            let id = token(for: element)
            controls.append(.init(id: id, title: attributes.title, selected: attributes.selected))
            actions[id] = .init(group: group, button: element, controlID: id, title: attributes.title)
        }
        guard let bar = WindowTabBar(groupID: token(for: group), anchorID: anchorID, controls: controls),
              let selected = bar.controls.first(where: \.selected), let action = actions[selected.id], io.flag(action.button, attribute: kAXValueAttribute),
              let after = groupWindow(group, processID: processID), io.windowID(after) == expectedID, io.equal(before, after) else { return nil }
        return .init(group: group, bar: bar, actions: actions)
    }

    func press(_ target: TabAction<Element>, processID: Int32) throws {
        let (_, button) = try validatedTarget(target, processID: processID)
        try Task.checkCancellation()
        guard io.press(button) else { throw WindowCatalogError.focusFailed }
    }
    /// Resolve the current group root before selecting an off-Space background tab. Selecting
    /// first can assign its previously Space-less physical surface to the caller's current Space.
    func anchorWindow(for target: TabAction<Element>, processID: Int32) throws -> Element {
        try validatedTarget(target, processID: processID).0
    }
    private func validatedTarget(_ target: TabAction<Element>, processID: Int32) throws -> (Element, Element) {
        guard io.trusted else { throw WindowCatalogError.permissionRequired }
        guard io.processID(target.group) == processID, let window = groupWindow(target.group, processID: processID),
              let id = io.windowID(window) else { throw WindowCatalogError.expired }
        _ = token(for: target.button, preferredID: target.controlID)
        guard let current = readGroup(target.group, window: window, processID: processID, expectedID: id,
                                      anchorID: "validation", deadline: Date().addingTimeInterval(0.2)),
              let index = WindowTabProjectionResolver.activationIndex(controlID: target.controlID, title: target.title, in: current.bar),
              let actual = current.actions[current.bar.controls[index].id], io.equal(actual.button, target.button) else { throw WindowCatalogError.expired }
        try Task.checkCancellation()
        return (window, actual.button)
    }
    func selectedWindow(for target: TabAction<Element>, processID: Int32) -> Element? {
        guard io.trusted, io.flag(target.button, attribute: kAXValueAttribute), let window = groupWindow(target.group, processID: processID) else { return nil }
        if let expected = target.expectedWindowID, io.windowID(window) != expected { return nil }
        return window
    }
}

extension TabAccessibility where IO == AXWindowTabIO {
    convenience init() { self.init(io: AXWindowTabIO()) }
}
