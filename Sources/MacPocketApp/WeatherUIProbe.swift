import SwiftUI

#if DEBUG
import AppKit

/// Geometry belongs only to the audit's own window. No system-wide input posting or AX permission is used.
@MainActor enum WeatherUIProbe {
    struct Target { let owner: UUID; let frame: CGRect }
    static var targets: [String: Target] = [:]
    static func contains(_ id: String) -> Bool { targets[id].map { $0.frame.width > 0 && $0.frame.height > 0 } == true }
    static func click(_ id: String, in window: NSWindow) async -> Bool {
        guard let frame = targets[id]?.frame, frame.width > 0, frame.height > 0,
              let content = window.contentView else { return false }
        let origin = targets["weather.root"]?.frame.origin ?? .zero
        let local = frame.offsetBy(dx: -origin.x, dy: -origin.y)
        let disclosure = ["weather.models", "weather.accounts", "weather.basket"].contains(id)
        let point = NSPoint(x: disclosure ? max(4, local.minX - 12) : local.midX, y: content.bounds.height - local.midY)
        guard content.bounds.contains(NSPoint(x: local.midX, y: local.midY)) else { return false }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { return false }
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(120))
        return true
    }
}

private struct WeatherUIProbeModifier: ViewModifier {
    let id: String
    @State private var owner = UUID()
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if WeatherBasketRuntimeAudit.requested { WeatherUIProbe.targets[id] = .init(owner: owner, frame: frame) }
        }.onDisappear {
            if WeatherUIProbe.targets[id]?.owner == owner { WeatherUIProbe.targets[id] = nil }
        }
    }
}
#endif

extension View {
    @ViewBuilder func weatherAuditTarget(_ id: String) -> some View {
        #if DEBUG
        modifier(WeatherUIProbeModifier(id: id))
        #else
        self
        #endif
    }
}
