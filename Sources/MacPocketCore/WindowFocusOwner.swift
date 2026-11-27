import ApplicationServices
import Foundation

/// AXFocusedWindow can be an attached AXSheet (for example Electron's native alert), rather
/// than the AXWindow shown in the switcher. Only its bounded, same-process parent chain may
/// establish ownership; an unrelated dialog/application root is never a matching window.
enum WindowFocusOwner {
    static func window<IO: WindowTabIO>(for focused: IO.Element, processID: Int32, io: IO) -> IO.Element? {
        guard io.trusted, processID > 0, !Task.isCancelled else { return nil }
        var current = focused
        var visited: [IO.Element] = []
        let deadline = ContinuousClock.now + .milliseconds(100)
        for depth in 0..<8 {
            guard !Task.isCancelled, ContinuousClock.now < deadline,
                  !visited.contains(where: { io.equal($0,current) }) else { return nil }
            visited.append(current)
            io.setTimeout(current,seconds: 0.02)
            guard io.processID(current) == processID, case .value(let role) = io.role(current) else { return nil }
            if role == kAXWindowRole as String { return current }
            guard role != kAXApplicationRole as String,
                  depth > 0 || role == kAXSheetRole as String,
                  let parent = io.element(current,attribute: kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }
}
