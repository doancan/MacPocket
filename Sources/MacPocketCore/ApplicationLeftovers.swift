import Foundation

public struct ApplicationLeftover: Identifiable, Sendable {
    public var id: String { request.url.path }
    public let bundleID: String
    public let category: String
    public let request: FileTrashRequest
    /// Another installed app from the same vendor may still use this item (shared helpers, updaters).
    public var sharedVendor = false
}

public actor ApplicationLeftoverScanner {
    public init() {}
    /// Absence from inventory is a candidate, never proof of ownership or safety.
    public func scan(installedIDs: Set<String>, home: URL = FileManager.default.homeDirectoryForCurrentUser) async throws -> [ApplicationLeftover] {
        let library = try canonicalFileURL(home).appendingPathComponent("Library")
        guard let libraryIdentity = try? FileIdentity.read(library), libraryIdentity.isDirectory, !libraryIdentity.isSymbolicLink else { return [] }
        var results: [ApplicationLeftover] = []
        // Bundle IDs are case-insensitive. Helpers named after an installed app (App.Helper, App-Helper)
        // belong to it; items sharing only the vendor prefix are flagged for review, not hidden.
        let installed = InstalledBundleIndex(installedIDs)
        let vendors = Set(installed.identifiers.compactMap { id -> String? in
            let parts = id.split(separator: ".")
            return parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : nil
        })
        func sharesVendor(_ id: String) -> Bool {
            let parts = id.lowercased().split(separator: ".")
            return parts.count >= 3 && vendors.contains(parts.prefix(2).joined(separator: "."))
        }
        let locations = [("Caches", String(localized: "Önbellek")), ("Logs", String(localized: "Günlük")), ("Preferences", String(localized: "Tercihler")),
                         ("Application Support", String(localized: "Uygulama verisi")), ("Saved Application State", String(localized: "Kaydedilmiş durum")),
                         ("HTTPStorages", String(localized: "HTTP verisi")), ("WebKit", String(localized: "Web verisi"))]
        for (folder, category) in locations {
            let directory = library.appendingPathComponent(folder)
            guard let directoryIdentity = try? FileIdentity.read(directory), directoryIdentity.isDirectory, !directoryIdentity.isSymbolicLink else { continue }
            guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in urls.prefix(10_000) {
                try Task.checkCancellation()
                guard let identity = try? FileIdentity.read(url), !identity.isSymbolicLink,
                      identity.isRegularFile || identity.isDirectory else { continue }
                var id = url.lastPathComponent
                if folder == "Preferences", (!id.hasSuffix(".plist") || !identity.isRegularFile) { continue }
                if folder == "Saved Application State", (!id.hasSuffix(".savedState") || !identity.isDirectory) { continue }
                if folder == "Preferences", id.hasSuffix(".plist") { id = String(id.dropLast(6)) }
                if folder == "Saved Application State", id.hasSuffix(".savedState") { id = String(id.dropLast(11)) }
                guard id.range(of: #"^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2,}$"#, options: .regularExpression) != nil,
                      !id.hasPrefix("com.apple."), !id.hasPrefix("com.doancan.MacPocket"),
                      !installed.containsApplicationOrHelper(id) else { continue }
                results.append(.init(bundleID: id, category: category, request: .init(url: url, identity: identity, root: library),
                                     sharedVendor: sharesVendor(id)))
                await Task.yield()
            }
        }
        return results.sorted { $0.bundleID < $1.bundleID }
    }
}
