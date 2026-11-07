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
            case "switcher":
                let request = SwitcherCLIRequest(command: try SwitcherCLICommand.parse(Array(arguments.dropFirst())))
                let response = try await Task.detached { try SwitcherCLITransport.send(request) }.value
                try output(response)
                if response.errorCode != nil { exit(2) }
            case "usb-eject":
                let disks = try await USBEject.load()
                try output(disks.map { ["id": $0.id, "name": $0.name, "mounts": $0.mountPaths.joined(separator: ", ")] })
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
            case "cleanup":
                // Read-only: lists what a cleanup scan finds, nothing is moved.
                let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                let control = StorageScanControl(maximumDuration: 90, maximumEntries: 4_000_000)
                let report = try await CleanupScanner().scan(CleanupCatalog.targets(home: home), control: control)
                try output(report.targets.map { ["target": $0.id.rawValue, "group": $0.target.group.rawValue, "state": "\($0.state)",
                                                 "items": String($0.items.count), "bytes": String($0.bytes),
                                                 "names": $0.items.prefix(4).map { $0.label ?? $0.name }.joined(separator: ", ")] })
            case "startup":
                let snapshot = await StartupItems.load()
                try output(snapshot.items.map { ["label": $0.label, "class": $0.kind.rawValue, "enabled": String($0.isEnabled),
                                                 "app": $0.appName ?? "", "stateKnown": String(snapshot.stateKnown)] })
            case "lan", "lan-macs":
                // `lan` scans the primary network; `lan 192.168.2.0/24` scans a routed range.
                var result: LANScanResult
                if arguments.count > 1, let subnet = LANSubnet.parse(cidr: arguments[1]) {
                    let network = LANScanner.customNetwork(subnet, name: arguments[1], attached: await LANScanner.availableNetworks())
                    result = try await LANScanner.scan(networks: [network])[0]
                } else {
                    result = try await LANScanner.scan()
                }
                if arguments.first == "lan-macs" {
                    let interface = result.network.isLocal ? result.network.interface : result.network.viaInterface
                    let entries = try await LANOnLinkProbe.run(subnet: result.network.subnet, interface: interface,
                                                               hosts: result.network.subnet.hosts.map(IPv4.text))
                    result = result.mergingARP(entries)
                }
                print("\(result.network.interface) \(result.network.address) \(result.network.subnet.description) gateway \(result.network.gateway ?? "-")")
                for device in result.devices {
                    let latency = device.latency.map { String(format: "%.0f ms", $0 * 1000) } ?? "-"
                    print([device.ip, device.mac ?? "-", device.kind.rawValue, latency, device.displayName ?? "-",
                           device.model ?? "", device.services.sorted().joined(separator: ","),
                           device.mac.map { _ in device.macSource.rawValue } ?? ""].joined(separator: " | "))
                }
            case "lan-networks":
                for network in await LANScanner.availableNetworks() {
                    print([network.interface, network.name, network.kind.rawValue, network.address, network.subnet.description,
                           network.gateway ?? "-", network.isPrimary ? "primary" : ""].joined(separator: " | "))
                }
            case "power-schedule":
                print(PowerScheduleReader.read())
            case "maintenance":
                // `maintenance` lists tasks and support; `maintenance run <id>` runs one ready task.
                let tasks = MaintenanceCatalog.tasks()
                if arguments.count == 3, arguments[1] == "run" {
                    guard let task = tasks.first(where: { $0.id.rawValue == arguments[2] }) else {
                        throw ProbeError.usage("maintenance run <\(tasks.map(\.id.rawValue).joined(separator: "|"))>")
                    }
                    let result = await MaintenanceRunner.run([task])
                    try output(result.map { ["task": $0.task.id.rawValue, "outcome": "\($0.outcome)"] })
                } else {
                    try output(tasks.map { ["task": $0.id.rawValue, "support": "\($0.support)"] })
                }
            case "fans":
                guard let transport = AppleSMCTransport() else { throw ProbeError.usage("AppleSMC is not reachable") }
                try output(try fanReport(FanController(transport: transport)))
            case "fan-set":
                guard arguments.count == 3, let fan = Int(arguments[1]), let rpm = Double(arguments[2]) else {
                    throw ProbeError.usage("fan-set <fan> <rpm> (needs root; ends with fan-release)")
                }
                guard let transport = AppleSMCTransport() else { throw ProbeError.usage("AppleSMC is not reachable") }
                let controller = FanController(transport: transport)
                try controller.setTarget(fan: fan, rpm: rpm)
                try output(try fanReport(controller))
            case "fan-release":
                guard let transport = AppleSMCTransport() else { throw ProbeError.usage("AppleSMC is not reachable") }
                let controller = FanController(transport: transport)
                controller.releaseAll()
                try output(try fanReport(controller))
            case "ddc":
                // Read-only: brightness, speaker volume and mute of every external display that answers DDC/CI.
                try output(DisplayRegistry.scan().map { display -> [String: String] in
                    var row = ["vendor": String(display.vendor), "product": String(display.product)]
                    guard let id = display.avServiceID, let channel = DDCChannel(registryID: id) else { row["ddc"] = "none"; return row }
                    for (name, code) in [("brightness", VCPCode.brightness), ("volume", .volume), ("mute", .audioMute)] {
                        row[name] = channel.get(code).map { "\($0.current)/\($0.maximum)" } ?? "no reply"
                    }
                    return row
                })
            case "ddc-set":
                // Development aid: ddc-set <display index> <brightness|volume|mute> <value>
                guard arguments.count == 4, let index = Int(arguments[1]), let value = UInt16(arguments[3]),
                      let code = ["brightness": VCPCode.brightness, "volume": .volume, "mute": .audioMute][arguments[2]] else {
                    throw ProbeError.usage("ddc-set <display index> <brightness|volume|mute> <value>")
                }
                let displays = DisplayRegistry.scan().filter { $0.avServiceID != nil }
                guard displays.indices.contains(index), let id = displays[index].avServiceID, let channel = DDCChannel(registryID: id) else {
                    throw ProbeError.usage("no DDC display at index \(index)")
                }
                let written = channel.set(code, value: value)
                usleep(100_000)
                try output(["written": "\(written)", "readBack": channel.get(code).map { "\($0.current)/\($0.maximum)" } ?? "no reply"])
            case "help", "--help", "-h":
                print("""
                macpocket-probe — native MacPocket development and validation tool
                  system                       Live CPU, RAM, volumes and power snapshot
                  ddc                          External displays: DDC brightness, speaker volume and mute (read-only)
                  processes                    Live process snapshot (interval CPU)
                  diagnostic <name> [PID]      Fixed read-only diagnostic; PID/self for openFiles
                  terminate <PID> [--force]    Signal an eligible same-user process
                  windows [--all]              Switchable windows on every Space (--all adds windowless apps)
                  switcher list [--detailed]
                  switcher focus <id> | switcher focus --mru <n>
                  switcher show [1…9] | switcher hide | switcher status
                  \(String(localized: "Komutlar çalışan MacPocket'a bağlanır. Profil ve MRU sırası 1'den başlar; show paneli açar, hide seçim yapmadan kapatır. status panelin görünürlüğünü bildirir."))
                  focus <windowID|id>          Bring a window to the front (switches Space when needed)
                  thumbnail <windowID> <png>   Capture one window (Screen Recording access required)
                  startup                      launchd startup items by class (read-only)
                  maintenance [run <id>]       Maintenance tasks and support; run one ready task
                  cleanup                      Read-only cleanup scan summary per target
                  fans                         Fan RPM, range and mode (read-only)
                  fan-set <fan> <rpm>          Set one fan's speed, verified by readback (needs root)
                  fan-release                  Hand every fan back to the system (needs root)
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

    static func fanReport(_ controller: FanController) throws -> [[String: Double]] {
        try (0..<controller.fanCount).map { fan in
            let range = try controller.range(fan: fan)
            return ["fan": Double(fan), "rpm": try controller.actualRPM(fan: fan) ?? -1,
                    "minimum": range.lowerBound, "maximum": range.upperBound]
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
