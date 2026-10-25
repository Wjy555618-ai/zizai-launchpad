import AppKit
import CoreServices
import XCTest

@testable import 自在启动台

final class LaunchPresentationTests: XCTestCase {
    func testInteractiveLaunchAlwaysPresents() {
        var state = LaunchPresentationState(isLoginItemLaunch: false)

        XCTAssertFalse(state.isSilentLoginLaunch)
        XCTAssertEqual(state.applicationDidFinishLaunching(), .present)
        XCTAssertEqual(state.applicationDidBecomeActive(), .present)

        state.silentSuppressionDidSettle()
        XCTAssertFalse(state.isSilentLoginLaunch)
        XCTAssertEqual(state.applicationDidBecomeActive(), .present)
    }

    func testLoginLaunchSuppressesUntilInitialActivationSettles() {
        var state = LaunchPresentationState(isLoginItemLaunch: true)

        XCTAssertTrue(state.isSilentLoginLaunch)
        XCTAssertEqual(state.applicationDidFinishLaunching(), .suppress)
        XCTAssertEqual(state.applicationDidBecomeActive(), .suppress)

        state.silentSuppressionDidSettle()
        XCTAssertTrue(state.isSilentLoginLaunch)
        XCTAssertEqual(state.applicationDidBecomeActive(), .present)
        XCTAssertFalse(state.isSilentLoginLaunch)
        XCTAssertEqual(state.applicationDidBecomeActive(), .present)
    }

    func testExplicitUserRequestOverridesLoginSuppression() {
        var state = LaunchPresentationState(isLoginItemLaunch: true)

        XCTAssertEqual(state.userRequestedPresentation(), .present)
        XCTAssertFalse(state.isSilentLoginLaunch)
        XCTAssertEqual(state.applicationDidBecomeActive(), .present)
    }

    func testLoginItemDetectorRejectsMissingUnrelatedAndUnmarkedEvents() {
        XCTAssertFalse(LoginItemLaunchDetector.isLoginItemLaunch(event: nil))

        let unrelatedEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        XCTAssertFalse(LoginItemLaunchDetector.isLoginItemLaunch(event: unrelatedEvent))
        XCTAssertFalse(
            LoginItemLaunchDetector.isLoginItemLaunch(event: makeOpenApplicationEvent())
        )
    }

    func testLoginItemDetectorRecognizesBothDocumentedLaunchMarkers() {
        let directEvent = makeOpenApplicationEvent()
        directEvent.setParam(
            NSAppleEventDescriptor(boolean: false),
            forKeyword: AEKeyword(keyAELaunchedAsLogInItem)
        )
        XCTAssertTrue(LoginItemLaunchDetector.isLoginItemLaunch(event: directEvent))

        let propertyEvent = makeOpenApplicationEvent()
        propertyEvent.setParam(
            NSAppleEventDescriptor(typeCode: DescType(keyAELaunchedAsLogInItem)),
            forKeyword: AEKeyword(keyAEPropData)
        )
        XCTAssertTrue(LoginItemLaunchDetector.isLoginItemLaunch(event: propertyEvent))

        let unrelatedPropertyEvent = makeOpenApplicationEvent()
        unrelatedPropertyEvent.setParam(
            NSAppleEventDescriptor(typeCode: DescType(typeBoolean)),
            forKeyword: AEKeyword(keyAEPropData)
        )
        XCTAssertFalse(LoginItemLaunchDetector.isLoginItemLaunch(event: unrelatedPropertyEvent))
    }

    private func makeOpenApplicationEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }
}
