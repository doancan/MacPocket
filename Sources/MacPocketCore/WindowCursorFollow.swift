import AppKit
import CoreGraphics
import Foundation

public enum SwitcherCursorPolicy: String, Codable, CaseIterable, Sendable {
    case never, always, differentDisplay
    public static let key = "switcher.cursorFollowFocus"
    public static func load(_ defaults: UserDefaults = .standard) -> Self { .init(rawValue: defaults.string(forKey: key) ?? "") ?? .never }
    public var localizedTitle: String {
        switch self {
        case .never: String(localized: "Kapalı")
        case .always: String(localized: "Her geçişte")
        case .differentDisplay: String(localized: "Yalnız imleç başka ekrandaysa")
        }
    }
}

/// An exact post-focus target. Catalog rows may be stale or represent an inactive native tab;
/// only the current AX focused window corroborated by WindowServer may supply this geometry.
/// For an attached sheet, catalog selection is proved against its owning window and this
/// destination describes the actually focused sheet, so the cursor follows the interactive surface.
public struct WindowFocusDestination: Equatable, Sendable {
    public let processID: Int32
    public let launchedAt: Date
    public let windowID: UInt32
    /// CoreGraphics global coordinates, like CGEvent.location and CGDisplayBounds.
    public let frame: CGRect
    public init(processID: Int32,launchedAt: Date,windowID: UInt32,frame: CGRect) {
        self.processID = processID;self.launchedAt = launchedAt;self.windowID = windowID;self.frame = frame
    }
}

public struct WindowCursorOrigin: Equatable, Sendable {
    public let point: CGPoint
    public let interactionSerial: UInt64
    public init(point: CGPoint,interactionSerial: UInt64 = 0) { self.point = point;self.interactionSerial = interactionSerial }
}

public enum WindowCursorGeometry {
    public static func destination(policy: SwitcherCursorPolicy,origin: WindowCursorOrigin,current: WindowCursorOrigin,buttonsDown: Bool,
                                   window: CGRect,displays: [(id: UInt32,frame: CGRect)]) -> CGPoint? {
        guard origin.interactionSerial == current.interactionSerial,!buttonsDown else { return nil }
        return destination(policy: policy,origin: origin.point,current: current.point,window: window,displays: displays)
    }

    public static func destination(policy: SwitcherCursorPolicy,origin: CGPoint,current: CGPoint,window: CGRect,
                                   displays: [(id: UInt32,frame: CGRect)]) -> CGPoint? {
        guard policy != .never, [origin.x,origin.y,current.x,current.y,window.minX,window.minY,window.width,window.height,window.maxX,window.maxY].allSatisfy(\.isFinite),
              window.width > 0,window.height > 0,hypot(current.x-origin.x,current.y-origin.y) <= 3 else { return nil }
        let screens = displays.filter { $0.frame.width > 0 && $0.frame.height > 0
            && [$0.frame.minX,$0.frame.minY,$0.frame.width,$0.frame.height,$0.frame.maxX,$0.frame.maxY].allSatisfy(\.isFinite) }
        let center = CGPoint(x: window.midX,y: window.midY)
        let candidates = screens.compactMap { screen -> (UInt32,CGRect,CGFloat)? in
            let visible = screen.frame.intersection(window)
            guard !visible.isNull,visible.width > 0,visible.height > 0 else { return nil }
            return (screen.id,visible,visible.width * visible.height)
        }
        guard let target = candidates.max(by: { lhs,rhs in
            // Prefer the display containing the actual window center, then the largest visible area.
            let left = screens.first { $0.id == lhs.0 }?.frame.contains(center) == true
            let right = screens.first { $0.id == rhs.0 }?.frame.contains(center) == true
            return left == right ? (lhs.2 == rhs.2 ? lhs.0 > rhs.0 : lhs.2 < rhs.2) : !left && right
        }) else { return nil }
        if policy == .differentDisplay {
            let currentScreens = screens.filter { $0.frame.contains(current) }
            guard currentScreens.count == 1,currentScreens[0].id != target.0 else { return nil }
        }
        return CGPoint(x: target.1.midX,y: target.1.midY)
    }
}

public enum WindowCursorFollowOutcome: Equatable, Sendable {
    case moved, notRequested, interrupted, notReady, unavailable
}

@MainActor public protocol WindowCursorFollowing: AnyObject {
    func captureOrigin() -> WindowCursorOrigin?
    @discardableResult func follow(_ target: WindowFocusDestination,from origin: WindowCursorOrigin,policy: SwitcherCursorPolicy) -> WindowCursorFollowOutcome
}

/// No event monitor or input injection. A successful, explicit switch may warp the cursor once;
/// all final reads and the warp are synchronous on main, with no suspension between them.
@MainActor public final class WindowCursorFollower: WindowCursorFollowing {
    public init() {}
#if DEBUG
    public private(set) var lastAuditTrace: [String: String] = [:]
#endif
    public func captureOrigin() -> WindowCursorOrigin? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        let types: [CGEventType] = [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.leftMouseDown,.rightMouseDown,.otherMouseDown,.scrollWheel,.keyDown]
        let serial = types.reduce(UInt64(0)) { $0 + UInt64(CGEventSource.counterForEventType(.combinedSessionState,eventType: $1)) }
        return .init(point: point,interactionSerial: serial)
    }
    public func follow(_ target: WindowFocusDestination,from origin: WindowCursorOrigin,policy: SwitcherCursorPolicy) -> WindowCursorFollowOutcome {
#if DEBUG
        let observed = captureOrigin()
        let windowRows = CGWindowListCopyWindowInfo(.optionOnScreenOnly,0) as? [[String: Any]] ?? []
        lastAuditTrace = ["targetID": String(target.windowID),"policy": policy.rawValue,"origin": NSStringFromPoint(origin.point),
                          "originSerial": String(origin.interactionSerial),"current": observed.map { NSStringFromPoint($0.point) } ?? "nil",
                          "currentSerial": observed.map { String($0.interactionSerial) } ?? "nil",
                          "frontPID": NSWorkspace.shared.frontmostApplication.map { String($0.processIdentifier) } ?? "nil",
                          "ownedWindowOrder": windowRows.filter { $0[kCGWindowOwnerPID as String] as? Int32 == target.processID }.compactMap { $0[kCGWindowNumber as String] as? UInt32 }.map(String.init).joined(separator: ",")]
#endif
        guard policy != .never else { return .notRequested }
        guard !Task.isCancelled else { return .interrupted }
        guard let app = NSWorkspace.shared.frontmostApplication,app.processIdentifier == target.processID,!app.isTerminated,
              CatalogWindowIdentity.processLaunchDate(pid: target.processID,applicationDate: app.launchDate) == target.launchedAt else { return .unavailable }
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],0) as? [[String: Any]],
              let row = rows.first(where: { $0[kCGWindowNumber as String] as? UInt32 == target.windowID && $0[kCGWindowOwnerPID as String] as? Int32 == target.processID }),
              let bounds = row[kCGWindowBounds as String] as? NSDictionary,let frame = CGRect(dictionaryRepresentation: bounds),
              let layer = row[kCGWindowLayer as String] as? Int,
              rows.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == target.processID && $0[kCGWindowLayer as String] as? Int == layer })?[kCGWindowNumber as String] as? UInt32 == target.windowID else { return .notReady }
#if DEBUG
        lastAuditTrace["windowValidated"] = "true"
#endif
        let screens = NSScreen.screens.compactMap { screen -> (id: UInt32,frame: CGRect)? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return (id,CGDisplayBounds(id))
        }
        let buttons = CGEventSource.buttonState(.combinedSessionState,button: .left)
            || CGEventSource.buttonState(.combinedSessionState,button: .right) || CGEventSource.buttonState(.combinedSessionState,button: .center)
        guard let current = captureOrigin(),current.interactionSerial == origin.interactionSerial,!buttons,
              hypot(current.point.x-origin.point.x,current.point.y-origin.point.y) <= 3,
              !Task.isCancelled else { return .interrupted }
        guard let point = WindowCursorGeometry.destination(policy: policy,origin: origin,current: current,buttonsDown: buttons,window: frame,displays: screens) else { return .notRequested }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID else { return .interrupted }
        let result = CGWarpMouseCursorPosition(point)
#if DEBUG
        lastAuditTrace["point"] = NSStringFromPoint(point);lastAuditTrace["warpResult"] = String(result.rawValue)
#endif
        return result == .success ? .moved : .unavailable
    }
}
