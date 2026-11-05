// Synthetic AppKit producer: verifies our transfer helper, not physical cross-app dragging.
import AppKit
import Foundation

private final class Reader: @unchecked Sendable {
    let callback: (URL, (any Error)?) -> Void
    init(_ callback: @escaping (URL, (any Error)?) -> Void) { self.callback = callback }
}
private final class Receiver: NSFilePromiseReceiver, @unchecked Sendable {
    let count: Int
    let delay: TimeInterval
    let fail: Bool
    let outside: Bool
    private var called = false
    init(count: Int, delay: TimeInterval = 0, fail: Bool = false, outside: Bool = false) { self.count = count; self.delay = delay; self.fail = fail; self.outside = outside; super.init() }
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { fatalError() }
    override var fileNames: [String] { called ? (0..<count).map { "file-\($0).txt" } : [] }
    override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:], operationQueue: OperationQueue,
                                      reader: @escaping (URL, (any Error)?) -> Void) {
        called = true
        let boxed = Reader(reader)
        for index in 0..<count {
            let target = outside ? destinationDir.deletingLastPathComponent() : destinationDir
            let url = target.appendingPathComponent("file-\(index).txt")
            let delay = delay
            let fail = fail
            operationQueue.addOperation {
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                if fail { boxed.callback(url, CocoaError(.fileWriteUnknown)); return }
                do {
                    try Data("promised file \(index)".utf8).write(to: url)
                    boxed.callback(url, nil)
                } catch { boxed.callback(url, error) }
            }
        }
    }
}
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var result: ShelfPromiseTransfer.Delivery?
    func set(_ value: ShelfPromiseTransfer.Delivery) { lock.lock(); result = value; lock.unlock() }
    func get() -> ShelfPromiseTransfer.Delivery? { lock.lock(); defer { lock.unlock() }; return result }
}
@main struct Probe {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-Promise-Probe-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var results: [String:Bool] = [:]
        for mode in ["success", "capacity", "failure", "cancel", "escape"] {
            let collector = Collector()
            let incoming = root.appendingPathComponent(mode + "/Incoming")
            let storage = root.appendingPathComponent(mode + "/Files")
            let transfer = try ShelfPromiseTransfer(incoming: incoming, storage: storage, maximum: mode == "capacity" ? 1 : 3) { collector.set($0) }
            let receiver = Receiver(count: 2, delay: mode == "cancel" ? 0.15 : 0, fail: mode == "failure", outside: mode == "escape")
            results[mode+"NamesInitiallyEmpty"] = receiver.fileNames.isEmpty
            let reserved = transfer.receive([receiver])
            results[mode+"Reservation"] = reserved == (mode == "capacity" ? 1 : 2)
            if mode == "cancel" { transfer.cancel() }
            for _ in 0..<100 {
                if !FileManager.default.fileExists(atPath: incoming.path) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            if mode == "cancel" {
                results["cancelNoDelivery"] = collector.get() == nil
                results["cancelCleansIncoming"] = !FileManager.default.fileExists(atPath: incoming.path)
                let enumerator = FileManager.default.enumerator(at: storage, includingPropertiesForKeys: nil)
                results["cancelCleansManagedCopies"] = !(enumerator?.allObjects as? [URL] ?? []).contains { $0.pathExtension == "txt" }
            } else {
                let result = collector.get()
                results[mode+"CleansIncoming"] = !FileManager.default.fileExists(atPath: incoming.path)
                results[mode+"Delivery"] = result?.urls.count == (["failure", "escape"].contains(mode) ? 0 : (mode == "capacity" ? 1 : 2))
                results[mode+"FailureState"] = result?.failed == (mode != "success")
                results[mode+"CopiedFilesReadable"] = result?.urls.allSatisfy { (try? String(contentsOf: $0, encoding: .utf8))?.hasPrefix("promised file") == true } ?? false
            }
        }
        let json = try JSONSerialization.data(withJSONObject: ["checks":results,"passed":results.values.allSatisfy{$0}],options:[.sortedKeys,.prettyPrinted])
        try json.write(to: URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/shelf-promise-probe.json"))
        print(String(decoding:json,as:UTF8.self))
    }
}
