#if DEBUG
import AppKit
import MacPocketCore
import ScreenCaptureKit
import SwiftUI

private actor UninstallAuditTrash {
    let root: URL
    private(set) var moved: [FileTrashResult] = []
    init(root: URL) { self.root = root }
    func move(_ requests: [FileTrashRequest]) -> [FileTrashResult] {
        requests.map { request in
            do {
                guard request.url.path.hasPrefix(root.path + "/") else { throw FileServiceError.outsideScope }
                try request.validate()
                let folder = root.appendingPathComponent("OwnedTrash/" + UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(request.url.lastPathComponent)
                try FileManager.default.moveItem(at: request.url, to: destination)
                let result = FileTrashResult(source: request.url, trashURL: destination, error: nil)
                moved.append(result); return result
            } catch { return .init(source: request.url, trashURL: nil, error: error.localizedDescription) }
        }
    }
    func results() -> [FileTrashResult] { moved }
}

/// Only the audit's freshly copied fixture apps may be closed, forced or moved. Ordinary services never start.
@MainActor enum UninstallRuntimeAudit {
    static var requested: Bool { CommandLine.arguments.contains("--audit-uninstall") }
    static func configureIfRequested() {
        guard requested else { return }
        var values = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        values[PocketPreferenceKey.showWindowAtLaunch] = false
        for module in PocketModule.allCases { values[module.availabilityKey] = false }
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    }
    static func launch() {
        guard let index = CommandLine.arguments.firstIndex(of: "--audit-uninstall"), CommandLine.arguments.indices.contains(index + 2) else { NSApp.terminate(nil); return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1]), template = URL(fileURLWithPath: CommandLine.arguments[index + 2])
        Task { await run(directory: directory, template: template); NSApp.terminate(nil) }
    }
    private static func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<120 { if condition() { return true }; try? await Task.sleep(for: .milliseconds(25)) }
        return false
    }
    private static func sign(_ app: URL) async throws {
        let result = try await BoundedProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path], timeout: 10)
        guard result.status == 0 else { throw FileServiceError.unreadable }
    }
    private static func makeApp(_ root: URL, template: URL) async throws -> URL {
        let app = root.appendingPathComponent("OwnedFixture.app")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: template, to: app)
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
        info["CFBundleIdentifier"] = "com.doancan.MacPocket.UninstallFixture." + UUID().uuidString
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        try await sign(app); return app
    }
    private static func open(_ app: URL, ready: URL, extra: [String]) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false; configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--ready", ready.path] + extra
        let running = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        guard await wait({ FileManager.default.fileExists(atPath: ready.path) }) else { throw FileServiceError.unreadable }
        guard await wait({ running.isFinishedLaunching }) else { throw FileServiceError.unreadable }
        return running
    }
    private static func capture(_ window: NSWindow, to destination: URL) async throws {
        guard WindowPreviewProvider.permitted else { throw WindowPreviewError.permissionRequired }
        let previous = NSWorkspace.shared.frontmostApplication
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer {
            if let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                previous.activate(options: [])
            }
        }
        try await Task.sleep(for: .milliseconds(250))
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { throw WindowPreviewError.unavailable }
        let filter = SCContentFilter(desktopIndependentWindow: target), config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)); config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw WindowPreviewError.unavailable }
        try data.write(to: destination)
    }
    private static func run(directory: URL, template: URL) async {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.doancan.MacPocket.UninstallAudit/owned-" + UUID().uuidString).resolvingSymlinksInPath()
        var checks: [String: Bool] = [:], details: [String: Any] = [:], failure: String?
        do {
            guard template.lastPathComponent == "UninstallFixture.app" else { throw FileServiceError.outsideScope }
            for mode in ["polite", "helper", "refuses"] {
                let home = root.appendingPathComponent(mode)
                let app = try await makeApp(home, template: template)
                guard let identifier = Bundle(url: app)?.bundleIdentifier else { throw FileServiceError.unreadable }
                let preference = home.appendingPathComponent("Library/Preferences/\(identifier).plist")
                try FileManager.default.createDirectory(at: preference.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("before quit".utf8).write(to: preference)
                for category in ["Caches", "Logs"] {
                    let folder = home.appendingPathComponent("Library/\(category)/\(identifier)")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try Data("owned audit data".utf8).write(to: folder.appendingPathComponent("sample.txt"))
                }
                let applications = try await ApplicationInventory().scan(roots: [home])
                guard let application = applications.first(where: { $0.url.path == app.path }) else { throw FileServiceError.unreadable }
                let plan = try UninstallPlanner.plan(application, home: home, systemLibrary: nil)
                var extra = ["--preference", preference.path]
                if mode == "refuses" { extra.append("--refuse-quit") }
                if mode == "helper" { extra.append("--stubborn-helper") }
                let running = try await open(app, ready: home.appendingPathComponent("ready.json"), extra: extra)
                var otherCopy: NSRunningApplication?
                var otherIdentity: ProcessIdentity?
                if mode == "polite" {
                    let other = home.appendingPathComponent("OtherCopy.app")
                    try FileManager.default.copyItem(at: app, to: other)
                    otherCopy = try await open(other, ready: home.appendingPathComponent("other-ready.json"), extra: [])
                    otherIdentity = try await ProcessMonitor().snapshot().processes.first { $0.pid == otherCopy?.processIdentifier }?.identity
                }
                let service = ApplicationUninstallProcesses(), trash = UninstallAuditTrash(root: root)
                let model = ApplicationWorkspaceModel(uninstallProcesses: service, uninstallRemoval: { requests, _, _, _ in await trash.move(requests) })
                let preparation = UninstallPreparationModel(application: application, service: service)
                await preparation.refresh()
                checks["\(mode)MainAndHelperDetected"] = preparation.processes.count == 2 && preparation.processes.contains(where: \.isMainApplication)
                let blocked = await model.uninstall(plan, selected: [application.id])
                let before = await trash.results()
                checks["\(mode)RunningRemovalBlocked"] = !blocked && before.isEmpty && FileManager.default.fileExists(atPath: app.path)
                var reviewWindow: NSWindow?
                if mode == "refuses" {
                    let window = NSWindow(contentRect: NSRect(x: 60, y: 80, width: 800, height: 740), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.title = "MacPocket · Uninstall fixture"
                    window.appearance = NSAppearance(named: CommandLine.arguments.contains("--audit-dark") ? .darkAqua : .aqua)
                    window.contentViewController = NSHostingController(rootView: UninstallPlanView(plan: plan, model: model, preparation: preparation).buttonStyle(.pocketSecondary))
                    window.orderFront(nil); reviewWindow = window
                    try await Task.sleep(for: .milliseconds(400))
                    try await capture(window, to: directory.appendingPathComponent("plan.png"))
                }
                let ready = await preparation.prepare()
                details[mode] = ["failure":preparation.failure ?? "", "mainTerminated":running.isTerminated,
                    "mainFinishedLaunching":running.isFinishedLaunching,
                    "quitReceipt":(try? String(contentsOf: home.appendingPathComponent("ready.json.quit"), encoding: .utf8)) ?? "",
                    "remaining":preparation.processes.map { ["pid":String($0.pid),"main":String($0.isMainApplication),"canStop":String($0.canStop)] },
                    "quitReceived":FileManager.default.fileExists(atPath: home.appendingPathComponent("ready.json.quit").path)]
                checks["\(mode)NormalQuitOutcome"] = ready == (mode == "polite")
                if !ready {
                    checks["\(mode)NoFilesRemovedOnRefusal"] = (await trash.results()).isEmpty && FileManager.default.fileExists(atPath: app.path)
                    if mode == "helper" { checks["helperSurvivesUntilSeparateForce"] = preparation.processes.count == 1 && !preparation.processes[0].isMainApplication }
                    if let window = reviewWindow {
                        try await Task.sleep(for: .milliseconds(400))
                        let nodes = ToolUIAudit.accessibilityNodes(window)
                        checks["nativeReviewControlsPresent"] = nodes.filter { $0["role"] == "AXButton" }.count >= 3
                        try await capture(window, to: directory.appendingPathComponent("review.png"))
                        window.close()
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    let forced = await preparation.prepare(forceConsent: preparation.forceIdentities)
                    checks["\(mode)SeparateForceCompletes"] = forced
                }
                let chosen = mode == "polite" ? Set(plan.candidates.map(\.id)) : [application.id]
                let removed = await model.uninstall(plan, selected: chosen)
                checks["\(mode)RemovedAfterExit"] = removed && !FileManager.default.fileExists(atPath: app.path)
                if mode == "polite" {
                    let moved = await trash.results()
                    let saved = moved.first { $0.source.path == preference.path }?.trashURL
                    checks["savedPreferencesRefreshed"] = saved.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.contains("saved by the owned fixture") == true
                    let current = try await ProcessMonitor().snapshot().processes.first { $0.pid == otherCopy?.processIdentifier }?.identity
                    checks["sameIDOtherCopyStillRunning"] = otherIdentity != nil && current == otherIdentity
                } else { checks["\(mode)UnselectedDataPreserved"] = FileManager.default.fileExists(atPath: preference.path) }
            }
        } catch { failure = error.localizedDescription }
        // Cleanup uses current process identities and only executables in this freshly created audit directory.
        let monitor = ProcessMonitor()
        if let snapshot = try? await monitor.snapshot() {
            for entry in snapshot.processes where entry.command.hasPrefix(root.path + "/") && entry.canTerminate {
                try? await monitor.terminate(entry: entry, force: true)
            }
        }
        try? await Task.sleep(for: .milliseconds(250))
        let leftovers = (try? await monitor.snapshot().processes.filter { $0.command.hasPrefix(root.path + "/") }) ?? []
        checks["ownedProcessesCleanedUp"] = leftovers.isEmpty
        if leftovers.isEmpty { try? FileManager.default.removeItem(at: root) }
        let report: [String: Any] = ["passed": failure == nil && checks.values.allSatisfy { $0 }, "checks": checks,
            "details":details,
            "error": failure ?? "", "language": Bundle.main.preferredLocalizations.first ?? "unknown",
            "scope": "owned-GUI-and-embedded-worker; owned-file-moves", "userApplicationsStopped": false]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        }
    }
}
#endif
