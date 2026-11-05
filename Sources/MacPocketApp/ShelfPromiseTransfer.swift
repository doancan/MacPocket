import AppKit

/// The reader callback is a coordinated read. Copy there, before returning to the producer.
/// Cancellation abandons our transfer; it cannot stop another application's writer.
final class ShelfPromiseTransfer: @unchecked Sendable {
    struct Delivery: Sendable {
        let urls: [URL]
        let failed: Bool
    }

    private let incoming: URL
    let storage: URL
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var expected: Int?
    private var received = 0
    private var cancelled = false
    private var completed = false
    private var urls: [URL] = []
    private var failed = false
    private var receivers: [NSFilePromiseReceiver] = []
    private let maximum: Int
    private let completion: @Sendable (Delivery) -> Void

    init(incoming: URL, storage: URL, maximum: Int, completion: @escaping @Sendable (Delivery) -> Void) throws {
        self.incoming = incoming
        self.storage = storage
        self.maximum = maximum
        self.completion = completion
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        queue.name = "MacPocket.Shelf.PromisedFiles"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
    }

    /// Must be called during the accepted-drop callback. fileNames is empty until this call.
    func receive(_ receivers: [NSFilePromiseReceiver]) -> Int {
        lock.lock()
        self.receivers = receivers
        lock.unlock()
        var count = 0
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: incoming, options: [:], operationQueue: queue) { [self] url, error in
                var copy: URL?
                lock.lock()
                let active = !cancelled && !completed && urls.count < maximum
                lock.unlock()
                if error == nil, active {
                    let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                    let root = incoming.resolvingSymlinksInPath().standardizedFileURL.path + "/"
                    if canonical.isFileURL, canonical.path.hasPrefix(root) {
                        let target = storage.appendingPathComponent(UUID().uuidString, isDirectory: true)
                        do {
                            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                            let destination = target.appendingPathComponent(canonical.lastPathComponent)
                            try FileManager.default.copyItem(at: canonical, to: destination)
                            copy = destination
                        } catch { try? FileManager.default.removeItem(at: target) }
                    }
                }
                record(copy, failed: error != nil || copy == nil)
            }
            count += max(1, receiver.fileNames.count)
        }
        lock.lock()
        expected = count
        lock.unlock()
        finishIfReady()
        return min(count, maximum)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let abandoned = urls
        urls = []
        lock.unlock()
        // Stay behind any in-flight coordinated copy. Producer callbacks remain alive for cleanup.
        queue.addOperation { [storage] in
            for url in abandoned where url.path.hasPrefix(storage.path + "/") {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
    }

    private func record(_ url: URL?, failed: Bool) {
        lock.lock()
        received += 1
        self.failed = self.failed || failed
        let discard = cancelled || completed
        if let url, !discard { urls.append(url) }
        lock.unlock()
        if let url, discard { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        finishIfReady()
    }

    private func finishIfReady() {
        lock.lock()
        guard !completed, let expected, received >= expected else { lock.unlock(); return }
        completed = true
        let delivery = Delivery(urls: urls, failed: failed)
        let notify = !cancelled
        urls = []
        receivers = []
        lock.unlock()
        try? FileManager.default.removeItem(at: incoming)
        if notify { completion(delivery) }
    }
}
