import XCTest
@testable import MacPocketCore

@MainActor
final class LoginItemControllerTests: XCTestCase {
    func testReadsExternalStateInsteadOfRememberingToggle() {
        let service = LoginItemFixture(status: .enabled)
        let controller = LoginItemController(service: service)
        XCTAssertEqual(controller.status, .enabled)
        service.status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.status.isRegistered)
    }

    func testRegistrationPreservesPendingApprovalState() async {
        let service = LoginItemFixture(status: .notRegistered)
        service.registerResult = .requiresApproval
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.status.isRegistered)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertNil(controller.error)
    }

    func testFailedRegistrationDoesNotInventSuccess() async {
        let service = LoginItemFixture(status: .notRegistered)
        service.failure = NSError(domain: "LoginItemFixture", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Registration denied"])
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertEqual(controller.error, "Registration denied")
        XCTAssertFalse(controller.isUpdating)
    }

    func testUnregistersPendingItemAndReadsResult() async {
        let service = LoginItemFixture(status: .requiresApproval)
        let controller = LoginItemController(service: service)
        await controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertFalse(controller.isUpdating)
    }

    func testAlreadyRegisteredDoesNotRegisterAgain() async {
        let service = LoginItemFixture(status: .enabled)
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(controller.status, .enabled)
    }
}

@MainActor
private final class LoginItemFixture: LoginItemServicing {
    var status: LoginItemStatus
    var registerResult = LoginItemStatus.enabled
    var failure: NSError?
    var registerCount = 0
    var unregisterCount = 0
    init(status: LoginItemStatus) { self.status = status }
    func register() throws {
        registerCount += 1
        if let failure { throw failure }
        status = registerResult
    }
    func unregister() async throws {
        unregisterCount += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}
