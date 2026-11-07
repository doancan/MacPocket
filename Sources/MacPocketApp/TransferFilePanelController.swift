#if DEBUG
import AppKit
@preconcurrency import ApplicationServices
import Darwin

/// The isolated UI has no cross-process TCC grant. This production-identity controller
/// operates only its attached file sheets, through real AX controls in the OS view service.
@MainActor enum TransferFilePanelController {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--audit-transfer-file-controller"),args.indices.contains(index+1) else { return }
        let root = URL(fileURLWithPath: args[index+1]).standardizedFileURL.resolvingSymlinksInPath()
        let expected = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("switcher-audit").standardizedFileURL.resolvingSymlinksInPath()
        guard Bundle.main.bundleIdentifier == "com.doancan.MacPocket",root.path == expected.path else { exit(2) }
        let driver = FileControllerDriver(root: root),app = NSApplication.shared
        app.setActivationPolicy(.accessory);app.delegate = driver
        withExtendedLifetime(driver) { app.run() };exit(0)
    }
}

@MainActor private final class FileControllerDriver: NSObject,NSApplicationDelegate {
    let root: URL
    private let started = Date()
    private var performed = Set<String>(),traces: [[String:Any]] = []
    init(root: URL) { self.root = root }
    func applicationDidFinishLaunching(_ notification: Notification) {
        write(["accessibility": AXIsProcessTrusted(),"applicationStateStarted": false],name: "file-controller-ready.json")
        Task { @MainActor in
            let limit = ContinuousClock.now + .seconds(600)
            while !FileManager.default.fileExists(atPath: root.appendingPathComponent("file-controller.stop").path),ContinuousClock.now < limit {
                if AXIsProcessTrusted() { scan() }
                try? await Task.sleep(for: .milliseconds(100))
            }
            write(["actions": traces,"accessibility": AXIsProcessTrusted(),"applicationStateStarted": false],name: "file-controller-report.json")
            NSApp.terminate(nil)
        }
    }
    private func scan() {
        for language in ["tr","en"] {
            let base = root.appendingPathComponent(language)
            let folders = (try? FileManager.default.contentsOfDirectory(at: base,includingPropertiesForKeys: nil)) ?? []
            for folder in folders where folder.lastPathComponent.hasPrefix("real-transfer-") {
                for name in ["driver-save-cancel.json","driver-save-accept.json","driver-open-cancel.json","driver-open-accept.json"] {
                    let file = folder.appendingPathComponent(name)
                    guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                          let modified = attributes[.modificationDate] as? Date,modified >= started,
                          let bytes = try? Data(contentsOf: file),bytes.count < 16384,
                          let request = try? JSONSerialization.jsonObject(with: bytes) as? [String:Any] else { continue }
                    control(request,file: file,folder: folder)
                }
            }
        }
    }
    private func control(_ request: [String:Any],file: URL,folder: URL) {
        guard let pid = request["hostPID"] as? Int32,let launch = request["hostLaunch"] as? Double,
              pid > 0,launch.isFinite,launch > 0,
              let parentID = request["sheetParentID"] as? Int,parentID > 0,parentID <= UInt32.max,let phase = request["phase"] as? String,
              ["cancel","accept","select-file"].contains(phase),let token = request["token"] as? String,UUID(uuidString: token) != nil,
              let targetPath = request["filePath"] as? String,let deadline = request["deadline"] as? Double,deadline.isFinite,deadline > Date().timeIntervalSince1970,
              let app = NSRunningApplication(processIdentifier: pid),!app.isTerminated,app.bundleIdentifier?.hasSuffix(".SwitcherAudit") == true,
              let appURL = app.bundleURL,appURL.deletingLastPathComponent().standardizedFileURL.path == root.path,
              let actualLaunch = app.launchDate?.timeIntervalSince1970,abs(actualLaunch-launch) < 0.001 else { return }
        let target = URL(fileURLWithPath: targetPath).standardizedFileURL.resolvingSymlinksInPath()
        guard target.deletingLastPathComponent() == folder.standardizedFileURL.resolvingSymlinksInPath(),
              ["cancel-export.json","export-nine-profiles.json","invalid-profiles.json"].contains(target.lastPathComponent) else { return }
        let identity = token+phase
        guard !performed.contains(identity) else { return }
        let application = AXUIElementCreateApplication(pid)
        let windows = value(application,kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let parent = windows.first(where: { number($0) == UInt32(parentID) }) else {
            write(["reason": "parent-window-not-found","hostPID": pid,"windowIDs": windows.compactMap(number)],name: "file-controller-last-pending.json");return
        }
        let sheet = (value(parent,"AXSheets") as? [AXUIElement])?.first ?? parent
        var pending: [AXUIElement] = [sheet],seen = Set<CFHashCode>(),nodes: [AXUIElement] = []
        let until = ContinuousClock.now + .milliseconds(700)
        while let node = pending.popLast(),nodes.count < 256,ContinuousClock.now < until {
            guard seen.insert(CFHash(node)).inserted else { continue }
            nodes.append(node)
            pending += (value(node,kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(80)
        }
        var acted = false,issued = false
        var response: Int32?
        if phase == "select-file" {
            let names = [target.lastPathComponent,target.deletingPathExtension().lastPathComponent]
            if let match = nodes.first(where: { node in [kAXTitleAttribute,kAXValueAttribute,kAXDescriptionAttribute].contains { key in
                (value(node,key) as? String).map { names.contains($0) } == true
            } }) {
                var current: AXUIElement? = match
                for _ in 0..<5 {
                    guard let node = current else { break }
                    var settable = DarwinBoolean(false)
                    if AXUIElementIsAttributeSettable(node,kAXSelectedAttribute as CFString,&settable) == .success,settable.boolValue,
                       AXUIElementSetAttributeValue(node,kAXSelectedAttribute as CFString,kCFBooleanTrue) == .success { acted = true;break }
                    if (value(node,kAXRoleAttribute) as? String) == kAXRowRole as String,
                       AXUIElementPerformAction(node,kAXPressAction as CFString) == .success { acted = true;break }
                    current = element(node,kAXParentAttribute)
                }
            }
        } else {
            let labels = phase == "cancel" ? ["Cancel","İptal","Vazgeç"] : [request["prompt"] as? String ?? ""]
            if let button = nodes.first(where: { value($0,kAXRoleAttribute) as? String == kAXButtonRole as String
                && labels.contains(value($0,kAXTitleAttribute) as? String ?? "") && (value($0,kAXEnabledAttribute) as? Bool) != false }) {
                let status = AXUIElementPerformAction(button,kAXPressAction as CFString)
                issued = true;response = status.rawValue;acted = status == .success
            }
        }
        if acted || issued {
            // Closing a sheet can invalidate its AX reply before the response arrives. Record
            // the return code, never replay the click, and let the real file/prefs result prove it.
            performed.insert(identity);traces.append(["token": token,"phase": phase,"hostPID": pid,"parentID": parentID,"file": target.lastPathComponent,"nodes": nodes.count,"AXResponse": response ?? 0])
            write(["actions": traces,"applicationStateStarted": false],name: "file-controller-progress.json")
        } else {
            let roles = nodes.reduce(into: [String:Int]()) { result,node in result[value(node,kAXRoleAttribute) as? String ?? "unknown",default: 0] += 1 }
            write(["phase": phase,"roles": roles,"hostPID": pid,"parentID": parentID],name: "file-controller-last-pending.json")
        }
    }
    private func value(_ node: AXUIElement,_ key: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(node,0.01);var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(node,key as CFString,&result) == .success ? result : nil
    }
    private func element(_ node: AXUIElement,_ key: String) -> AXUIElement? {
        guard let result = value(node,key),CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(result,to: AXUIElement.self)
    }
    private func number(_ node: AXUIElement) -> UInt32? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),"_AXUIElementGetWindow") else { return nil }
        var id: CGWindowID = 0
        typealias Read = @convention(c) (AXUIElement,UnsafeMutablePointer<CGWindowID>) -> AXError
        return unsafeBitCast(symbol,to: Read.self)(node,&id) == .success ? id : nil
    }
    private func write(_ record: [String:Any],name: String) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: record,options: [.prettyPrinted,.sortedKeys]) else { return }
        try? bytes.write(to: root.appendingPathComponent(name),options: .atomic)
    }
}
#endif
