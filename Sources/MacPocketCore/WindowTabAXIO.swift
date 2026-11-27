@preconcurrency import ApplicationServices
import Foundation

enum WindowTabRole: Equatable { case value(String), invalid, unavailable }
struct WindowTabAttributes { let subrole: String?; let title: String; let selected: Bool }

/// Synchronous, actor-owned transport. Element references never leave their owner.
protocol WindowTabIO {
    associatedtype Element
    var trusted: Bool { get }
    func equal(_ lhs: Element, _ rhs: Element) -> Bool
    func processID(_ element: Element) -> Int32?
    func windowID(_ element: Element) -> UInt32?
    func role(_ element: Element) -> WindowTabRole
    func string(_ element: Element, attribute: String) -> String?
    func flag(_ element: Element, attribute: String) -> Bool
    func element(_ element: Element, attribute: String) -> Element?
    func children(_ element: Element, limit: Int) -> [Element]?
    func tabAttributes(_ element: Element) -> WindowTabAttributes?
    func setTimeout(_ element: Element, seconds: Float)
    func press(_ element: Element) -> Bool
}

struct AXWindowTabIO: WindowTabIO {
    var trusted: Bool { AXIsProcessTrusted() }
    func equal(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool { CFEqual(lhs, rhs) }
    func processID(_ element: AXUIElement) -> Int32? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success && pid > 0 ? pid : nil
    }
    func windowID(_ element: AXUIElement) -> UInt32? { WindowCatalog.windowID(of: element) }
    func role(_ element: AXUIElement) -> WindowTabRole {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        if result == .invalidUIElement { return .invalid }
        guard result == .success, let role = value as? String else { return .unavailable }
        return .value(role)
    }
    func string(_ element: AXUIElement, attribute: String) -> String? { value(element, attribute) as? String }
    func flag(_ element: AXUIElement, attribute: String) -> Bool { (value(element, attribute) as? NSNumber)?.boolValue == true }
    func element(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    func children(_ element: AXUIElement, limit: Int) -> [AXUIElement]? {
        guard !Task.isCancelled else { return nil }
        setTimeout(element, seconds: 0.03)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success, (0...limit).contains(count) else { return nil }
        if count == 0 { return [] }
        var value: CFArray?
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, count, &value) == .success,
              let elements = value as? [AXUIElement], elements.count == count else { return nil }
        return elements
    }
    func tabAttributes(_ element: AXUIElement) -> WindowTabAttributes? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, [kAXSubroleAttribute, kAXTitleAttribute, kAXValueAttribute] as CFArray, [], &values) == .success,
              let attributes = values as? [Any], attributes.count == 3 else { return nil }
        return .init(subrole: attributes[0] as? String, title: attributes[1] as? String ?? "", selected: (attributes[2] as? NSNumber)?.boolValue == true)
    }
    func setTimeout(_ element: AXUIElement, seconds: Float) { AXUIElementSetMessagingTimeout(element, seconds) }
    func press(_ element: AXUIElement) -> Bool { AXUIElementPerformAction(element, kAXPressAction as CFString) == .success }
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
