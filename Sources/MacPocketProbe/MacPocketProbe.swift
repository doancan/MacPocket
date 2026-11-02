import AppKit
import Foundation
import MacPocketCore
import Darwin

@main
struct MacPocketProbe {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            switch arguments.first ?? "help" {
            case "system":
                let monitor = SystemMonitor()
                _ = try await monitor.snapshot()
                try await Task.sleep(for: .milliseconds(700))
                try output(try await monitor.snapshot())
            case "processes":
                let monitor = ProcessMonitor()
                _ = try await monitor.snapshot()
                try await Task.sleep(for: .milliseconds(700))
                let snapshot = try await monitor.snapshot()
                try output(snapshot)
            case "diagnostic":
                guard (2...3).contains(arguments.count),
                      let diagnostic = SystemDiagnostic(rawValue: arguments[1]) else {
                    throw ProbeError.usage("diagnostic: " + SystemDiagnostic.allCases.map(\.rawValue).joined(separator: ", "))
                }
                var processID: Int32?
                if arguments.count == 3 {
                    if arguments[2] == "self" { processID = getpid() }
                    else if let pid = Int32(arguments[2]), pid > 0 { processID = pid }
                    else { throw ProbeError.usage("diagnostic openFiles <positive PID|self>") }
                }
                try output(try await SystemDiagnostics.run(diagnostic, processID: processID))
            case "terminate":
                guard arguments.count >= 2, let pid = Int32(arguments[1]), pid > 1,
                      arguments.dropFirst(2).allSatisfy({ $0 == "--force" }) else {
                    throw ProbeError.usage("terminate <PID> [--force]")
                }
                let monitor = ProcessMonitor()
                _ = try await monitor.snapshot()
                try await monitor.terminate(pid: pid, force: arguments.contains("--force"))
                try output(["status": "signal-sent", "pid": String(pid)])
            case "windows":
                let report = await WindowCatalog().snapshot()
                let rows = WindowFiltering.apply(report.windows, includeWindowless: arguments.contains("--all")).map { window in
                    ProbeWindow(id: window.id, windowID: window.windowID, application: window.application, title: window.title,
                                minimized: window.minimized, hidden: window.hidden, otherSpace: window.otherSpace,
                                display: window.displayID, actionable: window.windowAccessible)
                }
                try output(ProbeWindowList(accessibility: report.accessibilityGranted, otherSpacesVisible: report.otherSpacesVisible,
                                           partial: report.partial, windows: rows))
            case "focus":
                guard arguments.count == 2 else { throw ProbeError.usage("focus <windowID|id>") }
                let catalog = WindowCatalog()
                let report = await catalog.snapshot()
                guard let target = report.windows.first(where: { $0.id == arguments[1] || $0.windowID.map(String.init) == arguments[1] }) else {
                    throw ProbeError.usage("Pencere bulunamadı: \(arguments[1]). `windows` ile listele.")
                }
                try await catalog.focus(target.id)
                try output(["status": "focused", "application": target.application, "title": target.title])
            case "thumbnail":
                guard arguments.count == 3 else { throw ProbeError.usage("thumbnail <windowID> <output.png>") }
                let report = await WindowCatalog().snapshot()
                guard let target = report.windows.first(where: { $0.windowID.map(String.init) == arguments[1] }) else {
                    throw ProbeError.usage("Pencere bulunamadı: \(arguments[1])")
                }
                try await WindowPreviewProvider().preview(target).write(to: URL(fileURLWithPath: arguments[2]))
                try output(["status": "saved", "path": arguments[2]])
            case "privacy":
                let apps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningAppInfo? in
                    app.bundleIdentifier.map { RunningAppInfo(pid: app.processIdentifier, bundleID: $0, name: app.localizedName ?? $0) }
                }
                let active = PrivacyProbe.activities(apps: apps).sorted { $0.id < $1.id }
                try output(active.map { ["device": $0.device.rawValue, "bundleID": $0.bundleID ?? "", "app": $0.appName ?? ""] })
            case "help", "--help", "-h":
                print("""
                macpocket-probe — native MacPocket development and validation tool
                  system                       Live CPU, RAM, volumes and power snapshot
                  processes                    Live process snapshot (interval CPU)
                  diagnostic <name> [PID]      Fixed read-only diagnostic; PID/self for openFiles
                  terminate <PID> [--force]    Signal an eligible same-user process
                  windows [--all]              Switchable windows on every Space (--all adds windowless apps)
                  focus <windowID|id>          Bring a window to the front (switches Space when needed)
                  thumbnail <windowID> <png>   Capture one window (Screen Recording access required)
                  privacy                      Microphone and camera use right now (apps that are listening/recording)
                Diagnostics: \(SystemDiagnostic.allCases.map(\.rawValue).joined(separator: ", "))
                """)
            default:
                throw ProbeError.usage("Unknown command. Use --help.")
            }
        } catch {
            FileHandle.standardError.write(Data("MacPocket: \(error)\n".utf8))
            exit(1)
        }
    }

    static func output<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    var description: String {
        switch self { case .usage(let text): return text }
    }
}

struct ProbeWindow: Encodable {
    let id: String
    let windowID: UInt32?
    let application: String
    let title: String
    let minimized: Bool
    let hidden: Bool
    let otherSpace: Bool
    let display: UInt32?
    let actionable: Bool
}

struct ProbeWindowList: Encodable {
    let accessibility: Bool
    let otherSpacesVisible: Bool
    let partial: Bool
    let windows: [ProbeWindow]
}
