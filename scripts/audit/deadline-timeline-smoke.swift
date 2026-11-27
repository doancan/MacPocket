import AppKit
import SwiftUI

@MainActor private final class DeadlineState: ObservableObject {
    @Published var deadline: Date?
    init(_ date: Date) { deadline = date }
}
private struct ChangingDeadlineRow: View {
    @ObservedObject var state: DeadlineState
    let record: (Date) -> Text
    var body: some View { DeadlineRefreshView(deadline: state.deadline, content: record).frame(width: 440, height: 160) }
}

@main @MainActor struct DeadlineSmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = Delegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
    @MainActor final class Delegate: NSObject, NSApplicationDelegate {
        var contexts: [String: Set<Date>] = [:]
        var ready: [Bool] = []
        func applicationDidFinishLaunching(_ notification: Notification) { Task { await run(); NSApp.terminate(nil) } }
        func record(_ name: String, _ date: Date, deadline: Date? = nil) -> Text {
            contexts[name, default: []].insert(date)
            if let deadline { ready.append(date >= deadline) }
            return Text(verbatim: name + ": " + String(date.timeIntervalSinceReferenceDate))
        }
        func run() async {
            let start = Date(), deadline = start.addingTimeInterval(2)
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 440, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            let host = NSHostingController(rootView: VStack(alignment: .leading, spacing: 12) {
                TimelineView(.periodic(from: start, by: 1)) { self.record("periodic", $0.date) }
                DeadlineRefreshView(deadline: deadline) { self.record("deadline", $0, deadline: deadline) }
                DeadlineRefreshView(deadline: nil) { self.record("none", $0) }
                DeadlineRefreshView(deadline: start.addingTimeInterval(-30)) { self.record("past", $0) }
            }.padding().frame(width: 440, height: 160))
            host.sizingOptions = []
            window.contentViewController = host
            window.setContentSize(NSSize(width: 440, height: 160))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(3400))
            var checks = ["periodicUpdatedRepeatedly": (contexts["periodic"]?.count ?? 0) >= 3,
                "deadlineOnlyInitialAndBoundary":contexts["deadline"]?.count == 2,
                "nilDeadlineStillRendersOnce":contexts["none"]?.count == 1,
                "pastDeadlineRendersOnce":contexts["past"]?.count == 1,
                "initiallyDisabled":ready.first == false,"enabledAtDeadline":ready.last == true]
            let comparisonContexts = contexts.mapValues(\.count)
            let changing = DeadlineState(Date().addingTimeInterval(0.7))
            var changeHost: NSHostingController<ChangingDeadlineRow>? = NSHostingController(rootView: ChangingDeadlineRow(state: changing) {
                self.record("changed", $0)
            })
            changeHost?.sizingOptions = []
            window.contentViewController = changeHost
            try? await Task.sleep(for: .milliseconds(200))
            changing.deadline = Date().addingTimeInterval(1.6)
            try? await Task.sleep(for: .milliseconds(800))
            checks["replacedDeadlineDoesNotFire"] = contexts["changed"]?.count == 1
            try? await Task.sleep(for: .milliseconds(1000))
            checks["replacementDeadlineFiresOnce"] = contexts["changed"]?.count == 2
            changing.deadline = Date().addingTimeInterval(0.5)
            try? await Task.sleep(for: .milliseconds(100))
            window.contentViewController = nil
            changeHost = nil
            let previous = contexts["changed"]?.count
            try? await Task.sleep(for: .milliseconds(650))
            checks["removedViewCancelsDeadline"] = contexts["changed"]?.count == previous
            window.close()
            window.contentViewController = nil
            let report: [String: Any] = ["passed":checks.values.allSatisfy { $0 }, "checks":checks,
                "uniqueTimelineContexts":comparisonContexts,"changedDeadlineContexts":contexts["changed"]?.count ?? 0,
                "comparisonSeconds":3.4,"networkRequests":false,"userPreferencesChanged":false]
            if CommandLine.arguments.count > 1, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
        }
    }
}
