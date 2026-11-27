import Foundation

/// Serializes automatic writes with explicit load/erase/flush boundaries.
/// Mutable state is accessed exclusively on `queue`; callbacks never hold that queue waiting for the UI.
public final class ClipboardArchiveWriter: @unchecked Sendable {
    private let archive: ClipboardArchive
    private let write: @Sendable (ClipboardHistory) throws -> Void
    private let queue = DispatchQueue(label: "com.doancan.MacPocket.clipboard-storage", qos: .utility,
                                      autoreleaseFrequency: .workItem)
    private var savedRevision: UInt64?

    public convenience init(archive: ClipboardArchive) {
        self.init(archive: archive, write: { try archive.save($0) })
    }

    init(archive: ClipboardArchive, write: @escaping @Sendable (ClipboardHistory) throws -> Void) {
        self.archive = archive
        self.write = write
    }

    public func save(_ history: ClipboardHistory, revision: UInt64,
                     completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        queue.async { [self] in
            completion(Result { try saveOnQueue(history, revision: revision) })
        }
    }

    /// Explicit durability boundary for shutdown and storage transitions; ordinary autosave never uses this.
    public func saveSynchronously(_ history: ClipboardHistory, revision: UInt64) throws {
        try queue.sync { try saveOnQueue(history, revision: revision) }
    }

    public func loadSynchronously() throws -> ClipboardHistory {
        try queue.sync { try archive.load() }
    }

    public func eraseAllSynchronously() throws {
        try queue.sync {
            savedRevision = nil
            try archive.eraseAll()
        }
    }

    private func saveOnQueue(_ history: ClipboardHistory, revision: UInt64) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        guard savedRevision != revision else { return }
        try write(history)
        savedRevision = revision
    }
}
