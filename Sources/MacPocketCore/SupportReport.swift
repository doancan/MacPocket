import Foundation

/// A shareable Markdown snapshot of the Mac's state for asking for help. Private details are masked unless the
/// user opts out: computer name, user name in paths, IP addresses and serial numbers.
public struct SupportReport: Sendable {
    public struct Options: Equatable, Sendable {
        public var maskPrivateDetails = true
        public var includeProcesses = true
        public var includePorts = true

        public init() {}
    }

    public struct ProcessLine: Equatable, Sendable {
        public let name: String
        public let cpuPercent: Double
        public let memoryBytes: UInt64
        public init(name: String, cpuPercent: Double, memoryBytes: UInt64) {
            self.name = name; self.cpuPercent = cpuPercent; self.memoryBytes = memoryBytes
        }
    }

    public struct Input: Sendable {
        public var generatedAt: Date
        public var appVersion: String
        public var osVersion: String
        public var computerName: String
        public var userName: String
        public var snapshot: SystemSnapshot?
        public var processes: [ProcessLine]
        public var ports: [PortOwner]
        public var attention: [String]

        public init(generatedAt: Date, appVersion: String, osVersion: String, computerName: String, userName: String,
                    snapshot: SystemSnapshot?, processes: [ProcessLine], ports: [PortOwner], attention: [String]) {
            self.generatedAt = generatedAt; self.appVersion = appVersion; self.osVersion = osVersion; self.computerName = computerName
            self.userName = userName; self.snapshot = snapshot; self.processes = processes; self.ports = ports; self.attention = attention
        }
    }

    public static func markdown(_ input: Input, options: Options, bytes: (UInt64) -> String) -> String {
        var lines: [String] = []
        func section(_ title: String) { lines += ["", "## " + title, ""] }
        lines.append("# " + String(localized: "MacPocket destek raporu"))
        lines.append("")
        lines.append("- " + String(localized: "Oluşturulma: \(ISO8601DateFormatter().string(from: input.generatedAt))"))
        lines.append("- MacPocket \(input.appVersion) · \(input.osVersion)")
        lines.append("- " + String(localized: "Bilgisayar: \(options.maskPrivateDetails ? String(localized: "(gizlendi)") : input.computerName)"))

        section(String(localized: "Dikkat"))
        lines += input.attention.isEmpty ? ["- " + String(localized: "Dikkat gerektiren durum yok.")] : input.attention.map { "- " + $0 }

        if let s = input.snapshot {
            section(String(localized: "Sistem"))
            lines.append("- " + String(localized: "Model: \(s.hardwareModel) · \(s.logicalCPUCount) çekirdek · \(bytes(s.physicalMemoryBytes)) bellek"))
            lines.append("- " + String(localized: "Açık kalma süresi: \(Int(s.uptimeSeconds / 3600)) saat"))
            if let cpu = s.cpuTotalPercent { lines.append("- CPU: %\(Int(cpu.rounded()))") }
            if let load = s.loadAverages, load.count == 3 {
                lines.append("- " + String(localized: "Yük ortalaması: \(load.map { String(format: "%.2f", $0) }.joined(separator: " / "))"))
            }
            if let used = s.usedMemoryBytes {
                lines.append("- " + String(localized: "Bellek: \(bytes(used)) kullanılıyor, swap \(bytes(s.swapUsedBytes ?? 0)), baskı seviyesi \(s.memoryPressureLevel.map(String.init) ?? "?")"))
            }
            lines.append("- " + String(localized: "Isı durumu: \(MenuBarFormatter.thermalTitle(s.thermalState))"))
            if let fans = s.fans, !fans.isEmpty {
                lines.append("- " + String(localized: "Fanlar: \(fans.map { "\(Int($0.rpm)) rpm" }.joined(separator: ", "))"))
            }
            let power = s.power
            let source = switch power.source {
            case "AC Power": String(localized: "Priz")
            case "Battery Power": String(localized: "Pil")
            case "UPS Power": "UPS"
            default: String(localized: "Bilinmiyor")
            }
            lines.append("- " + String(localized: "Güç: \(source)") + (power.chargePercent.map { " · %\(Int($0))" } ?? ""))

            section(String(localized: "Depolama"))
            for volume in s.volumes {
                let name = options.maskPrivateDetails ? mask(volume.path, user: input.userName) : volume.path
                let free = volume.totalBytes > 0 ? Int(Double(volume.availableBytes) / Double(volume.totalBytes) * 100) : 0
                lines.append("- `\(name)`: " + String(localized: "\(bytes(UInt64(max(0, volume.availableBytes)))) boş / \(bytes(UInt64(max(0, volume.totalBytes)))) (%\(free))"))
            }
            if let network = s.network {
                section(String(localized: "Ağ"))
                lines.append("- " + String(localized: "Birincil arayüz: \(network.primaryInterface ?? "?")"))
                let address = network.localIPv4.map { options.maskPrivateDetails ? maskAddress($0) : $0 } ?? "?"
                lines.append("- " + String(localized: "Yerel adres: \(address)"))
            }
        }

        if options.includeProcesses, !input.processes.isEmpty {
            section(String(localized: "En çok kaynak kullanan süreçler"))
            lines.append("| " + String(localized: "Süreç") + " | CPU | " + String(localized: "Bellek") + " |")
            lines.append("|---|---:|---:|")
            for process in input.processes.prefix(10) {
                let name = options.maskPrivateDetails ? mask(process.name, user: input.userName) : process.name
                lines.append("| \(name.replacingOccurrences(of: "|", with: "\\|")) | %\(String(format: "%.1f", process.cpuPercent)) | \(bytes(process.memoryBytes)) |")
            }
        }

        if options.includePorts {
            let exposed = input.ports.filter(\.isExposed)
            section(String(localized: "Ağa açık portlar"))
            lines += exposed.isEmpty ? ["- " + String(localized: "Ağa açık dinleyici yok.")]
                : exposed.map { "- \($0.command): \($0.ports.map(String.init).joined(separator: ", "))" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Replaces the user's home folder with "~" and the user name anywhere else.
    public static func mask(_ text: String, user: String) -> String {
        guard !user.isEmpty else { return text }
        return text.replacingOccurrences(of: "/Users/\(user)", with: "~").replacingOccurrences(of: user, with: "‹user›")
    }

    /// Keeps the network part useful for diagnosis (192.168.x.x) but hides the host.
    public static func maskAddress(_ address: String) -> String {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return "‹" + String(localized: "gizlendi") + "›" }
        return "\(parts[0]).\(parts[1]).x.x"
    }
}
