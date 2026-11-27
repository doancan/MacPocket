import XCTest
@testable import MacPocketCore

/// Controlled HTTPS URLProtocol responses exercise the real session/delegate/cancellation path, with no
/// network.
private final class UpdateHTTPFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "update-fixture.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        if path == "/pending" { return }
        let status = path == "/rate" ? 429 : 200
        let headers = path == "/size-header" ? ["Content-Length": "9999999"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "/size-body" { client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 2_097_153)) }
        else { client?.urlProtocol(self, didLoad: Data("metadata".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ApplicationUpdateHTTPTests: XCTestCase {
    private static func fetch(_ path: String) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateHTTPFixture.self]
        return try await ApplicationUpdateHTTP.fetch(URL(string: "https://update-fixture.example/" + path)!, configuration: config)
    }
    func testSuccessfulMetadataResponseReturnsExactlyItsBytes() async throws {
        let data = try await Self.fetch("ok")
        XCTAssertEqual(data, Data("metadata".utf8))
    }
    func testRateLimitIsAnErrorRatherThanAnEmptyCatalog() async {
        do { _ = try await Self.fetch("rate"); XCTFail("HTTP 429 succeeded") }
        catch ApplicationUpdateError.http(let code) { XCTAssertEqual(code, 429) } catch { XCTFail("\(error)") }
    }
    func testOversizedResponseHeaderAndStreamAreRejected() async {
        for path in ["size-header", "size-body"] {
            do { _ = try await Self.fetch(path); XCTFail("oversized metadata succeeded") }
            catch ApplicationUpdateError.tooLarge {} catch { XCTFail("\(error)") }
        }
    }
    func testInFlightCancellationReleasesARequestThatNeverReturns() async {
        let task = Task { try await Self.fetch("pending") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled request succeeded") }
        catch is CancellationError {} catch { XCTFail("\(error)") }
    }
    func testAlreadyCancelledRequestDoesNotStartLoading() async {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await Self.fetch("pending")
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled request succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
}
