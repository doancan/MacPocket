import Foundation

public enum MaintenanceTaskID: String, CaseIterable, Sendable, Identifiable {
    case quickLook, launchServices, userFontCache, flushDNS, verifyDisk, purgeMemory, restartInterface, spotlight
    public var id: String { rawValue }
}

public enum MaintenanceGroup: String, CaseIterable, Sendable, Identifiable {
    case caches, system, interface
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .caches: String(localized: "Önbellekler")
        case .system: String(localized: "Disk ve sistem")
        case .interface: String(localized: "Arayüz")
        }
    }

    public var symbol: String {
        switch self {
        case .caches: "archivebox"
        case .system: "internaldrive"
        case .interface: "macwindow"
        }
    }
}

public enum MaintenanceSupport: Equatable, Sendable {
    case ready
    case unavailable(String)
}

/// One command of a task. Commands are fixed in the catalog; nothing user-supplied reaches a shell.
public struct MaintenanceStep: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(_ executable: String, _ arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var commandLine: String { ([executable] + arguments).joined(separator: " ") }
}

public struct MaintenanceTask: Identifiable, Sendable {
    public let id: MaintenanceTaskID
    public let group: MaintenanceGroup
    public let title: String
    public let detail: String
    public let symbol: String
    public let steps: [MaintenanceStep]
    /// Runs through one administrator prompt shared by every such task in the run.
    public let requiresAdministrator: Bool
    /// Selected by default: safe, quick and useful. The rest interrupt something or take a while.
    public let recommended: Bool
    /// Side effect worth reading before running.
    public let caution: String?
    public let timeout: TimeInterval
    public let support: MaintenanceSupport
}

public enum MaintenanceOutcome: Equatable, Sendable {
    case ran(seconds: Double, note: String?)
    case skipped(String)
    case failed(String)
}

public enum MaintenanceProgress: Equatable, Sendable {
    case waiting, running
    case finished(MaintenanceOutcome)
}

public struct MaintenanceResult: Identifiable, Sendable {
    public var id: MaintenanceTaskID { task.id }
    public let task: MaintenanceTask
    public let outcome: MaintenanceOutcome
}

public enum MaintenanceCatalog {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// `isExecutable` is injectable so a missing tool can be tested.
    public static func tasks(isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> [MaintenanceTask] {
        func make(_ id: MaintenanceTaskID, _ group: MaintenanceGroup, _ title: String, _ detail: String, _ symbol: String,
                  _ steps: [MaintenanceStep], administrator: Bool = false, recommended: Bool, caution: String? = nil,
                  timeout: TimeInterval = 60) -> MaintenanceTask {
            let support: MaintenanceSupport = steps.allSatisfy { isExecutable($0.executable) }
                ? .ready : .unavailable(String(localized: "Bu macOS sürümünde bu araç yok."))
            return MaintenanceTask(id: id, group: group, title: title, detail: detail, symbol: symbol, steps: steps,
                                   requiresAdministrator: administrator, recommended: recommended, caution: caution,
                                   timeout: timeout, support: support)
        }
        return [
            make(.quickLook, .caches, String(localized: "Quick Look Önbelleği"),
                 String(localized: "Önizleme önbelleğini sıfırlar; bozuk ya da eski önizlemeleri düzeltir."),
                 "eye", [.init("/usr/bin/qlmanage", ["-r", "cache"])], recommended: true),
            make(.launchServices, .caches, String(localized: "Launch Services Veritabanı"),
                 String(localized: "Silinmiş uygulamaların kayıtlarını temizler; “Birlikte Aç” menüsündeki kopyaları ve yanlış simgeleri düzeltir."),
                 "square.stack.3d.up", [.init(lsregister, ["-gc"])], recommended: true),
            make(.userFontCache, .caches, String(localized: "Yazı Tipi Önbelleği"),
                 String(localized: "Kullanıcı yazı tipi veritabanını sıfırlar; bozuk görünen yazıları düzeltir."),
                 "textformat", [.init("/usr/bin/atsutil", ["databases", "-removeUser"])], recommended: false,
                 caution: String(localized: "Açık uygulamaları yeniden başlatman gerekebilir.")),
            make(.flushDNS, .caches, String(localized: "DNS Önbelleği"),
                 String(localized: "Adres çözümleme önbelleğini boşaltır; bir site açılmıyor ya da eski adrese gidiyorsa işe yarar."),
                 "network", [.init("/usr/bin/dscacheutil", ["-flushcache"]), .init("/usr/bin/killall", ["-HUP", "mDNSResponder"])],
                 administrator: true, recommended: true),
            make(.verifyDisk, .system, String(localized: "Başlangıç Diskini Doğrula"),
                 String(localized: "Disk İzlencesi’nin İlk Yardım denetimini salt okunur yapar; dosya sisteminde hata olup olmadığını söyler."),
                 "checkmark.shield", [.init("/usr/sbin/diskutil", ["verifyVolume", "/"])], recommended: true, timeout: 600),
            make(.purgeMemory, .system, String(localized: "Belleği Boşalt"),
                 String(localized: "Disk önbelleği için tutulan belleği serbest bırakır."),
                 "memorychip", [.init("/usr/sbin/purge", [])], administrator: true, recommended: false,
                 caution: String(localized: "macOS belleği zaten kendisi yönetir; etkisi geçicidir ve uygulamalar bir süre yavaş açılabilir.")),
            make(.restartInterface, .interface, String(localized: "Dock, Finder ve Menü Çubuğu"),
                 String(localized: "Takılan ya da yanlış çizilen Dock, Finder pencereleri ve menü çubuğu simgelerini yeniden başlatır."),
                 "arrow.triangle.2.circlepath",
                 [.init("/usr/bin/killall", ["Dock"]), .init("/usr/bin/killall", ["Finder"]), .init("/usr/bin/killall", ["SystemUIServer"])],
                 recommended: false, caution: String(localized: "Finder pencereleri bir an kapanıp yeniden açılır.")),
            make(.spotlight, .system, String(localized: "Spotlight Dizinini Yeniden Oluştur"),
                 String(localized: "Arama sonuçları eksik ya da yanlışsa başlangıç diskinin arama dizinini sıfırdan oluşturur."),
                 "magnifyingglass", [.init("/usr/bin/mdutil", ["-E", "/"])], administrator: true, recommended: false,
                 caution: String(localized: "Yeniden dizinleme arka planda saatler sürebilir; bu sürede arama eksik sonuç verir.")),
        ]
    }
}

public enum MaintenanceAdministratorError: Error, Equatable, Sendable {
    case cancelled
    case failed(String)
}

public enum MaintenanceRunner {
    public typealias Execute = @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) async throws -> BoundedProcess.Result
    /// Runs a shell command line as root and returns its standard output.
    public typealias AdministratorExecute = @Sendable (_ commandLine: String) async throws -> String
    public typealias Progress = @Sendable (MaintenanceTaskID, MaintenanceProgress) async -> Void

    public static let systemExecute: Execute = { path, arguments, timeout in
        try await BoundedProcess.run(path, arguments, timeout: timeout)
    }

    public static let systemAdministrator: AdministratorExecute = { command in
        do {
            return try await AdministratorShell.run(command)
        } catch AdministratorShell.Failure.cancelled {
            throw MaintenanceAdministratorError.cancelled
        } catch {
            throw MaintenanceAdministratorError.failed(error.localizedDescription)
        }
    }

    /// User-level tasks run one by one first; administrator tasks then run together after a single prompt.
    /// Every requested task gets a result. A failure never stops the run; cancelling does, before the next
    /// task.
    public static func run(_ tasks: [MaintenanceTask], execute: Execute = systemExecute,
                           administrator: AdministratorExecute = systemAdministrator,
                           progress: Progress = { _, _ in }) async -> [MaintenanceResult] {
        var outcomes: [MaintenanceTaskID: MaintenanceOutcome] = [:]
        func finish(_ task: MaintenanceTask, _ outcome: MaintenanceOutcome) async {
            outcomes[task.id] = outcome
            await progress(task.id, .finished(outcome))
        }
        for task in tasks { await progress(task.id, .waiting) }

        let cancelledReason = String(localized: "Durduruldu.")
        var privileged: [MaintenanceTask] = []
        for task in tasks {
            if case .unavailable(let reason) = task.support { await finish(task, .skipped(reason)); continue }
            if task.requiresAdministrator { privileged.append(task); continue }
            if Task.isCancelled { await finish(task, .skipped(cancelledReason)); continue }
            await progress(task.id, .running)
            await finish(task, await runSteps(task, execute: execute))
        }

        if !privileged.isEmpty {
            if Task.isCancelled {
                for task in privileged { await finish(task, .skipped(cancelledReason)) }
            } else {
                for task in privileged { await progress(task.id, .running) }
                let started = Date()
                do {
                    let output = try await administrator(try administratorCommand(for: privileged))
                    let statuses = parseAdministratorStatuses(output)
                    let seconds = Date().timeIntervalSince(started)
                    for task in privileged {
                        switch statuses[task.id] {
                        case 0?: await finish(task, .ran(seconds: seconds, note: nil))
                        case let status?: await finish(task, .failed(String(localized: "Çıkış kodu \(status).")))
                        case nil: await finish(task, .failed(String(localized: "Sonuç alınamadı.")))
                        }
                    }
                } catch MaintenanceAdministratorError.cancelled {
                    for task in privileged { await finish(task, .skipped(String(localized: "Yönetici onayı verilmedi."))) }
                } catch {
                    let message = (error as? MaintenanceAdministratorError).flatMap {
                        if case .failed(let text) = $0 { text } else { nil }
                    } ?? error.localizedDescription
                    for task in privileged { await finish(task, .failed(message)) }
                }
            }
        }
        return tasks.compactMap { task in outcomes[task.id].map { MaintenanceResult(task: task, outcome: $0) } }
    }

    private static func runSteps(_ task: MaintenanceTask, execute: Execute) async -> MaintenanceOutcome {
        let started = Date()
        var lastOutput = ""
        for step in task.steps {
            do {
                let result = try await execute(step.executable, step.arguments, task.timeout)
                lastOutput = result.output
                guard result.status == 0 else {
                    let lines = { (text: String) in
                        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
                    let message = lines(result.errorOutput).first ?? lines(result.output).last
                    return .failed(message ?? String(localized: "Çıkış kodu \(result.status)."))
                }
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        return .ran(seconds: Date().timeIntervalSince(started), note: note(for: task.id, output: lastOutput))
    }

    static func note(for id: MaintenanceTaskID, output: String) -> String? {
        switch id {
        case .verifyDisk: String(localized: "Dosya sisteminde hata bulunmadı.")
        default: nil
        }
    }

    static let statusMarker = "MACPOCKET-STATUS"

    /// `( a && b ) >/dev/null 2>&1; echo MARKER:id:$?` per task, so one prompt reports each task separately.
    /// Every word is checked against a strict character set before it reaches the shell.
    public static func administratorCommand(for tasks: [MaintenanceTask]) throws -> String {
        let safe = #"^[A-Za-z0-9/._-]+$"#
        return try tasks.map { task in
            let steps = try task.steps.map { step -> String in
                for word in [step.executable] + step.arguments where word.range(of: safe, options: .regularExpression) == nil {
                    throw MaintenanceAdministratorError.failed(word)
                }
                return step.commandLine
            }
            return "( \(steps.joined(separator: " && ")) ) >/dev/null 2>&1; echo \(statusMarker):\(task.id.rawValue):$?"
        }.joined(separator: "; ")
    }

    public static func parseAdministratorStatuses(_ output: String) -> [MaintenanceTaskID: Int32] {
        var statuses: [MaintenanceTaskID: Int32] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":")
            guard parts.count == 3, parts[0] == statusMarker, let id = MaintenanceTaskID(rawValue: String(parts[1])),
                  let status = Int32(parts[2].trimmingCharacters(in: .whitespaces)) else { continue }
            statuses[id] = status
        }
        return statuses
    }
}

/// `do shell script … with administrator privileges`: the standard macOS password prompt, run off the main
/// thread.
public enum AdministratorShell {
    public enum Failure: Error, LocalizedError, Equatable {
        case cancelled
        case failed(code: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .cancelled: String(localized: "Yönetici onayı iptal edildi.")
            case let .failed(code, message): String(localized: "Komut başarısız oldu (\(code)): \(message)")
            }
        }
    }

    private static let queue = DispatchQueue(label: "MacPocket.administrator", qos: .userInitiated)

    /// Some callers (notably network probes) need the system scripting process to present authorization
    /// reliably.
    public static func runInSeparateProcess(_ command: String) async throws -> String {
        guard !command.contains("\""), !command.contains("\\") else { throw Failure.failed(code: -1, message: command) }
        let source = "do shell script \"\(command)\" with administrator privileges"
        let result = try await BoundedProcess.run("/usr/bin/osascript", ["-e", source], timeout: 300)
        if let failure = processFailure(result) { throw failure }
        return result.output.hasSuffix("\n") ? String(result.output.dropLast()) : result.output
    }

    static func processFailure(_ result: BoundedProcess.Result) -> Failure? {
        guard result.status != 0 else { return nil }
        let message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = message.range(of: #"\(-?\d+\)$"#, options: .regularExpression)
            .flatMap { Int(message[$0].dropFirst().dropLast()) } ?? Int(result.status)
        return code == -128 ? .cancelled : .failed(code: code, message: message)
    }

    /// `command` must not contain double quotes or backslashes; callers build it from validated fixed words.
    public static func run(_ command: String) async throws -> String {
        guard !command.contains("\""), !command.contains("\\") else { throw Failure.failed(code: -1, message: command) }
        let source = "do shell script \"\(command)\" with administrator privileges"
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                var errorInfo: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? String(localized: "Bilinmeyen hata")
                    continuation.resume(throwing: code == -128 ? Failure.cancelled : Failure.failed(code: code, message: message))
                } else {
                    continuation.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }
}
