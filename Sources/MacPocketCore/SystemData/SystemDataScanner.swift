import Foundation
@_exported import MacPocketShared

/// Everything the scanner needs from the outside world, so tests can use a temporary home and canned tool
/// output.
public struct SystemDataEnvironment: Sendable {
    public typealias CommandRunner = @Sendable (_ executable: String, _ arguments: [String]) async -> String?

    public var home: URL
    /// Where absolute catalog locations (`/Library/Caches`, `/opt`) are looked up. Tests and audits point it
    /// at a fixture so they can never measure or remove anything on the real system.
    public var systemRoot: URL
    public var temporaryDirectory: URL
    /// Folders searched for `docker` and `ollama`; a GUI app inherits no shell PATH.
    public var toolSearchPaths: [String]
    /// Plugged-in drives whose top-level project folders are searched, when `includeExternalProjects` is on.
    public var externalVolumes: @Sendable () -> [URL]
    public var includeExternalProjects: Bool
    /// Runs a tool and returns its standard output, or nil when it is missing, fails or times out.
    public var run: CommandRunner
    public var now: @Sendable () -> Date
    /// Display name of the installed app owning a bundle identifier, nil when no such app is installed.
    public var installedAppName: @Sendable (String) -> String?
    public var capacity: @Sendable () -> VolumeCapacity?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                systemRoot: URL = URL(fileURLWithPath: "/"),
                temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                toolSearchPaths: [String]? = nil,
                externalVolumes: @escaping @Sendable () -> [URL] = SystemDataExternalVolumes.eligibleVolumeURLs,
                includeExternalProjects: Bool = false,
                run: @escaping CommandRunner = SystemDataEnvironment.liveRunner,
                now: @escaping @Sendable () -> Date = { Date() },
                installedAppName: @escaping @Sendable (String) -> String? = { _ in nil },
                capacity: @escaping @Sendable () -> VolumeCapacity? = { try? VolumeCapacity.read() }) {
        self.home = home
        self.systemRoot = systemRoot
        self.temporaryDirectory = temporaryDirectory
        self.toolSearchPaths = toolSearchPaths ?? SystemDataCatalog.defaultToolSearchPaths(home: home)
        self.externalVolumes = externalVolumes
        self.includeExternalProjects = includeExternalProjects
        self.run = run
        self.now = now
        self.installedAppName = installedAppName
        self.capacity = capacity
    }

    public static let liveRunner: CommandRunner = { executable, arguments in
        guard FileManager.default.isExecutableFile(atPath: executable),
              let result = try? await BoundedProcess.run(executable, arguments, timeout: 25), result.status == 0 else { return nil }
        return result.output
    }
}

/// Counts the places a scan could not read, from any of the concurrent measurements.
final class ScanCompleteness: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func note(_ measurement: StorageMeasurement) { if measurement.inaccessibleCount > 0 { lock.withLock { count += measurement.inaccessibleCount } } }
    var unreadable: Int { lock.withLock { count } }
}

/// A live reading of how far the scan is, sent a few times a second.
public struct SystemDataScanProgress: Sendable, Equatable {
    public static let phaseCount = 5
    /// 1-based position of the current phase among `phaseCount`.
    public let phaseIndex: Int
    public let visitedEntries: Int
    public let measuredBytes: Int64
    public let currentName: String

    /// 0…1, by phase: a scan has no honest per-file percentage because nothing knows how many files are
    /// ahead.
    public var fraction: Double { min(1, max(0, (Double(phaseIndex) - 0.5) / Double(Self.phaseCount))) }
}

final class ScanPhaseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0
    func advance() -> Int { lock.withLock { index += 1; return index } }
    var current: Int { lock.withLock { index } }
}

public enum SystemDataScanEvent: Sendable {
    case progress(SystemDataScanProgress)
    case phase(String)
    case item(SystemDataItem)
    case finished(SystemDataReport)
}

/// Measures System Data. Fixed locations come from the catalog; simulators, snapshots, Docker, Ollama, iOS
/// backups, project build folders and unexplained large folders are discovered. A tool that is not installed
/// simply contributes nothing. Nothing is deleted here.
public actor SystemDataScanner {
    private let environment: SystemDataEnvironment
    private let maximumDuration: TimeInterval
    private var control: StorageScanControl?

    public init(environment: SystemDataEnvironment = SystemDataEnvironment(), maximumDuration: TimeInterval = 150) {
        self.environment = environment
        self.maximumDuration = maximumDuration
    }

    public func cancel() { control?.cancel() }

    /// Streams each item as soon as it is measured, then the finished report.
    public nonisolated func scan(hidden: Set<String> = []) -> AsyncStream<SystemDataScanEvent> {
        AsyncStream { continuation in
            let task = Task { [self] in
                let report = await run(hidden: hidden) { continuation.yield($0) }
                continuation.yield(.finished(report))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel(); Task { await self.cancel() } }
        }
    }

    private func run(hidden: Set<String>, emit: @Sendable @escaping (SystemDataScanEvent) -> Void) async -> SystemDataReport {
        let control = StorageScanControl(maximumDuration: maximumDuration, maximumEntries: 12_000_000)
        self.control = control
        let links = HardLinkRegistry()
        let completeness = ScanCompleteness()
        let env = environment
        let collector = Collector(hidden: hidden, emit: emit)
        let phases = ScanPhaseBox()
        func enter(_ text: String) { _ = phases.advance(); emit(.phase(text)) }
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let reading = control.snapshot
                emit(.progress(SystemDataScanProgress(phaseIndex: max(1, phases.current), visitedEntries: reading.visitedEntries,
                                                      measuredBytes: reading.measuredBytes, currentName: reading.currentName)))
            }
        }
        defer { ticker.cancel() }

        enter(String(localized: "Bilinen konumlar ölçülüyor…"))
        let probes = SystemDataCatalog.probes()
        await withTaskGroup(of: Void.self) { group in
            var iterator = probes.makeIterator()
            var running = 0
            func addNext() {
                guard let probe = iterator.next() else { return }
                running += 1
                group.addTask { await collector.add(await Self.measure(probe, env: env, control: control, links: links, completeness: completeness)) }
            }
            for _ in 0..<4 { addNext() }
            while await group.next() != nil {
                running -= 1
                if !Task.isCancelled { addNext() }
            }
        }

        enter(String(localized: "Geçici dosyalar, simülatörler ve anlık görüntüler…"))
        for item in await Self.temporaryItems(env: env, control: control, links: links, completeness: completeness) { await collector.add(item) }
        for item in await Self.snapshotItems(env: env) { await collector.add(item) }
        for item in await Self.simulatorItems(env: env, control: control, links: links) { await collector.add(item) }

        enter(String(localized: "Docker, yapay zekâ modelleri ve yedekler…"))
        for item in await Self.dockerItems(env: env) { await collector.add(item) }
        for item in await Self.ollamaItems(env: env) { await collector.add(item) }
        for item in await Self.backupItems(env: env, control: control, links: links, completeness: completeness) { await collector.add(item) }

        enter(String(localized: "Proje derleme klasörleri aranıyor…"))
        for item in await Self.projectItems(env: env, control: control, links: links, completeness: completeness) { await collector.add(item) }

        enter(String(localized: "Açıklanamayan büyük klasörler aranıyor…"))
        let covered = await collector.coveredPaths
            + SystemDataCatalog.probes().flatMap { SystemDataCatalog.resolve($0.locations, home: env.home, systemRoot: env.systemRoot) }
        for item in await Self.catchAllItems(env: env, control: control, links: links, covered: Set(covered), completeness: completeness) { await collector.add(item) }

        let items = await collector.items.sorted { $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.id < $1.id }
        let capacity = env.capacity()
        return SystemDataReport(scannedAt: env.now(), items: items, totalBytes: capacity?.totalBytes ?? 0,
                                freeBytes: capacity?.availableBytes ?? 0, purgeableBytes: capacity?.purgeableBytes ?? 0,
                                complete: !control.limitReached && !control.isCancelled, unreadablePlaces: completeness.unreadable)
    }

    /// Collects items from concurrent probes, drops hidden and duplicate ones and forwards each to the
    /// stream.
    private actor Collector {
        private let hidden: Set<String>
        private let emit: @Sendable (SystemDataScanEvent) -> Void
        private(set) var items: [SystemDataItem] = []
        private var ids = Set<String>()
        init(hidden: Set<String>, emit: @escaping @Sendable (SystemDataScanEvent) -> Void) { self.hidden = hidden; self.emit = emit }
        var coveredPaths: [String] { items.flatMap(\.paths) }
        func add(_ item: SystemDataItem?) {
            guard let item, !hidden.contains(item.id), ids.insert(item.id).inserted else { return }
            items.append(item)
            emit(.item(item))
        }
    }

    // MARK: Fixed locations

    static func measure(_ probe: SystemDataProbe, env: SystemDataEnvironment, control: StorageScanControl, links: HardLinkRegistry,
                        completeness: ScanCompleteness) async -> SystemDataItem? {
        let paths = SystemDataCatalog.resolve(probe.locations, home: env.home, systemRoot: env.systemRoot)
        guard !paths.isEmpty else { return nil }
        control.setCurrent(probe.title)
        let measured = await StorageWork.run(control) { paths.map { DirectorySizer.measure($0, control: control, links: links) } }
        var total = StorageMeasurement()
        for measurement in measured { total.add(measurement); completeness.note(measurement) }
        guard total.allocatedBytes > 0 else { return nil }
        return SystemDataItem(id: probe.id, group: probe.group, title: probe.title, detail: probe.detail, safety: probe.safety,
                              regeneration: probe.regeneration, paths: paths, sizeBytes: total.allocatedBytes,
                              lastActivity: total.newestModification > 0 ? Date(timeIntervalSince1970: Double(total.newestModification)) : nil,
                              action: probe.action, warning: probe.warning, busyBundleIDs: probe.busyBundleIDs)
    }

    // MARK: Temporary files

    static let temporaryAgeDays = 3

    static func temporaryItems(env: SystemDataEnvironment, control: StorageScanControl, links: HardLinkRegistry,
                               completeness: ScanCompleteness) async -> [SystemDataItem] {
        guard let path = existingCanonicalPath(env.temporaryDirectory) else { return [] }
        let cutoff = env.now().addingTimeInterval(-Double(temporaryAgeDays) * 86_400)
        let measurement = await StorageWork.run(control) { measureChildren(of: path, olderThan: cutoff, control: control, links: links) }
        completeness.note(measurement)
        guard measurement.allocatedBytes > 0 else { return [] }
        return [SystemDataItem(id: "temp.user", group: .temporary, title: String(localized: "Geçici dosyalar"),
                               detail: String(localized: "Kullanıcı geçici klasöründe \(Self.temporaryAgeDays) günden uzun süredir dokunulmamış dosyalar."),
                               safety: .safe, regeneration: .rebuildsLocally, paths: [path], sizeBytes: measurement.allocatedBytes,
                               lastActivity: measurement.newestModification > 0 ? Date(timeIntervalSince1970: Double(measurement.newestModification)) : nil,
                               action: .removeContentsOlderThan(days: Self.temporaryAgeDays))]
    }

    /// Sum of direct children whose newest change is older than `cutoff`.
    static func measureChildren(of path: String, olderThan cutoff: Date, control: StorageScanControl, links: HardLinkRegistry) -> StorageMeasurement {
        var total = StorageMeasurement()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return total }
        for name in names {
            let child = path + "/" + name
            var info = stat()
            guard lstat(child, &info) == 0 else { continue }
            let measurement = (info.st_mode & S_IFMT) == S_IFDIR ? DirectorySizer.measure(child, control: control, links: links) : {
                var single = StorageMeasurement()
                single.allocatedBytes = max(0, Int64(info.st_blocks) * 512)
                single.logicalBytes = max(0, info.st_size)
                single.newestModification = Int64(info.st_mtimespec.tv_sec)
                return single
            }()
            let newest = max(measurement.newestModification, Int64(info.st_mtimespec.tv_sec))
            if Double(newest) < cutoff.timeIntervalSince1970 { total.add(measurement) }
        }
        return total
    }

    // MARK: Time Machine snapshots

    static func snapshotItems(env: SystemDataEnvironment) async -> [SystemDataItem] {
        guard let output = await env.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }
        return SystemDataParsers.localSnapshotDates(output).map { stamp in
            SystemDataItem(id: "snapshot.\(stamp)", group: .snapshots,
                           title: SystemDataParsers.snapshotDate(stamp).map { String(localized: "Anlık görüntü: \($0.formatted(date: .abbreviated, time: .shortened))") }
                               ?? String(localized: "Yerel anlık görüntü"),
                           detail: String(localized: "APFS’in Time Machine için tuttuğu yerel anlık görüntü. macOS boyutunu bildirmez; silince tuttuğu alan boşalır."),
                           safety: .review, regeneration: .doesNotReturn, paths: [], sizeBytes: 0,
                           lastActivity: SystemDataParsers.snapshotDate(stamp),
                           action: .run(SystemDataCommand("/usr/bin/tmutil", ["deletelocalsnapshots", stamp], administratorFallback: true)),
                           sizeKnown: false)
        }
    }

    // MARK: Simulators

    static func simulatorItems(env: SystemDataEnvironment, control: StorageScanControl, links: HardLinkRegistry) async -> [SystemDataItem] {
        var items: [SystemDataItem] = []
        let runtimeJSON = await env.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        let deviceJSON = await env.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        let devices = deviceJSON.map { SystemDataParsers.simulatorDevices(Data($0.utf8)) } ?? []
        let runtimes = runtimeJSON.map { SystemDataParsers.simulatorRuntimes(Data($0.utf8)) } ?? []

        for runtime in runtimes where runtime.deletable && runtime.sizeBytes > 0 {
            let users = devices.filter { $0.runtimeIdentifier == runtime.runtimeIdentifier }
            let inUse = users.contains(where: \.isBooted)
            let lastUsed = users.compactMap(\.lastBooted).max()
            let name = [runtime.platform.replacingOccurrences(of: "simulator", with: "").capitalized, runtime.version]
                .filter { !$0.isEmpty }.joined(separator: " ")
            items.append(SystemDataItem(
                id: "simulator.runtime.\(runtime.identifier)", group: .simulators,
                title: String(localized: "Simülatör çalışma zamanı: \(name)"),
                detail: users.isEmpty
                    ? String(localized: "Bu sürüme bağlı simülatör aygıtı yok; Xcode güncellemeleri bunları geride bırakır.")
                    : String(localized: "Bu sürümde \(users.count) simülatör aygıtı var; kaldırırsan aygıtlar da kullanılamaz olur."),
                safety: .review, regeneration: .downloadsAgain, paths: [], sizeBytes: runtime.sizeBytes, lastActivity: lastUsed,
                action: .run(SystemDataCommand("/usr/bin/xcrun", ["simctl", "runtime", "delete", runtime.identifier])),
                warning: inUse ? String(localized: "Bu sürümde açık bir simülatör var.") : nil))
        }

        let unavailable = devices.filter { !$0.isAvailable }
        if !unavailable.isEmpty {
            let size = unavailable.reduce(Int64(0)) { $0 + $1.dataPathSize }
            if size > 0 {
                items.append(SystemDataItem(
                    id: "simulator.unavailable", group: .simulators, title: String(localized: "Kullanılamayan simülatör aygıtları"),
                    detail: String(localized: "Çalışma zamanı kaldırılmış \(unavailable.count) aygıt; hiçbir zaman açılamazlar."),
                    safety: .safe, regeneration: .notNeededAgain, paths: [], sizeBytes: size,
                    action: .run(SystemDataCommand("/usr/bin/xcrun", ["simctl", "delete", "unavailable"]))))
            }
        }

        let available = devices.filter(\.isAvailable)
        let deviceBytes = available.reduce(Int64(0)) { $0 + $1.dataPathSize }
        if deviceBytes > 0 {
            items.append(SystemDataItem(
                id: "simulator.devices", group: .simulators, title: String(localized: "Simülatör aygıt verileri"),
                detail: String(localized: "\(available.count) aygıtın uygulamaları, verileri ve fotoğrafları. Sıfırlamak aygıtı fabrika durumuna getirir."),
                safety: .review, regeneration: .doesNotReturn, paths: [], sizeBytes: deviceBytes,
                lastActivity: available.compactMap(\.lastBooted).max(),
                action: .run(SystemDataCommand("/usr/bin/xcrun", ["simctl", "erase", "all"])),
                warning: available.contains(where: \.isBooted) ? String(localized: "Açık bir simülatör var; önce kapat.") : nil))
        }
        return items
    }

    // MARK: Docker

    static func dockerItems(env: SystemDataEnvironment) async -> [SystemDataItem] {
        guard let docker = SystemDataCatalog.executable(named: "docker", in: env.toolSearchPaths),
              let output = await env.run(docker, ["system", "df", "--format", "{{json .}}"]) else { return [] }
        return SystemDataParsers.dockerUsage(output).compactMap { usage in
            guard usage.reclaimableBytes > 0 else { return nil }
            switch usage.kind {
            case .buildCache:
                return SystemDataItem(id: "docker.buildCache", group: .docker, title: String(localized: "Docker derleme önbelleği"),
                                      detail: String(localized: "BuildKit’in önbelleği; sonraki derlemeler yavaşlar."),
                                      safety: .safe, regeneration: .rebuildsLocally, paths: [], sizeBytes: usage.reclaimableBytes,
                                      action: .run(SystemDataCommand(docker, ["builder", "prune", "--all", "--force"])))
            case .images:
                return SystemDataItem(id: "docker.images", group: .docker, title: String(localized: "Kullanılmayan Docker imajları"),
                                      detail: String(localized: "Hiçbir konteynerin kullanmadığı imajlar; gerekince yeniden çekilir."),
                                      safety: .review, regeneration: .downloadsAgain, paths: [], sizeBytes: usage.reclaimableBytes,
                                      action: .run(SystemDataCommand(docker, ["image", "prune", "--all", "--force"])))
            case .containers:
                return SystemDataItem(id: "docker.containers", group: .docker, title: String(localized: "Durmuş Docker konteynerleri"),
                                      detail: String(localized: "Çalışmayan konteynerlerin yazılabilir katmanları."),
                                      safety: .review, regeneration: .doesNotReturn, paths: [], sizeBytes: usage.reclaimableBytes,
                                      action: .run(SystemDataCommand(docker, ["container", "prune", "--force"])))
            case .volumes:
                return SystemDataItem(id: "docker.volumes", group: .docker, title: String(localized: "Kullanılmayan Docker birimleri"),
                                      detail: String(localized: "Hiçbir konteynere bağlı olmayan birimler."),
                                      safety: .review, regeneration: .doesNotReturn, paths: [], sizeBytes: usage.reclaimableBytes,
                                      action: .run(SystemDataCommand(docker, ["volume", "prune", "--force"])),
                                      warning: String(localized: "Veritabanları verilerini birimlerde tutar; silinen veri geri gelmez."))
            }
        }
    }

    // MARK: Ollama

    static func ollamaItems(env: SystemDataEnvironment) async -> [SystemDataItem] {
        guard let ollama = SystemDataCatalog.executable(named: "ollama", in: env.toolSearchPaths),
              let output = await env.run(ollama, ["list"]) else { return [] }
        let models = SystemDataParsers.ollamaModels(output)
        // `ollama list` rounds (and truncates to whole units from 10 up); the manifests hold the exact byte
        // counts.
        let exact = SystemDataParsers.ollamaExclusiveBytes(models: models.map(\.name),
                                                           modelsDirectory: env.home.appending(path: ".ollama/models", directoryHint: .isDirectory))
        return models.map { model in
            let sizes = exact[model.name]
            let sharing = (sizes?.shared ?? 0) > 0
            return SystemDataItem(id: "ollama.\(model.name)", group: .aiModels, title: String(localized: "Ollama modeli: \(model.name)"),
                                  detail: sharing
                                      ? String(localized: "Yerel dil modeli; “ollama rm” ile kaldırılır. Başka modellerle paylaştığı katmanlar boyuta dahil değil, çünkü onlar kalır.")
                                      : String(localized: "Yerel dil modeli; “ollama rm” ile kaldırılır, blob dosyaları elle silinmez."),
                                  safety: .review, regeneration: .downloadsAgain, paths: [],
                                  sizeBytes: sizes?.exclusive ?? model.sizeBytes,
                                  action: .run(SystemDataCommand(ollama, ["rm", model.name])))
        }
    }

    // MARK: iOS backups

    static func backupItems(env: SystemDataEnvironment, control: StorageScanControl, links: HardLinkRegistry,
                            completeness: ScanCompleteness) async -> [SystemDataItem] {
        let root = env.home.appending(path: "Library/Application Support/MobileSync/Backup", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        var items: [SystemDataItem] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let url = root.appending(path: name, directoryHint: .isDirectory)
            guard let path = existingCanonicalPath(url) else { continue }
            let info = NSDictionary(contentsOf: url.appending(path: "Info.plist")) as? [String: Any]
            let device = info?["Device Name"] as? String ?? String(localized: "Bilinmeyen aygıt")
            let date = info?["Last Backup Date"] as? Date
            let measurement = await StorageWork.run(control) { DirectorySizer.measure(path, control: control, links: links) }
            completeness.note(measurement)
            guard measurement.allocatedBytes > 0 else { continue }
            items.append(SystemDataItem(id: "backup.\(name)", group: .backups, title: String(localized: "iOS yedeği: \(device)"),
                                        detail: date.map { String(localized: "Son yedekleme: \($0.formatted(date: .abbreviated, time: .omitted)). Aygıt başka yerde yedeklenmediyse geri gelmez.") }
                                            ?? String(localized: "Aygıt başka yerde yedeklenmediyse geri gelmez."),
                                        safety: .review, regeneration: .doesNotReturn, paths: [path], sizeBytes: measurement.allocatedBytes,
                                        lastActivity: date ?? Date(timeIntervalSince1970: Double(measurement.newestModification)),
                                        action: .removeFolder))
        }
        return items
    }
}
