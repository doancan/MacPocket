import MacPocketTestSupport
import ServiceManagement
import XCTest
@testable import MacPocketApp

@MainActor private final class RegistrationFixture: HelperRegistration {
    var status: SMAppService.Status = .enabled
    var calls: [String] = []
    var failUnregister = false
    var failRegister = false
    func register() throws {
        calls.append("register")
        if failRegister { throw CocoaError(.featureUnsupported) }
        status = .requiresApproval
    }
    func unregister() async throws {
        calls.append("unregister")
        if failUnregister { throw CocoaError(.featureUnsupported) }
        status = .notRegistered
    }
}

@MainActor final class FanHelperRepairTests: XCTestCase {
    func testRepairRegistersTheHelperAgainForThisBuildAndAsksForApproval() async {
        let registration = RegistrationFixture()
        var approvalOpened = 0
        let service = FanControlService(defaults: temporaryDefaults(), registration: registration,
                                        openLoginItems: { approvalOpened += 1 })
        XCTAssertEqual(service.availability, .ready)
        await service.repairHelper()
        XCTAssertEqual(registration.calls, ["unregister", "register"])
        XCTAssertEqual(service.availability, .needsApproval)
        XCTAssertEqual(approvalOpened, 1)
        XCTAssertEqual(service.reading, .loading)
    }

    func testFailedUnregisterKeepsTheRegistrationAndExplains() async {
        let registration = RegistrationFixture()
        registration.failUnregister = true
        let service = FanControlService(defaults: temporaryDefaults(), registration: registration, openLoginItems: {})
        await service.repairHelper()
        XCTAssertEqual(registration.calls, ["unregister"])
        XCTAssertNotNil(service.message)
    }

    func testFailedRegistrationShowsOnlyItsOwnReasonNotAnOlderWarning() async {
        let registration = RegistrationFixture()
        registration.failUnregister = true
        let service = FanControlService(defaults: temporaryDefaults(), registration: registration, openLoginItems: {})
        await service.repairHelper()
        XCTAssertNotNil(service.message, "a warning from an earlier attempt")
        registration.failUnregister = false
        registration.failRegister = true
        await service.repairHelper()
        guard case .unavailable = service.availability else { return XCTFail("registration failure must be shown") }
        XCTAssertNil(service.message, "the card already explains why; an old warning beside it contradicts it")
    }
}
