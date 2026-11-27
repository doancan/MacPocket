#if DEBUG
import AppKit
import Foundation
import ScreenCaptureKit
import ObjectiveC
import SSHConfigKit

/// End-to-end checks use an explicitly supplied throwaway home, never the user's SSH files or agent.
@MainActor
public enum SSHRuntimeAudit {
    static func makeFixture(home: URL) -> (model: AppModel, defaults: UserDefaults) {
        let defaults = UserDefaults(suiteName: home.appending(path: "preferences").path)!
        let fm = FileManager.default
        try? fm.createDirectory(at: home.appending(path: ".ssh"), withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let config = home.appending(path: "ssh_config")
        let known = home.appending(path: "known_hosts")
        let included = home.appending(path: "included.conf")
        let text = """
        # MacPocket SSH acceptance fixture — never a real server.
        Include \(included.path)
        # group: Development
        Host demo-web
          HostName 127.0.0.1
          User deploy
          Port 9
          IdentityFile \(home.appending(path: ".ssh/id_acceptance").path)
          UserKnownHostsFile \(known.path)
        Host bastion
          HostName 127.0.0.1
          Port 9
          User deploy
        # group: Production
        Host prod-db
          HostName 127.0.0.1
          ProxyJump bastion
          Port 9
        Host *
          ServerAliveInterval 30
        Match host restricted.example
          User restricted

        """
        let key = "AAAAC3NzaC1lZDI1NTE5AAAAIPfUPYg1znbIXwm8qtmbk2fUgbpCS0X0aPBTqX90D7ND"
        do {
            if !fm.fileExists(atPath: config.path) { try text.write(to: config, atomically: true, encoding: .utf8) }
            if !fm.fileExists(atPath: included.path) {
                try "Host included-demo\n  HostName 127.0.0.1\n  Port 9\n".write(to: included, atomically: true, encoding: .utf8)
            }
            if !fm.fileExists(atPath: known.path) {
                try "demo.example ssh-ed25519 \(key) fixture\n@cert-authority *.corp.example ssh-ed25519 \(key)\n".write(to: known, atomically: true, encoding: .utf8)
            }
        } catch { AppLog.error(.settings, error) }
        defaults.set(config.path, forKey: "configPath")
        defaults.set(known.path, forKey: "knownHostsPath")
        let tools = KeyTools(scanner: KeyScanner(), manager: KeyManager(agentSocket: home.appending(path: "no-agent").path,
            askPassDirectory: home), useKeychain: false, recycle: { _ in }, copyToPasteboard: { _ in })
        let model = AppModel(settings: AppSettings(defaults: defaults, homeDirectory: home),
            backupRoot: home.appending(path: "Backups"), launcherFactory: { _ in FixtureLauncher() }, keyTools: tools)
        return (model, defaults)
    }

    public static func run(runtime: SSHRuntime = .shared, destination: URL) async {
        guard CommandLine.arguments.contains("--ssh-fixture") else { return }
        let model = runtime.model
        var checks: [String: Bool] = [:]
        var failures: [String] = []
        var rows: [[String: Any]] = []
        func record(_ name: String, _ value: Bool) { checks[name] = value }
        func write() {
            let report: [String: Any] = ["checks": checks, "failures": failures, "rows": rows,
                "language": Bundle.main.preferredLocalizations.first ?? "unknown", "isolatedHome": model.settings.homeDirectory.path,
                "realRemoteConnections": false, "terminalLaunchesInFixture": "injected recorder",
                "allChecksPassed": !checks.isEmpty && checks.values.allSatisfy { $0 } && failures.isEmpty]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        runtime.open(.servers)
        try? await Task.sleep(for: .milliseconds(700))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
            failures.append("No visible MacPocket window")
            write()
            return
        }
        let originalFrame = window.frame
        defer { window.setFrame(originalFrame, display: true); runtime.section = .servers; write() }
        do {
            let original = try Data(contentsOf: model.store.fileURL)
            record("parserRoundTrip", model.store.document.render() == String(decoding: original, as: UTF8.self))
            record("includesLoaded", !model.store.includedHosts.isEmpty)
            record("matchPreserved", model.store.document.render().contains("Match host restricted.example"))
            record("customConfigUsesExplicitF", model.commandBuilder.configArguments == ["-F", model.store.fileURL.path])
            let item = SidebarItem.host(alias: "demo-web", occurrence: 0)
            model.select(item)
            let editor = model.editor(for: item)
            editor?.fields["User"] = "acceptance"
            record("hostEditorCommit", editor?.commit() == true)
            let save = model.makeSaveFlow()
            await save.prepare()
            record("saveDiffAndSshValidation", save.canConfirm)
            await save.confirm()
            record("atomicSave", save.phase == .done && !model.store.hasUnsavedChanges)
            let saved = try String(contentsOf: model.store.fileURL, encoding: .utf8)
            record("commentsIncludeMatchRetained", saved.contains("# group: Development") && saved.contains("Include ") && saved.contains("Match host restricted.example"))
            record("backupBeforeSave", !(try model.backupManager.list(kind: model.store.backupKind)).isEmpty)
            await model.effectiveConfig.load("demo-web", using: model.commandBuilder)
            record("realSshG", model.effectiveConfig.options(for: "demo-web")?.first("user") == "acceptance")
            model.toggleFavorite("demo-web")
            record("favoriteToggle", model.memory.isFavorite("demo-web"))
            model.toggleFavorite("demo-web")
            let quick = QuickConnectModel(app: model)
            quick.query = "dm wb"
            record("fuzzySearch", quick.entries.first?.alias == "demo-web")
            let command = HostCommands.sshCommand(for: item, document: model.store.document, builder: model.commandBuilder)
            record("commandIncludesConfig", command?.contains(model.store.fileURL.path) == true)
            let keyURL = model.sshDirectory.appending(path: "id_acceptance")
            if !FileManager.default.fileExists(atPath: keyURL.path) {
                record("actualKeyGeneration", await model.keys.generate(type: .ed25519, fileName: "id_acceptance",
                    comment: "MacPocket acceptance fixture", passphrase: "", assignTo: nil))
            } else { record("actualKeyGeneration", true) }
            await model.keys.refresh()
            record("keyFingerprintAndUsage", model.keys.rows.contains { $0.key.publicKey?.fingerprint.hasPrefix("SHA256:") == true && $0.usedBy.contains("demo-web") })
            // Loopback port 9 intentionally has no service: this exercises real ssh failure classification.
            await model.test(alias: "bastion")
            record("realLoopbackConnectionTest", model.connectionTests.results["bastion"] != nil)
            let backups = BackupsModel(model: model)
            if let first = backups.backups.first {
                try backups.restore(first)
                record("configRestoreIsDraft", model.store.hasUnsavedChanges)
                model.store.discardChanges()
                model.resetEditor()
            } else { record("configRestoreIsDraft", false) }
            // Restore the fixture for repeatable runs, through the normal save path.
            try model.store.apply { $0 = ConfigDocument(parsing: String(decoding: original, as: UTF8.self)) }
            try await model.store.save()
            model.resetEditor()
            record("fixtureRestored", try Data(contentsOf: model.store.fileURL) == original)
            model.select(item)
        } catch { failures.append(String(describing: error)) }

        for width in [960.0, 1280.0] {
            window.setContentSize(NSSize(width: width, height: width == 960 ? 700 : 820))
            for section in SSHSection.allCases {
                runtime.section = section
                try? await Task.sleep(for: .milliseconds(350))
                window.contentView?.layoutSubtreeIfNeeded()
                let nodes = accessibilityNodes(window)
                if section == .keys || section == .knownHosts {
                    let tables = window.contentView.map(nativeTables(in:)) ?? []
                    let dataTables = tables.filter { $0.numberOfColumns >= 5 }
                    let canReachAllColumns = !dataTables.isEmpty && dataTables.allSatisfy { table in
                        guard let scroll = table.enclosingScrollView else { return false }
                        let clip = scroll.contentView
                        let original = clip.bounds.origin
                        let rightEdge = max(0, table.bounds.width - clip.bounds.width)
                        clip.scroll(to: NSPoint(x: rightEdge, y: original.y))
                        scroll.reflectScrolledClipView(clip)
                        let reached = abs(clip.bounds.origin.x - rightEdge) < 2
                        clip.scroll(to: original)
                        scroll.reflectScrolledClipView(clip)
                        return reached
                    }
                    record("tableColumnsReachable-\(section.rawValue)-\(Int(width))", canReachAllColumns)
                }
                rows.append(["section": section.rawValue, "width": width, "elements": nodes.count,
                             "measuredElements": nodes.filter { $0["width"] != nil }.count,
                             "tabFrames": nodes.filter { node in SSHSection.allCases.contains { $0.localizedTitle == node["name"] } },
                             "labels": nodes.map { $0["name"] ?? "" }.filter { !$0.isEmpty }])
                record("visible-\(section.rawValue)-\(Int(width))", nodes.contains { $0["name"]?.contains(section.localizedTitle) == true })
                let allTabsFit = SSHSection.allCases.allSatisfy { tab in
                    nodes.contains { node in
                        guard node["role"] == "AXButton", node["name"] == tab.localizedTitle,
                              let x = Double(node["x"] ?? ""), let tabWidth = Double(node["width"] ?? ""),
                              tabWidth > 0 else { return false }
                        return x >= window.frame.minX - 1 && x + tabWidth <= window.frame.maxX + 1
                    }
                }
                record("tabsFit-\(section.rawValue)-\(Int(width))", allTabsFit)
                if CommandLine.arguments.contains("--audit-ssh-snapshots") {
                    let name = destination.deletingPathExtension().lastPathComponent + "-\(section.rawValue)-\(Int(width)).png"
                    let imageURL = destination.deletingLastPathComponent().appending(path: name)
                    record("snapshot-\(section.rawValue)-\(Int(width))", await snapshot(window, to: imageURL))
                }
                write()
            }
        }
        runtime.section = .servers
        try? await Task.sleep(for: .milliseconds(200))
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: Notification.Name("MacPocket.find"), object: nil)
        try? await Task.sleep(for: .milliseconds(150))
        record("findFocus", window.firstResponder is NSTextView || window.firstResponder is NSTextField)
        record("iconResourcePresent", Bundle.main.url(forResource: "SSHManagerIcon", withExtension: "icns") != nil)
        let resources = Bundle.main.resourceURL?.appending(path: "KeyboardShortcuts_KeyboardShortcuts.bundle")
        record("shortcutResourceBundlePresent", resources.flatMap(Bundle.init(url:)) != nil)
        runtime.showQuickConnect()
        try? await Task.sleep(for: .milliseconds(350))
        let panel = NSApp.windows.first { $0 is QuickConnectPanel && $0.isVisible }
        record("quickConnectPanelShown", panel != nil)
        record("quickConnectPanelSearchFocused", panel?.firstResponder is NSTextView || panel?.firstResponder is NSTextField)
        if let panel {
            if CommandLine.arguments.contains("--audit-ssh-snapshots") {
                let image = destination.deletingPathExtension().lastPathComponent + "-quick-connect.png"
                record("quickConnectSnapshot", await snapshot(panel, to: destination.deletingLastPathComponent().appending(path: image)))
            }
            panel.orderOut(nil)
        }
        write()
    }

    private static func nativeTables(in view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(nativeTables(in:))
    }

    private static func snapshot(_ window: NSWindow, to destination: URL) async -> Bool {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let captured = content.windows.first(where: { Int($0.windowID) == window.windowNumber }) else { return false }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(captured.frame.width * window.backingScaleFactor)
            configuration.height = Int(captured.frame.height * window.backingScaleFactor)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: captured), configuration: configuration)
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
            try png.write(to: destination, options: .atomic)
            return true
        } catch { return false }
    }

    private static func accessibilityNodes(_ root: NSObject) -> [[String: String]] {
        var seen = Set<ObjectIdentifier>(), result: [[String: String]] = [], pending: [NSObject] = [root]
        func attribute(_ element: NSObject, _ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            guard element.responds(to: selector) else { return nil }
            return element.perform(selector)?.takeUnretainedValue()
        }
        while let element = pending.popLast(), result.count < 3_000 {
            guard seen.insert(ObjectIdentifier(element)).inserted else { continue }
            var node = ["role": attribute(element, "accessibilityRole") as? String ?? "",
                "name": ["accessibilityLabel", "accessibilityTitle", "accessibilityDescription", "accessibilityHelp"]
                    .compactMap { attribute(element, $0) as? String }.first(where: { !$0.isEmpty }) ?? ""]
            if let accessible = element as? any NSAccessibilityProtocol {
                let rect = accessible.accessibilityFrame()
                node["x"] = String(Double(rect.minX))
                node["y"] = String(Double(rect.minY))
                node["width"] = String(Double(rect.width))
                node["height"] = String(Double(rect.height))
            } else if let rect = accessibilityFrame(of: element) {
                node["x"] = String(Double(rect.minX))
                node["y"] = String(Double(rect.minY))
                node["width"] = String(Double(rect.width))
                node["height"] = String(Double(rect.height))
            }
            result.append(node)
            pending += attribute(element, "accessibilityChildren") as? [NSObject] ?? []
        }
        return result
    }

    /// SwiftUI's private AX objects implement the getter without declaring NSAccessibilityProtocol.
    /// Validate the method's ABI before calling its Objective-C implementation.
    private static func accessibilityFrame(of element: NSObject) -> CGRect? {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard let method = class_getInstanceMethod(type(of: element), selector) else { return nil }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType).hasPrefix("{CGRect=") else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(element, selector)
    }
}

private struct FixtureLauncher: TerminalLaunching {
    func launch(_ request: LaunchRequest) async throws {}
}
#endif
