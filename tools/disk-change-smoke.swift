import AppKit

@MainActor final class DiskChangeAudit: NSObject, NSApplicationDelegate {
    private var notifications = 0
    private let observer = DiskChangeObservation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await run(); NSApp.terminate(nil) }
    }

    private func waitForChange(after count: Int) async -> Bool {
        for _ in 0..<100 {
            if notifications > count { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }

    private nonisolated static func command(_ path: String, _ arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.standardError
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NSError(domain: path, code: Int(process.terminationStatus)) }
            return data
        }.value
    }

    private func run() async {
        let report = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = report.deletingLastPathComponent().appendingPathComponent("fixture-" + UUID().uuidString)
        var checks: [String: Bool] = [:]
        var failure: String?
        var device: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            checks["registered"] = observer.start { [weak self] in self?.notifications += 1 }
            checks["initialDiscovery"] = await waitForChange(after: 0)
            try await Task.sleep(for: .milliseconds(500))
            let quietCount = notifications
            try await Task.sleep(for: .milliseconds(3200))
            checks["idleHasNoRepeatedRefresh"] = notifications == quietCount
            let image = directory.appendingPathComponent("fixture.sparseimage")
            let mount = directory.appendingPathComponent("mount")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            _ = try await Self.command("/usr/bin/hdiutil", ["create", "-size", "64m", "-fs", "APFS", "-volname", "MacPocketDiskAudit", "-type", "SPARSE", image.path])
            let beforeAttach = notifications
            let data = try await Self.command("/usr/bin/hdiutil", ["attach", "-nobrowse", "-mountpoint", mount.path, "-plist", image.path])
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            device = (plist?["system-entities"] as? [[String: Any]])?.compactMap { $0["dev-entry"] as? String }.first
            guard let mountedDevice = device, mountedDevice.range(of: #"^/dev/disk[0-9]+$"#, options: .regularExpression) != nil else {
                throw NSError(domain: "DiskChangeAudit.attach", code: 1)
            }
            checks["imageAppearance"] = await waitForChange(after: beforeAttach)
            try await Task.sleep(for: .milliseconds(300))
            let beforeRename = notifications
            _ = try await Self.command("/usr/sbin/diskutil", ["renameVolume", mount.path, "MacPocketDiskAuditRenamed"])
            checks["volumeDescriptionChange"] = await waitForChange(after: beforeRename)
            let beforeDetach = notifications
            _ = try await Self.command("/usr/bin/hdiutil", ["detach", mountedDevice])
            device = nil
            checks["imageDisappearance"] = await waitForChange(after: beforeDetach)
            observer.stop()
            let stoppedCount = notifications
            try await Task.sleep(for: .milliseconds(500))
            checks["stopCancelsCallbacks"] = notifications == stoppedCount
            _ = observer.start { [weak self] in self?.notifications += 1 }
            checks["restartDiscoversDisks"] = await waitForChange(after: stoppedCount)
        } catch { failure = error.localizedDescription }
        observer.stop()
        if let attachedDevice = device {
            do { _ = try await Self.command("/usr/bin/hdiutil", ["detach", attachedDevice]); device = nil }
            catch { failure = (failure ?? "") + " cleanup: " + error.localizedDescription }
        }
        if device == nil { try? FileManager.default.removeItem(at: directory) }
        let result: [String: Any] = ["passed":failure == nil && checks.count == 8 && checks.values.allSatisfy { $0 },
            "checks":checks,"notifications":notifications,"error":failure ?? "", "fixtureDirectory":directory.path]
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: report)
    }

}

@main enum DiskChangeAuditMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = DiskChangeAudit()
        application.setActivationPolicy(.prohibited)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
