import Foundation

/// Metadata only: bounded ephemeral HTTPS, no cookies, credentials, cache, package downloads or installation.
public enum ApplicationUpdateHTTP {
    public static func fetch(_ url: URL) async throws -> Data {
        try await fetch(url, configuration: .ephemeral)
    }
    static func fetch(_ url: URL, configuration: URLSessionConfiguration) async throws -> Data {
        guard ApplicationUpdateURL.valid(url) else { throw ApplicationUpdateError.invalidURL }
        let download = UpdateMetadataDownload(configuration: configuration)
        return try await withTaskCancellationHandler { try await download.start(url) } onCancel: { download.cancel() }
    }
}

private final class UpdateMetadataDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var cancelled = false
    private var redirects = 0
    private static let limit = 2_097_152
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration) { self.configuration = configuration; super.init() }

    func start(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            let config = configuration.copy() as! URLSessionConfiguration
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 25
            config.waitsForConnectivity = false
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            var request = URLRequest(url: url)
            request.setValue("MacPocket", forHTTPHeaderField: "User-Agent")
            let task = session.dataTask(with: request)
            let active = lock.withLock {
                guard !cancelled else { return false }
                self.continuation = continuation
                self.session = session
                self.task = task
                return true
            }
            if active { task.resume() } else { session.invalidateAndCancel(); continuation.resume(throwing: CancellationError()) }
        }
    }
    func cancel() { lock.withLock { cancelled = true }; finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Data, Error>) {
        let state = lock.withLock { () -> (CheckedContinuation<Data, Error>?, URLSession?) in
            let state = (continuation, session)
            continuation = nil
            session = nil
            task = nil
            buffer = Data()
            return state
        }
        state.1?.invalidateAndCancel()
        state.0?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, let url = response.url, ApplicationUpdateURL.valid(url) else {
            completionHandler(.cancel)
            finish(.failure(ApplicationUpdateError.invalidURL))
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            completionHandler(.cancel)
            finish(.failure(ApplicationUpdateError.http(response.statusCode)))
            return
        }
        guard response.expectedContentLength <= Self.limit else {
            completionHandler(.cancel)
            finish(.failure(ApplicationUpdateError.tooLarge))
            return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let accepted = lock.withLock {
            guard continuation != nil, data.count <= Self.limit - buffer.count else { return false }
            buffer.append(data)
            return true
        }
        if !accepted { finish(.failure(ApplicationUpdateError.tooLarge)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else { let data = lock.withLock { buffer }; finish(.success(data)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = lock.withLock { redirects += 1; return redirects <= 5 }
        guard allowed, let url = request.url, ApplicationUpdateURL.valid(url) else {
            completionHandler(nil)
            finish(.failure(ApplicationUpdateError.invalidURL))
            return
        }
        completionHandler(request)
    }
}
