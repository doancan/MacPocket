import CoreFoundation
import XCTest
@testable import MacPocketCore

@MainActor final class SwitcherCLITests: XCTestCase {
    func testParserAcceptsDocumentedCommandsAndOneBasedIndexes() throws {
        let cases: [([String],SwitcherCLICommand)] = [(["list"],.list(detailed: false)),(["list","--detailed"],.list(detailed: true)),
            (["focus","42"],.focus("42")),(["focus","opaque:tab"],.focus("opaque:tab")),(["focus","--mru","2"],.focusMRU(2)),
            (["show"],.show(1)),(["show","9"],.show(9)),(["hide"],.hide),(["status"],.status)]
        for (args,expected) in cases { XCTAssertEqual(try SwitcherCLICommand.parse(args),expected) }
    }
    func testParserRejectsUnknownFlagsMissingExtraAndInvalidIndexes() {
        for args in [[],["list","--all"],["list","--detailed","extra"],["focus"],["focus",""],["focus","--bad"],
                     ["focus","--mru","0"],["focus","--mru","-1"],["focus","--mru","1.5"],["show","0"],["show","10"],["hide","x"],["status","x"],
                     ["focus",String(repeating: "a",count: 513)],["focus","--mru",String(repeating: "9",count: 100)]] {
            XCTAssertThrowsError(try SwitcherCLICommand.parse(args),"\(args)")
        }
    }
    func testWireValidationCannotBypassParserAndRejectsVersionsAndDeadlines() throws {
        for command in [SwitcherCLICommand.show(0),.show(10),.focusMRU(0),.focus("")] { XCTAssertFalse(SwitcherCLIRequest(command: command).isCurrent) }
        XCTAssertFalse(SwitcherCLIRequest(command: .hide,expiresAt: .distantPast).isCurrent)
        XCTAssertFalse(SwitcherCLIRequest(command: .hide,expiresAt: Date().addingTimeInterval(60)).isCurrent)
        let data = try JSONEncoder().encode(SwitcherCLIRequest(command: .status))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any]);object["version"] = 2
        XCTAssertFalse(try JSONDecoder().decode(SwitcherCLIRequest.self,from: JSONSerialization.data(withJSONObject: object)).isCurrent)
    }
    func testUnavailableServerReturnsErrorInsteadOfEmptySuccess() {
        XCTAssertThrowsError(try SwitcherCLITransport.send(.init(command: .status),portName: UUID().uuidString)) { error in
            guard case SwitcherCLIError.notRunning = error else { return XCTFail("\(error)") }
        }
    }
    func testNativeMessagePortRepliesWhileMainActorRuns() async throws {
        let name = "com.doancan.MacPocket.Unit.CLI."+UUID().uuidString
        var calls = 0
        let listener = try SwitcherCLIListener(portName: name) { request in
            await MainActor.run { calls += 1 }
            return SwitcherCLIResponse(requestID: request.id,status: "hidden")
        }
        defer { listener.stop() }
        let reply = try await Task.detached { try SwitcherCLITransport.send(.init(command: .hide),portName: name) }.value
        XCTAssertEqual(reply.status,"hidden");XCTAssertEqual(calls,1)
        listener.stop()
        XCTAssertThrowsError(try SwitcherCLITransport.send(.init(command: .hide),portName: name))
    }
    func testDuplicateListenerDoesNotStealExistingEndpoint() async throws {
        let name = "com.doancan.MacPocket.Unit.CLI."+UUID().uuidString
        let first = try SwitcherCLIListener(portName: name) { SwitcherCLIResponse(requestID: $0.id,status: "first") }
        defer { first.stop() }
        XCTAssertThrowsError(try SwitcherCLIListener(portName: name) { SwitcherCLIResponse(requestID: $0.id,status: "second") })
        let reply = try await Task.detached { try SwitcherCLITransport.send(.init(command: .status),portName: name) }.value
        XCTAssertEqual(reply.status,"first")
    }
    func testMismatchedRequestIdentityIsRejected() async throws {
        let name = "com.doancan.MacPocket.Unit.CLI."+UUID().uuidString
        let listener = try SwitcherCLIListener(portName: name) { _ in SwitcherCLIResponse(requestID: UUID()) }
        defer { listener.stop() }
        do { _ = try await Task.detached { try SwitcherCLITransport.send(.init(command: .status),portName: name) }.value;XCTFail("Must reject mismatched identity") }
        catch { guard case SwitcherCLIError.invalidResponse = error else { return XCTFail("\(error)") } }
    }
    func testOversizedResponseReportsFailureWithoutTruncatedJSON() async throws {
        let name = "com.doancan.MacPocket.Unit.CLI."+UUID().uuidString
        let listener = try SwitcherCLIListener(portName: name) { SwitcherCLIResponse(requestID: $0.id,message: String(repeating: "x",count: 4*1024*1024)) }
        defer { listener.stop() }
        let reply = try await Task.detached { try SwitcherCLITransport.send(.init(command: .status),portName: name) }.value
        XCTAssertEqual(reply.status,"error");XCTAssertEqual(reply.errorCode,"response-too-large")
    }
    func testTimedOutWorkIsCancelledBeforeLateMutation() async throws {
        let name = "com.doancan.MacPocket.Unit.CLI."+UUID().uuidString
        var mutated = false
        let listener = try SwitcherCLIListener(portName: name) { request in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled,request.isCurrent { await MainActor.run { mutated = true } }
            return SwitcherCLIResponse(requestID: request.id)
        }
        defer { listener.stop() }
        do {
            let reply = try await Task.detached { try SwitcherCLITransport.send(.init(command: .hide,expiresAt: Date().addingTimeInterval(0.1)),portName: name) }.value
            XCTAssertEqual(reply.errorCode,"timed-out")
        } catch { guard case SwitcherCLIError.timedOut = error else { return XCTFail("\(error)") } }
        try await Task.sleep(for: .milliseconds(80));XCTAssertFalse(mutated)
    }
    func testNonFiniteGeometryDoesNotBreakAnEntireList() throws {
        let window = SwitchableWindow(id: "1",processID: 1,application: "App",title: "Başlık",applicationURL: nil,minimized: false,hidden: false,
            fullScreen: false,frontmost: false,windowAccessible: false,canClose: false,canMinimize: false,canFullScreen: false,
            launchedAt: nil,lastFocusedAt: nil,windowID: 1,frame: CGRect(x: Double.nan,y: 0,width: 40,height: 40))
        let row = SwitcherCLIWindow(window,mru: 1,detailed: true)
        XCTAssertNil(row.details?.frame);XCTAssertNoThrow(try JSONEncoder().encode(row))
        XCTAssertNil(SwitcherCLIWindow(window,mru: 1,detailed: false).details)
    }
}
