import AppKit
import MacPocketCore
import Sparkle

struct ApplicationUpdateFinding: Identifiable, Sendable {
    var id: String { source.rawValue + ":" + app.id }
    let app: InstalledApplication
    let source: ApplicationUpdateSource
    let release: ApplicationUpdateRelease
    var installedVersion: String { source == .sparkle && app.build != app.version ? "\(app.version) (\(app.build))" : app.version }
    var availableVersion: String { source == .sparkle && release.version != release.displayVersion ? "\(release.displayVersion) (\(release.version))" : release.displayVersion }
}

struct ApplicationUpdateSourceResult: Sendable {
    var findings: [ApplicationUpdateFinding] = []
    var checked = 0
    var unmatched = 0
    var skipped = 0
    var failures: [String] = []
}

/// Reads published metadata. App Store and each application's updater retain installation ownership.
actor ApplicationUpdateScanner {
    typealias Fetch = @Sendable (URL) async throws -> Data
    typealias Progress = @Sendable (Int, Int) async -> Void
    private let fetch: Fetch
    private let requestPause: Duration
    private let comparator = SUStandardVersionComparator()
    private var nextStoreRequest: ContinuousClock.Instant?
    init(fetch: @escaping Fetch = ApplicationUpdateHTTP.fetch, requestPause: Duration = .milliseconds(3200)) {
        self.fetch = fetch
        self.requestPause = requestPause
    }
    private var systemVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    private var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
    private func compare(_ a: String, _ b: String) -> ComparisonResult { comparator.compareVersion(a, toVersion: b) }
    private func newer(_ release: ApplicationUpdateRelease, than app: InstalledApplication, source: ApplicationUpdateSource, settings: ApplicationUpdateSettings) -> Bool {
        let installed = source == .sparkle ? app.build : app.version
        guard !installed.isEmpty, installed != "—", settings.includePrereleases || !release.prerelease,
              release.supports(os: systemVersion, architecture: architecture, compare: compare) else { return false }
        return compare(release.version, installed) == .orderedDescending
    }

    func check(_ source: ApplicationUpdateSource, applications: [InstalledApplication], settings: ApplicationUpdateSettings, progress: @escaping Progress) async throws -> ApplicationUpdateSourceResult {
        var result = ApplicationUpdateSourceResult()
        switch source {
        case .homebrew: return result
        case .appStore:
            let apps = applications.filter { $0.channel == .appStore && ApplicationUpdateURL.validBundleID($0.bundleID) }
            let ids = Array(Set(apps.map(\.bundleID))).sorted()
            for start in stride(from: 0, to: ids.count, by: 20) {
                try Task.checkCancellation()
                if let nextStoreRequest { try await ContinuousClock().sleep(until: nextStoreRequest) }
                let batch = Array(ids[start..<min(start + 20, ids.count)])
                let url = try ApplicationUpdateURL.lookup(bundleIDs: batch, country: settings.country)
                do {
                    nextStoreRequest = ContinuousClock.now.advanced(by: requestPause)
                    let data = try await fetch(url)
                    try Task.checkCancellation()
                    let catalog = try AppStoreUpdateCatalog.decode(data, requested: Set(batch))
                    for app in apps where batch.contains(app.bundleID) {
                        guard let release = catalog[app.bundleID.lowercased()] else { result.unmatched += 1; continue }
                        result.checked += 1
                        if newer(release, than: app, source: source, settings: settings) { result.findings.append(.init(app: app, source: source, release: release)) }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    result.failures.append(error.localizedDescription)
                    // Stop on transport/rate errors; do not hammer Apple's catalog or label unchecked apps
                    // current.
                    break
                }
                await progress(min(start + 20, ids.count), ids.count)
            }
        case .sparkle:
            let apps = applications.filter { $0.channel == .sparkle && $0.bundleID != "com.doancan.MacPocket" }
            var cache: [URL: Result<[ApplicationUpdateRelease], Error>] = [:]
            for (index, app) in apps.enumerated() {
                try Task.checkCancellation()
                do {
                    guard let url = try Self.feedURL(app) else { result.skipped += 1; await progress(index + 1, apps.count); continue }
                    let releases: [ApplicationUpdateRelease]
                    if let cached = cache[url] { releases = try cached.get() }
                    else {
                        do {
                            let data = try await fetch(url)
                            try Task.checkCancellation()
                            releases = try SparkleUpdateCatalog.decode(data)
                            cache[url] = .success(releases)
                        } catch { cache[url] = .failure(error)
                        throw error }
                    }
                    result.checked += 1
                    let candidates = releases.filter { newer($0, than: app, source: source, settings: settings) }
                    if let release = candidates.max(by: { compare($0.version, $1.version) == .orderedAscending }) {
                        result.findings.append(.init(app: app, source: source, release: release))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { try Task.checkCancellation(); result.failures.append(app.name + ": " + error.localizedDescription) }
                await progress(index + 1, apps.count)
            }
        }
        return result
    }

    private static func feedURL(_ app: InstalledApplication) throws -> URL? {
        guard try FileIdentity.read(app.url) == app.identity else { throw FileServiceError.changed }
        let handle = try FileHandle(forReadingFrom: app.url.appendingPathComponent("Contents/Info.plist"))
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 1_048_577), data.count <= 1_048_576,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw ApplicationUpdateError.malformed }
        guard let raw = plist["SUFeedURL"] as? String else { return nil }
        guard let url = URL(string: raw), ApplicationUpdateURL.valid(url) else { throw ApplicationUpdateError.invalidURL }
        return url
    }
}
