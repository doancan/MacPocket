import Darwin
import Foundation

/// The numbers of the last scan, kept so the menu bar can show them without scanning again.
public struct SystemDataSummary: Codable, Equatable, Sendable {
    public static let key = "MacPocket.systemData.lastSummary"

    public let date: Date
    public let systemDataBytes: Int64
    public let safeBytes: Int64
    public let freeBytes: Int64
    public let purgeableBytes: Int64

    public init(date: Date, systemDataBytes: Int64, safeBytes: Int64, freeBytes: Int64, purgeableBytes: Int64) {
        self.date = date; self.systemDataBytes = systemDataBytes; self.safeBytes = safeBytes
        self.freeBytes = freeBytes; self.purgeableBytes = purgeableBytes
    }

    /// The widget cannot read the app's preferences, so the same numbers are also written to a small file next to its data.
    public static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "MacPocket", directoryHint: .isDirectory)
            .appending(path: "system-data-summary.json", directoryHint: .notDirectory)
    }

    /// The file path computed from the real home folder. A sandboxed widget's `applicationSupportDirectory` points
    /// into its own container, so it reads the file through the user's actual home, which its entitlement allows.
    public static func realHomeFileURL() -> URL? {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appending(path: "Library/Application Support/MacPocket/system-data-summary.json")
    }

    public static func load(fromFile url: URL) -> Self? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: data)
    }

    public static func load(from defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: data)
    }

    /// - Parameter file: where the widget's copy goes. Nil (the default) writes none, so tests and audits can never touch
    ///   the file a real widget reads; the app passes `SystemDataSummary.fileURL`.
    public func save(to defaults: UserDefaults, file: URL? = nil) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        defaults.set(data, forKey: Self.key)
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
