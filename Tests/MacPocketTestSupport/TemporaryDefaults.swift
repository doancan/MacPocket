import Foundation
import XCTest

/// A `UserDefaults` store kept in its own temporary folder, for tests.
///
/// A plain suite name ("SomeTests.<UUID>") writes `~/Library/Preferences/<name>.plist`, and cfprefsd keeps
/// (and sometimes rewrites) that file even after `removePersistentDomain`, so every test run left files
/// behind there. An absolute-path suite keeps the plist inside the folder, which `remove()` deletes.
public final class TemporaryDefaults {
    public let suiteName: String
    public let defaults: UserDefaults
    private let folder: URL

    public init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPocketTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suiteName = folder.appendingPathComponent("defaults").path
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw CocoaError(.fileWriteUnknown) }
        self.defaults = defaults
    }

    /// Another handle on the same store, as the app would open it after a relaunch.
    public func reopen() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw CocoaError(.fileReadUnknown) }
        return defaults
    }

    public func remove() throws { try Self.remove(suiteName: suiteName, folder: folder) }

    fileprivate var cleanup: @Sendable () throws -> Void {
        { [suiteName, folder] in try Self.remove(suiteName: suiteName, folder: folder) }
    }

    private static func remove(suiteName: String, folder: URL) throws {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: folder)
    }
}

public extension XCTestCase {
    /// Empty defaults for this test, deleted when it ends (a failed deletion fails the test).
    func temporaryDefaultsStore() -> TemporaryDefaults {
        let store: TemporaryDefaults
        do { store = try TemporaryDefaults() } catch {
            // Without a writable temporary folder no test can run; stop with the reason rather than fail
            // obscurely later.
            preconditionFailure("Couldn't create temporary defaults: \(error)")
        }
        let cleanup = store.cleanup
        addTeardownBlock { try cleanup() }
        return store
    }

    func temporaryDefaults() -> UserDefaults { temporaryDefaultsStore().defaults }
}
