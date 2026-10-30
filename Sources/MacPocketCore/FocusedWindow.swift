import ApplicationServices
import CoreGraphics

/// The focused window of the frontmost app, moved and resized through the Accessibility API.
/// Frames are in Accessibility coordinates (top-left origin of the primary display, y down).
public struct FocusedWindow {
    public let element: AXUIElement
    public let processID: pid_t

    /// nil without Accessibility access, or when the front app has no focused window (e.g. Finder's desktop).
    public static func current() -> FocusedWindow? {
        let system = AXUIElementCreateSystemWide()
        guard let app = element(system, kAXFocusedApplicationAttribute),
              let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return FocusedWindow(element: window, processID: pid)
    }

    public var frame: CGRect? {
        guard let position = Self.value(element, kAXPositionAttribute), let size = Self.value(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// Size, then position, then size again: apps that clamp a size to the current screen accept the full
    /// size only after the window has moved. Returns false when the app refuses the change.
    @discardableResult
    public func setFrame(_ frame: CGRect) -> Bool {
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return false }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
        let resized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return moved == .success && resized == .success
    }

    /// Same window (AX elements are compared by identity, not by pointer).
    public func isSame(as other: FocusedWindow) -> Bool { CFEqual(element, other.element) }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func value(_ parent: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
