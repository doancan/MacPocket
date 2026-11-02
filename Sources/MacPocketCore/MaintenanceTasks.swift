import Foundation

public enum MaintenanceTaskID: String, CaseIterable, Sendable, Identifiable {
    case quickLook, userFontCache, flushDNS, periodicScripts
    public var id: String { rawValue }
}

public enum MaintenanceSupport: Equatable, Sendable {
    case ready
    /// Runs only with administrator rights, which this version does not request yet.
    case needsAdministrator
    case unavailable(String)
}

public struct MaintenanceTask: Identifiable, Sendable {
    public let id: MaintenanceTaskID
    public let title: String
    public let detail: String
    public let symbol: String
    public let executable: String
    public let arguments: [String]
    public let support: MaintenanceSupport
}

public enum MaintenanceOutcome: Equatable, Sendable {
    case ran(seconds: Double)
    case skipped(String)
    case failed(String)
}

public struct MaintenanceResult: Identifiable, Sendable {
    public var id: MaintenanceTaskID { task.id }
    public let task: MaintenanceTask
    public let outcome: MaintenanceOutcome
}

public enum MaintenanceCatalog {
    /// `isExecutable` is injectable so a missing tool (periodic was removed from recent macOS) can be tested.
    public static func tasks(isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> [MaintenanceTask] {
        func make(_ id: MaintenanceTaskID, _ title: String, _ detail: String, _ symbol: String, _ path: String, _ arguments: [String],
                  administrator: Bool) -> MaintenanceTask {
            let support: MaintenanceSupport = !isExecutable(path)
                ? .unavailable(String(localized: "Bu macOS sürümünde bu araç yok."))
                : (administrator ? .needsAdministrator : .ready)
            return MaintenanceTask(id: id, title: title, detail: detail, symbol: symbol, executable: path, arguments: arguments, support: support)
        }
        return [
            make(.quickLook, String(localized: "Quick Look Önbelleği"),
                 String(localized: "Önizleme önbelleğini sıfırlar; bozuk ya da eski önizlemeleri düzeltir."),
                 "eye", "/usr/bin/qlmanage", ["-r", "cache"], administrator: false),
            make(.userFontCache, String(localized: "Yazı Tipi Önbelleği"),
                 String(localized: "Kullanıcı yazı tipi veritabanını sıfırlar. Uygulamaları yeniden açman gerekebilir."),
                 "textformat", "/usr/bin/atsutil", ["databases", "-removeUser"], administrator: false),
            make(.flushDNS, String(localized: "DNS Önbelleği"),
                 String(localized: "Adres çözümleme önbelleğini boşaltır; ağ adresi sorunlarında işe yarar."),
                 "network", "/usr/bin/dscacheutil", ["-flushcache"], administrator: true),
            make(.periodicScripts, String(localized: "Periyodik Bakım"),
                 String(localized: "macOS’un günlük, haftalık ve aylık bakım betiklerini çalıştırır."),
                 "calendar.badge.clock", "/usr/sbin/periodic", ["daily", "weekly", "monthly"], administrator: true),
        ]
    }
}

public enum MaintenanceRunner {
    public typealias Execute = @Sendable (_ executable: String, _ arguments: [String]) async throws -> BoundedProcess.Result

    public static let timeout: TimeInterval = 60

    public static let systemExecute: Execute = { path, arguments in
        try await BoundedProcess.run(path, arguments, timeout: timeout)
    }

    /// Runs the ready tasks one by one and reports every task: what ran, what was skipped and why, what failed.
    /// A failure never stops the run; cancelling does, before the next task starts.
    public static func run(_ tasks: [MaintenanceTask], execute: Execute = systemExecute) async -> [MaintenanceResult] {
        var results: [MaintenanceResult] = []
        for task in tasks {
            if Task.isCancelled { break }
            switch task.support {
            case .needsAdministrator:
                results.append(.init(task: task, outcome: .skipped(String(localized: "Yönetici onayı gerektirir; bu sürüm yönetici gerektiren görevleri çalıştırmaz."))))
            case .unavailable(let reason):
                results.append(.init(task: task, outcome: .skipped(reason)))
            case .ready:
                let started = Date()
                do {
                    let result = try await execute(task.executable, task.arguments)
                    if result.status == 0 {
                        results.append(.init(task: task, outcome: .ran(seconds: Date().timeIntervalSince(started))))
                    } else {
                        let firstLine = result.errorOutput.split(whereSeparator: \.isNewline)
                            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
                        results.append(.init(task: task, outcome: .failed(firstLine ?? String(localized: "Çıkış kodu \(result.status)."))))
                    }
                } catch {
                    results.append(.init(task: task, outcome: .failed(error.localizedDescription)))
                }
            }
        }
        return results
    }
}
