#if DEBUG
import Foundation
import OSLog

/// Preferences for a runtime audit, kept in a temporary folder that `remove()` deletes.
///
/// A named suite would leave a plist in ~/Library/Preferences, and cfprefsd keeps that file even after
/// `removePersistentDomain`; an absolute-path suite stores it inside the folder instead.
@MainActor
final class AuditDefaults {
    private let folder: URL
    private var suites: [String] = []
    private let logger = Logger(subsystem: "com.doancan.MacPocket", category: "RuntimeAudit")

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPocketAudit-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A separate store inside the folder; nil only if the system refuses the suite.
    func make(_ name: String = "defaults") -> UserDefaults? {
        let suite = folder.appendingPathComponent(name).path
        suites.append(suite)
        return UserDefaults(suiteName: suite)
    }

    func remove() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        do { try FileManager.default.removeItem(at: folder) } catch {
            logger.error("Audit preferences folder was not removed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
