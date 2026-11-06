#if DEBUG
import AppKit
import SwiftUI
import MacPocketCore

/// Read-only traversal of the app's own accessibility objects. Does not press controls or request permissions.
@MainActor
enum ToolUIAudit {
    static var practicalWorkspace: PracticalWorkspace?

    static func runPractical(destination: URL) async {
        let model = PocketApplicationState.shared.model
        let workspace = PracticalWorkspace(defaults: nil)
        practicalWorkspace = workspace
        model.openMainWindow?()
        model.navigation.select(.tools)
        try? await Task.sleep(for: .seconds(1))
        model.navigation.select(.practical)
        try? await Task.sleep(for: .milliseconds(300))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        let originalFrame = window.frame
        var rows: [[String: Any]] = []
        for width in [960.0, 1280.0] {
            window.setContentSize(NSSize(width: width, height: width == 960 ? 680 : 820))
            for tool in PracticalTool.allCases {
                workspace.selected = tool
                workspace.update(PracticalExecution.example(tool, draft: PracticalDraft()), for: tool)
                workspace.run(tool)
                while workspace.running != nil { try? await Task.sleep(for: .milliseconds(30)) }
                try? await Task.sleep(for: .milliseconds(350))
                window.contentView?.layoutSubtreeIfNeeded()
                let nodes = accessibilityNodes(window)
                let outside = nodes.filter { node in
                    guard ["AXButton", "AXCheckBox", "AXTextField", "AXPopUpButton"].contains(node["role"] ?? ""),
                          let x = Double(node["x"] ?? ""), let y = Double(node["y"] ?? ""),
                          let width = Double(node["width"] ?? ""), let height = Double(node["height"] ?? ""),
                          width > 0, height > 0, y + height > window.frame.minY, y < window.frame.maxY else { return false }
                    return x < window.frame.minX - 2 || x + width > window.frame.maxX + 2
                }
                rows.append(["tool": tool.id, "width": width, "result": workspace.results[tool] != nil,
                             "error": workspace.errors[tool] ?? "", "elements": nodes.count,
                             "measuredElements": nodes.filter { $0["width"] != nil }.count,
                             "horizontalOverflowHeuristic": outside])
                let report: [String: Any] = ["rows": rows, "language": Bundle.main.preferredLocalizations.first ?? "unknown",
                                             "usesIsolatedWorkspace": true]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: destination, options: .atomic)
                }
            }
        }
        var checks: [String: Bool] = [:]
        func exercise(_ tool: PracticalTool, _ draft: PracticalDraft, errorExpected: Bool = false) async -> Bool {
            workspace.selected = tool; workspace.update(draft, for: tool); workspace.run(tool)
            while workspace.running != nil { try? await Task.sleep(for: .milliseconds(30)) }
            return errorExpected ? workspace.errors[tool] != nil && workspace.results[tool] == nil
                : workspace.errors[tool] == nil && workspace.results[tool] != nil
        }
        var variant = PracticalDraft(); variant.reverse = true; variant.urlSafe = true; variant.input = "TWFjUG9ja2V0"
        checks["base64Decode"] = await exercise(.base64, variant)
        variant = PracticalDraft(); variant.reverse = true; variant.input = "Merhaba%20%C4%B0zmir"
        checks["urlDecode"] = await exercise(.url, variant)
        variant = PracticalDraft(); variant.reverse = true; variant.milliseconds = true; variant.input = "2026-11-05T12:30:00+03:00"
        checks["dateToUnix"] = await exercise(.timestamp, variant)
        variant = PracticalDraft(); variant.wifi = true; variant.ssid = "MacPocket Demo"; variant.wifiPassword = "example-only-123"
        checks["wifiQR"] = await exercise(.qr, variant)
        variant = PracticalDraft(); variant.input = "[1,]"
        checks["invalidJSON"] = await exercise(.json, variant, errorExpected: true)
        checks["errorRecovery"] = await exercise(.json, PracticalExecution.example(.json, draft: PracticalDraft()))
        workspace.toggleFavorite(.json); checks["favoriteOn"] = workspace.favorites.contains(.json)
        workspace.toggleFavorite(.json); checks["favoriteOff"] = !workspace.favorites.contains(.json)
        workspace.clear(.json); checks["clear"] = workspace.results[.json] == nil && workspace.draft(for: .json).input.isEmpty
        variant = PracticalExecution.example(.caseConverter, draft: PracticalDraft())
        checks["caseAllFormats"] = await exercise(.caseConverter, variant)
            && workspace.results[.caseConverter]?.casePreviews.count == CaseFormat.allCases.count
        workspace.selectCaseFormat(.snake)
        checks["caseInstantSelection"] = workspace.running == nil && workspace.results[.caseConverter]?.text
            == workspace.results[.caseConverter]?.casePreviews.first(where: { $0.format == .snake })?.text
        variant = PracticalDraft(); variant.input = "İZMİR ŞEHİR"; variant.caseOptions.language = .turkish
        variant.caseOptions.simplifyLatin = true
        checks["caseTurkishASCII"] = await exercise(.caseConverter, variant)
            && workspace.results[.caseConverter]?.text == "izmirSehir"
        func waitForCasePreview() async -> Bool {
            for _ in 0..<60 {
                if workspace.results[.caseConverter] != nil && workspace.running == nil { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }
        variant = PracticalDraft(); variant.caseOptions.language = .english; variant.input = "livePreview"
        workspace.update(variant, for: .caseConverter)
        checks["caseLivePreview"] = await waitForCasePreview()
            && workspace.results[.caseConverter]?.text == "livePreview"
        variant.input = "old value"; workspace.update(variant, for: .caseConverter)
        variant.input = "new value"; workspace.update(variant, for: .caseConverter)
        checks["caseLatestEditWins"] = await waitForCasePreview()
            && workspace.results[.caseConverter]?.text == "newValue"
        variant.caseLive = false; variant.input = "manual conversion"
        workspace.update(variant, for: .caseConverter)
        try? await Task.sleep(for: .milliseconds(400))
        checks["caseManualModeIdle"] = workspace.running == nil && workspace.results[.caseConverter] == nil
        checks["caseManualModeRun"] = await exercise(.caseConverter, variant)
            && workspace.results[.caseConverter]?.text == "manualConversion"
        variant.caseLive = true; variant.input = "discard pending"
        workspace.update(variant, for: .caseConverter); workspace.clear(.caseConverter)
        try? await Task.sleep(for: .milliseconds(400))
        checks["caseClearCancelsPreview"] = workspace.running == nil && workspace.results[.caseConverter] == nil
            && workspace.draft(for: .caseConverter).input.isEmpty
        window.makeFirstResponder(window)
        NotificationCenter.default.post(name: .pocketFind, object: nil)
        try? await Task.sleep(for: .milliseconds(150))
        checks["searchFocus"] = window.firstResponder is NSTextView || window.firstResponder is NSTextField
        let final: [String: Any] = ["rows": rows, "language": Bundle.main.preferredLocalizations.first ?? "unknown",
                                    "usesIsolatedWorkspace": true, "checks": checks]
        if let data = try? JSONSerialization.data(withJSONObject: final, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destination, options: .atomic)
        }
        window.setFrame(originalFrame, display: true)
        model.navigation.select(.tools)
        try? await Task.sleep(for: .milliseconds(200))
        practicalWorkspace = nil
        model.navigation.select(.practical)
    }

    static func run(destination: URL) async {
        let model = PocketApplicationState.shared.model
        model.openMainWindow?()
        var mainWindow: NSWindow?
        for _ in 0..<40 {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) { mainWindow = window; break }
            model.openMainWindow?()
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let window = mainWindow else {
            let failure = Data(#"{"error":"No visible main window available for the read-only audit."}"#.utf8)
            try? failure.write(to: destination, options: .atomic)
            return
        }
        let originalFrame = window.frame
        var rows: [[String: Any]] = []
        let changed = ["startup-items", "network-traffic", "peripherals", "usb-eject", "disk-health", "bluetooth-battery",
                       "audio", "recorder", "support-report", "task-manager", "system-reports", "local-network", "screen-cleaning"]
        let tools = CommandLine.arguments.contains("--audit-tools-changed") ? changed : ToolsHubView.diagnosticCatalogIDs
        func save() {
            let report: [String: Any] = ["rows": rows, "scope": "read-only navigation and in-process accessibility tree",
                                         "interactiveActionsTested": false,
                                         "language": Bundle.main.preferredLocalizations.first ?? "unknown"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        for width in [960.0, 1280.0] {
            window.setContentSize(NSSize(width: width, height: width == 960 ? 680 : 820))
            for id in tools {
                NotificationCenter.default.post(name: .pocketOpenTool, object: id)
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                window.contentView?.layoutSubtreeIfNeeded()
                var searchFocused = false
                if ["startup-items", "task-manager"].contains(id) {
                    NotificationCenter.default.post(name: .pocketFind, object: nil)
                    try? await Task.sleep(for: .milliseconds(150))
                    searchFocused = window.firstResponder is NSTextView || window.firstResponder is NSTextField
                }
                let nodes = accessibilityNodes(window)
                let clipped = nodes.filter { node in
                    guard ["AXButton", "AXCheckBox", "AXTextField", "AXPopUpButton"].contains(node["role"] ?? ""),
                          let x = Double(node["x"] ?? ""), let y = Double(node["y"] ?? ""),
                          let width = Double(node["width"] ?? ""), let height = Double(node["height"] ?? ""),
                          width > 0, height > 0, y + height > window.frame.minY, y < window.frame.maxY else { return false }
                    return x < window.frame.minX - 2 || x + width > window.frame.maxX + 2
                }
                rows.append(["tool": id, "width": window.frame.width, "height": window.frame.height,
                             "navigation": model.navigation.title, "searchFocusAfterFind": searchFocused,
                             "elements": nodes.count,
                             "buttons": nodes.filter { $0["role"] == "AXButton" }.count,
                             "horizontalOverflowHeuristic": clipped,
                             "unnamedButtons": nodes.filter { $0["role"] == "AXButton" && $0["name"] == "" }.count,
                             "labels": nodes.compactMap { $0["name"] }.filter { !$0.isEmpty }])
                save()
            }
            model.navigation.select(.tools)
            try? await Task.sleep(for: .milliseconds(650))
            NotificationCenter.default.post(name: .pocketFind, object: nil)
            try? await Task.sleep(for: .milliseconds(150))
            let hubFocus = window.firstResponder is NSTextView || window.firstResponder is NSTextField
            rows.append(["tool": "hub", "width": width, "navigation": model.navigation.title, "searchFocusAfterFind": hubFocus])
            save()
        }
        window.setFrame(originalFrame, display: true)
        model.navigation.select(.tools)
    }

    static func accessibilityNodes(_ root: NSObject) -> [[String: String]] {
        var seen = Set<ObjectIdentifier>(), result: [[String: String]] = []
        var pending: [NSObject] = [root]
        func attribute(_ element: NSObject, _ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            guard element.responds(to: selector) else { return nil }
            return element.perform(selector)?.takeUnretainedValue()
        }
        while let element = pending.popLast(), result.count < 2_000 {
            guard seen.insert(ObjectIdentifier(element)).inserted else { continue }
            let role = attribute(element, "accessibilityRole") as? String ?? ""
            let label = ["accessibilityLabel", "accessibilityTitle", "accessibilityDescription", "accessibilityHelp"]
                .compactMap { attribute(element, $0) as? String }.first(where: { !$0.isEmpty }) ?? ""
            var node = ["role": role, "name": label]
            if let accessible = element as? any NSAccessibilityProtocol {
                let rect = accessible.accessibilityFrame()
                node["x"] = String(Double(rect.minX)); node["y"] = String(Double(rect.minY))
                node["width"] = String(Double(rect.width)); node["height"] = String(Double(rect.height))
            }
            result.append(node)
            pending += attribute(element, "accessibilityChildren") as? [NSObject] ?? []
        }
        return result
    }
}
#endif
