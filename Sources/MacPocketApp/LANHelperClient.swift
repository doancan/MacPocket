import Foundation
import MacPocketCore

/// A persistent connection avoids releasing the helper's fan safety state after every network request.
@MainActor
final class LANHelperClient {
    static let shared = LANHelperClient()
    private var connection: NSXPCConnection?

    @MainActor private final class PendingReply {
        private var continuation: CheckedContinuation<[String: String], Error>?
        init(_ continuation: CheckedContinuation<[String: String], Error>) { self.continuation = continuation }
        func finish(_ result: Result<[String: String], Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    func discover(_ network: LANNetworkInfo) async throws -> [String: String] {
        try FanControlService.shared.prepareNetworkHelper()
        _ = try LANHelperScanRequest(cidr: network.subnet.description, interface: network.viaInterface)
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: MacPocketHelperConstants.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: MacPocketHelperXPC.self)
            connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
            connection.resume()
            self.connection = connection
        }
        guard let connection else { throw LANHelperError.scanFailed }
        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingReply(continuation)
            let timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(130))
                guard !Task.isCancelled else { return }
                pending.finish(.failure(LANHelperError.scanFailed))
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                Task { @MainActor in
                    timeout.cancel()
                    pending.finish(.failure(error))
                }
            } as? MacPocketHelperXPC
            guard let proxy else { timeout.cancel(); pending.finish(.failure(LANHelperError.scanFailed)); return }
            proxy.scanMACAddresses(cidr: network.subnet.description, interface: network.viaInterface) { addresses, error in
                Task { @MainActor in
                    timeout.cancel()
                    if let error {
                        pending.finish(.failure(NSError(domain: "MacPocket.Helper", code: 2,
                                                        userInfo: [NSLocalizedDescriptionKey: error])))
                    } else { pending.finish(.success(addresses)) }
                }
            }
        }
    }
}
