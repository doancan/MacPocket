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
            case "help", "--help", "-h":
                print("""
                macpocket-probe — native MacPocket development and validation tool
                  system                       Live CPU, RAM, volumes and power snapshot
                  processes                    Live process snapshot (interval CPU)
                  diagnostic <name> [PID]      Fixed read-only diagnostic; PID/self for openFiles
                  terminate <PID> [--force]    Signal an eligible same-user process
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
