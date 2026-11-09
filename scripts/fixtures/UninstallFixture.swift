import AppKit
import Darwin

@MainActor final class UninstallFixtureDelegate: NSObject, NSApplicationDelegate {
    private func argument(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("uninstall-worker") else { NSApp.terminate(nil); return }
        var pid: pid_t = 0
        var arguments = [executable.path]
        if CommandLine.arguments.contains("--stubborn-helper") { arguments.append("ignore-term") }
        var argv = arguments.map { strdup($0) } + [nil]
        defer { for value in argv { free(value) } }
        do {
            guard posix_spawn(&pid, executable.path, nil, nil, &argv, environ) == 0 else { throw POSIXError(.EIO) }
            if let destination = argument("--ready") {
                let state = ["pid": ProcessInfo.processInfo.processIdentifier, "helper": pid]
                try JSONSerialization.data(withJSONObject: state).write(to: URL(fileURLWithPath: destination), options: .atomic)
            }
        } catch { NSApp.terminate(nil) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let refuse = CommandLine.arguments.contains("--refuse-quit")
        if let preference = argument("--preference") {
            if !refuse { try? Data("saved by the owned fixture on normal quit".utf8).write(to: URL(fileURLWithPath: preference), options: .atomic) }
        }
        if let ready = argument("--ready"), let data = try? JSONSerialization.data(withJSONObject: ["args":CommandLine.arguments,"refused":refuse]) {
            try? data.write(to: URL(fileURLWithPath: ready + ".quit"), options: .atomic)
        }
        if refuse { return .terminateCancel }
        // The helper deliberately outlives the GUI, so the production coordinator must stop it.
        return .terminateNow
    }
}
@main enum UninstallFixture {
    @MainActor static func main() {
        let app = NSApplication.shared, delegate = UninstallFixtureDelegate()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
