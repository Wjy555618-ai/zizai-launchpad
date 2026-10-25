import ServiceManagement
import XCTest

@testable import 自在启动台

@MainActor
final class LoginItemManagerTests: XCTestCase {
    func testInitializationNeverRegistersWithoutUserAction() {
        let service = TestLoginItemService(status: .notFound)

        let manager = LoginItemManager(service: service)

        XCTAssertFalse(manager.isRequested)
        XCTAssertEqual(service.registerCount, 0)
    }

    func testExplicitEnableRegistersOnce() {
        let service = TestLoginItemService(status: .notRegistered)
        let manager = LoginItemManager(service: service)

        manager.setRequested(true)

        XCTAssertTrue(manager.isRequested)
        XCTAssertEqual(service.registerCount, 1)
    }

    func testApprovalStateDoesNotRegisterAgain() {
        let service = TestLoginItemService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)

        manager.setRequested(true)

        XCTAssertTrue(manager.isRequested)
        XCTAssertEqual(service.registerCount, 0)
    }

    func testExplicitDisableUnregistersOnce() {
        let service = TestLoginItemService(status: .enabled)
        let manager = LoginItemManager(service: service)

        manager.setRequested(false)

        XCTAssertFalse(manager.isRequested)
        XCTAssertEqual(service.unregisterCount, 1)
    }

    func testRejectedRegistrationSurfacesAnActionableErrorAndRefreshClearsIt() {
        let service = TestLoginItemService(status: .notRegistered)
        service.registerError = TestLoginItemError.denied
        let manager = LoginItemManager(service: service)

        manager.setRequested(true)

        XCTAssertEqual(service.registerCount, 1)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertFalse(manager.isRequested)

        service.registerError = nil
        manager.refresh()
        XCTAssertNil(manager.errorMessage)
    }

    func testRedundantRequestsDoNotMutateTheSystemService() {
        let enabledService = TestLoginItemService(status: .enabled)
        let enabledManager = LoginItemManager(service: enabledService)
        enabledManager.setRequested(true)
        XCTAssertEqual(enabledService.registerCount, 0)

        let disabledService = TestLoginItemService(status: .notRegistered)
        let disabledManager = LoginItemManager(service: disabledService)
        disabledManager.setRequested(false)
        XCTAssertEqual(disabledService.unregisterCount, 0)
    }

    func testOpeningSystemSettingsDelegatesToTheService() {
        let service = TestLoginItemService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)

        manager.openSystemSettings()

        XCTAssertEqual(service.openSettingsCount, 1)
    }
}

private enum TestLoginItemError: Error {
    case denied
}

private final class TestLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}
