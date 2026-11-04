import AppKit
import Foundation
import QuartzCore
import XCTest

@testable import 自在启动台

@MainActor
final class ApplicationRemovalTests: XCTestCase {
    func testPolicyProtectsSystemSelfAndInvalidPaths() {
        XCTAssertEqual(
            ApplicationRemovalPolicy.eligibility(for: app(path: "/Applications/Example.app")),
            .removable
        )

        assertProtected(
            ApplicationRemovalPolicy.eligibility(for: app(path: "/System/Applications/Music.app"))
        )
        assertProtected(
            ApplicationRemovalPolicy.eligibility(
                for: app(path: "/Applications/自在启动台.app"),
                currentApplicationURL: URL(fileURLWithPath: "/Applications/自在启动台.app")
            )
        )
        assertProtected(
            ApplicationRemovalPolicy.eligibility(for: app(path: "/Applications/not-an-app"))
        )
        XCTAssertEqual(
            ApplicationRecycleError.trashDirectoryUnavailable.errorDescription,
            "macOS 没有提供可用的废纸篓位置。"
        )
        XCTAssertEqual(
            ApplicationRecycleError.sourceStillPresent.errorDescription,
            "系统操作结束后，原应用仍然存在。"
        )
        XCTAssertFalse(
            WorkspaceApplicationRunningDetector().isRunning(
                app(path: "/Applications/Definitely-Not-Running.app")
            )
        )
    }

    func testRemovalCapabilityOwnsDestructiveAndExplanationPresentation() {
        XCTAssertTrue(ApplicationRemovalCapability.removable.presentsManagementBadge)
        XCTAssertTrue(ApplicationRemovalCapability.removable.isDestructiveAction)
        XCTAssertEqual(ApplicationRemovalCapability.removable.actionTitle, "移到废纸篓")
        XCTAssertEqual(ApplicationRemovalCapability.removable.actionSystemImage, "trash")

        let protected = ApplicationRemovalCapability.protected(reason: "系统保护")
        XCTAssertFalse(protected.presentsManagementBadge)
        XCTAssertFalse(protected.isDestructiveAction)
        XCTAssertEqual(protected.actionTitle, "了解为什么无法移除")
        XCTAssertEqual(protected.actionSystemImage, "lock.fill")

        XCTAssertTrue(ApplicationRemovalCapability.temporarilyUnavailable.presentsManagementBadge)
        XCTAssertFalse(ApplicationRemovalCapability.temporarilyUnavailable.isDestructiveAction)
        XCTAssertEqual(
            ApplicationRemovalCapability.temporarilyUnavailable.actionTitle,
            "了解当前无法移除原因"
        )
    }

    func testFileManagerRecyclerMovesARealFixtureToTrashAndReportsDestination() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "自在启动台-回收实现测试-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceRoot = fixtureRoot.appendingPathComponent("应用程序", isDirectory: true)
        let trashRoot = fixtureRoot.appendingPathComponent("废纸篓", isDirectory: true)
        let applicationURL = sourceRoot.appendingPathComponent("回收测试.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: trashRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: applicationURL,
            withIntermediateDirectories: true
        )
        try Data("自在启动台回收测试".utf8).write(
            to: applicationURL.appendingPathComponent("marker")
        )

        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let recycledURL = try await FileManagerApplicationRecycler(
            trashDirectoryOverride: trashRoot
        ).recycle(applicationURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: applicationURL.path))
        XCTAssertEqual(recycledURL.deletingLastPathComponent(), trashRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recycledURL.path))
    }

    func testFileManagerRecyclerPreservesExistingTrashItemWithUniqueName() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "自在启动台-废纸篓重名测试-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceRoot = fixtureRoot.appendingPathComponent("应用程序", isDirectory: true)
        let trashRoot = fixtureRoot.appendingPathComponent("废纸篓", isDirectory: true)
        let applicationURL = sourceRoot.appendingPathComponent("回收测试.app", isDirectory: true)
        let existingURL = trashRoot.appendingPathComponent("回收测试.app", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingURL, withIntermediateDirectories: true)
        try Data("旧应用".utf8).write(to: existingURL.appendingPathComponent("marker"))
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let recycledURL = try await FileManagerApplicationRecycler(
            trashDirectoryOverride: trashRoot
        ).recycle(applicationURL)

        XCTAssertEqual(recycledURL.lastPathComponent, "回收测试 2.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recycledURL.path))
    }

    func testPermissionClassifierRecognizesDirectAndNestedAppManagementDenials() {
        let applicationURL = URL(fileURLWithPath: "/Applications/Protected.app")
        let cocoaDenial = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError
        )
        XCTAssertTrue(
            ApplicationRemovalFailureClassifier.requiresAppManagementPermission(
                cocoaDenial,
                applicationURL: applicationURL
            )
        )

        let nestedDenial = NSError(
            domain: "ApplicationRemovalTests",
            code: 99,
            userInfo: [
                NSUnderlyingErrorKey: NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(EPERM)
                )
            ]
        )
        XCTAssertTrue(
            ApplicationRemovalFailureClassifier.requiresAppManagementPermission(
                nestedDenial,
                applicationURL: applicationURL
            )
        )
        XCTAssertFalse(
            ApplicationRemovalFailureClassifier.requiresAppManagementPermission(
                RemovalTestError.recycle,
                applicationURL: applicationURL
            )
        )
        XCTAssertFalse(
            ApplicationRemovalFailureClassifier.requiresAppManagementPermission(
                cocoaDenial,
                applicationURL: URL(fileURLWithPath: "/Applications/not-an-app")
            )
        )
    }

    func testManagementCanExitAndConfirmationRechecksRunningState() {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        let runningDetector = MutableRunningDetectorMock()
        let candidate = app(path: "/Applications/Example.app")
        let coordinator = ApplicationRemovalCoordinator(
            authorizer: authorizer,
            runningDetector: runningDetector,
            recycler: RecyclerMock(),
            onRemovalCompleted: { _ in }
        )

        coordinator.requestRemoval(of: candidate)
        XCTAssertEqual(coordinator.dialog?.kind, .confirmation)
        runningDetector.isRunningValue = true
        coordinator.confirmRemoval(of: candidate)
        XCTAssertEqual(coordinator.dialog?.kind, .running)
        XCTAssertEqual(authorizer.beginCount, 0)

        coordinator.dismissDialog()
        coordinator.endManagement()
        XCTAssertFalse(coordinator.isManaging)
        XCTAssertNil(coordinator.dialog)
    }

    func testCoordinatorRequestsAuthorizationBeforeConfirmation() {
        let authorizer = RemovalAuthorizerMock()
        let presenter = RemovalAuthorizationPresenterMock()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            authorizationPresenter: presenter
        )
        let candidate = app(path: "/Applications/Example.app")

        coordinator.requestRemoval(of: candidate)

        XCTAssertTrue(coordinator.isManaging)
        XCTAssertNil(coordinator.dialog)
        XCTAssertTrue(coordinator.isChoosingAuthorizationFolder)
        XCTAssertEqual(presenter.presentationCount, 1)
    }

    func testEntryPointerReleaseIsIgnoredOnceAndNextUnclaimedClickEndsManagement() async {
        let coordinator = makeCoordinator(
            authorizer: RemovalAuthorizerMock(),
            managementInactivityTimeout: 1
        )

        coordinator.beginManagement(trigger: .longPress)
        coordinator.endAfterUnclaimedPointerInteraction()
        await Task.yield()
        XCTAssertTrue(coordinator.isManaging)

        coordinator.endAfterUnclaimedPointerInteraction()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(coordinator.isManaging)
    }

    func testManagementInactivityDeadlineResetsAndEventuallyEndsSession() async {
        let coordinator = makeCoordinator(
            authorizer: RemovalAuthorizerMock(),
            managementInactivityTimeout: 0.08
        )

        coordinator.beginManagement(trigger: .accessibility)
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.noteActivity()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(coordinator.isManaging)

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(coordinator.isManaging)
    }

    func testRemovalDialogPausesInactivityUntilInteractionReturns() async {
        let authorizer = RemovalAuthorizerMock()
        let presenter = RemovalAuthorizationPresenterMock()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            authorizationPresenter: presenter,
            managementInactivityTimeout: 0.04
        )

        coordinator.requestRemoval(of: app(path: "/Applications/Example.app"))
        XCTAssertTrue(coordinator.isChoosingAuthorizationFolder)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(coordinator.isManaging)

        presenter.complete(.cancelled)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(coordinator.isManaging)
    }

    func testManagementUsesContinuousEntrySteadyAndExitPhases() async {
        let coordinator = makeCoordinator(authorizer: RemovalAuthorizerMock())

        coordinator.beginManagement(trigger: .accessibility)
        XCTAssertEqual(coordinator.managementPhase, .entering)
        XCTAssertTrue(coordinator.isManaging)
        XCTAssertTrue(coordinator.isManagementPresented)

        try? await Task.sleep(
            nanoseconds: UInt64(
                (ApplicationManagementMotion.entryDuration + 0.04) * 1_000_000_000
            )
        )
        XCTAssertEqual(coordinator.managementPhase, .active)

        coordinator.endManagement(reason: .explicit)
        XCTAssertEqual(coordinator.managementPhase, .exiting)
        XCTAssertFalse(coordinator.isManaging)
        XCTAssertTrue(coordinator.isManagementPresented)

        try? await Task.sleep(
            nanoseconds: UInt64(
                (ApplicationManagementMotion.exitDuration + 0.04) * 1_000_000_000
            )
        )
        XCTAssertEqual(coordinator.managementPhase, .inactive)
        XCTAssertFalse(coordinator.isManagementPresented)
    }

    func testManagementTransitionsAreFiniteAndBounded() {
        XCTAssertGreaterThan(ApplicationManagementMotion.entryDuration, 0)
        XCTAssertGreaterThan(ApplicationManagementMotion.exitDuration, 0)
        XCTAssertLessThanOrEqual(ApplicationManagementMotion.entryDuration, 0.3)
        XCTAssertLessThanOrEqual(ApplicationManagementMotion.exitDuration, 0.3)
        XCTAssertGreaterThanOrEqual(ApplicationManagementMotion.removalDuration, 0.25)
        XCTAssertLessThanOrEqual(ApplicationManagementMotion.removalDuration, 0.4)
        XCTAssertLessThan(
            ApplicationManagementMotion.reducedRemovalDuration,
            ApplicationManagementMotion.removalDuration
        )
        XCTAssertLessThan(ApplicationManagementMotion.removalScale, 1)
        XCTAssertGreaterThan(ApplicationManagementMotion.jiggleDuration, 0)
        XCTAssertEqual(
            ApplicationManagementMotion.jiggleRotationValues.first,
            ApplicationManagementMotion.jiggleRotationValues.last
        )
        XCTAssertNotEqual(
            ApplicationManagementMotion.jigglePhase(for: "first"),
            ApplicationManagementMotion.jigglePhase(for: "second")
        )
    }

    func testManagementJiggleRunsOnCoreAnimationWithoutChangingLayout() {
        let view = ApplicationManagementJiggleImageView()
        view.frame = NSRect(x: 4, y: 6, width: 72, height: 72)
        let originalFrame = view.frame
        view.configure(
            image: NSImage(size: NSSize(width: 72, height: 72)),
            renderedSize: 72,
            identifier: "com.example.one",
            isJiggling: true
        )

        let animation = view.installedJiggleAnimation as? CAAnimationGroup
        XCTAssertNotNil(animation)
        XCTAssertEqual(animation?.repeatCount, .infinity)
        XCTAssertEqual(view.frame, originalFrame)

        view.configure(
            image: NSImage(size: NSSize(width: 72, height: 72)),
            renderedSize: 72,
            identifier: "com.example.one",
            isJiggling: false
        )
        XCTAssertNil(view.installedJiggleAnimation)
    }

    func testCoordinatorBlocksRunningApplicationWithoutForcingItToQuit() {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        let runningDetector = RunningDetectorMock(isRunning: true)
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            runningDetector: runningDetector
        )

        coordinator.requestRemoval(of: app(path: "/Applications/Running.app"))

        XCTAssertEqual(coordinator.dialog?.kind, .running)
        XCTAssertEqual(authorizer.beginCount, 0)
    }

    func testCoordinatorBlocksProtectedApplicationBeforeAuthorization() {
        let authorizer = RemovalAuthorizerMock()
        let coordinator = makeCoordinator(authorizer: authorizer)

        coordinator.requestRemoval(of: app(path: "/System/Applications/Music.app"))

        XCTAssertEqual(coordinator.dialog?.kind, .blocked)
        XCTAssertEqual(authorizer.beginCount, 0)
        assertProtectedCapability(
            coordinator.removalCapability(for: app(path: "/System/Applications/Music.app"))
        )
    }

    func testSelectedFolderAuthorizationContinuesToConfirmation() {
        let authorizer = RemovalAuthorizerMock()
        let presenter = RemovalAuthorizationPresenterMock()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            authorizationPresenter: presenter
        )
        let candidate = app(path: "/Applications/Example.app")

        coordinator.requestRemoval(of: candidate)
        XCTAssertNil(coordinator.dialog)
        XCTAssertTrue(coordinator.isChoosingAuthorizationFolder)
        presenter.complete(.selected(URL(fileURLWithPath: "/Applications")))

        XCTAssertTrue(authorizer.isAuthorized)
        XCTAssertEqual(coordinator.dialog?.kind, .confirmation)
    }

    func testAuthorizationSelectionHasOneOwnerAndIgnoresDuplicateStart() {
        let authorizer = RemovalAuthorizerMock()
        let presenter = RemovalAuthorizationPresenterMock()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            authorizationPresenter: presenter
        )
        let candidate = app(path: "/Applications/Example.app")

        coordinator.requestRemoval(of: candidate)
        coordinator.beginAuthorizationSelection(for: candidate)
        coordinator.beginAuthorizationSelection(for: candidate)

        XCTAssertTrue(coordinator.isChoosingAuthorizationFolder)
        XCTAssertEqual(presenter.presentationCount, 1)
    }

    func testAuthorizationCancellationReturnsToRetryableIdleState() {
        let authorizer = RemovalAuthorizerMock()
        let presenter = RemovalAuthorizationPresenterMock()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            authorizationPresenter: presenter
        )
        let candidate = app(path: "/Applications/Example.app")

        coordinator.requestRemoval(of: candidate)
        presenter.complete(.cancelled)
        XCTAssertFalse(coordinator.isChoosingAuthorizationFolder)
        XCTAssertNil(coordinator.dialog)

        coordinator.requestRemoval(of: candidate)
        XCTAssertTrue(coordinator.isChoosingAuthorizationFolder)
        XCTAssertEqual(presenter.presentationCount, 2)
    }

    func testLifecycleExitCannotTearDownActiveAuthorizationSelection() {
        let authorizer = RemovalAuthorizerMock()
        let presenter = RemovalAuthorizationPresenterMock()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            authorizationPresenter: presenter
        )
        let candidate = app(path: "/Applications/Example.app")

        coordinator.requestRemoval(of: candidate)
        coordinator.endManagement(reason: .lifecycle)

        XCTAssertTrue(coordinator.isChoosingAuthorizationFolder)
        XCTAssertTrue(coordinator.isManagementPresented)
        presenter.complete(.cancelled)
    }

    func testAuthorizationAndSelectionFailuresRemainActionable() {
        let authorizer = RemovalAuthorizerMock()
        authorizer.authorizationResult = false
        authorizer.removalErrorMessage = "模拟授权失败"
        let presenter = RemovalAuthorizationPresenterMock()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            authorizationPresenter: presenter
        )
        let candidate = app(path: "/Applications/Example.app")

        coordinator.requestRemoval(of: candidate)
        presenter.complete(.selected(URL(fileURLWithPath: "/Applications")))
        XCTAssertEqual(coordinator.dialog?.kind, .authorization)
        XCTAssertTrue(coordinator.dialog?.message.contains("模拟授权失败") == true)

        coordinator.beginAuthorizationSelection(for: candidate)
        presenter.complete(.failed(RemovalTestError.selection))
        XCTAssertEqual(coordinator.dialog?.kind, .authorization)
        XCTAssertTrue(coordinator.dialog?.message.contains("模拟选择失败") == true)
        coordinator.cancelAuthorizationSelection()
    }

    func testMissingScopeAtConfirmationReturnsToAuthorizationFailure() {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        authorizer.beginResult = nil
        authorizer.removalErrorMessage = "模拟授权已失效"
        let coordinator = makeCoordinator(authorizer: authorizer)
        let candidate = app(path: "/Applications/Example.app")

        coordinator.requestRemoval(of: candidate)
        coordinator.confirmRemoval(of: candidate)

        XCTAssertEqual(coordinator.dialog?.kind, .authorization)
        XCTAssertTrue(coordinator.dialog?.message.contains("模拟授权已失效") == true)
        XCTAssertNil(coordinator.isRemovingAppID)
    }

    func testConfirmedRemovalBalancesScopeAndReportsCompletion() async {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        let recycler = RecyclerMock()
        let recycled = expectation(description: "recycler returned")
        recycler.onRecycle = { recycled.fulfill() }
        let feedbackPlayer = RemovalFeedbackPlayerMock()
        let completed = expectation(description: "removal callback")
        let candidate = app(path: "/Applications/Example.app")
        let coordinator = ApplicationRemovalCoordinator(
            authorizer: authorizer,
            runningDetector: RunningDetectorMock(isRunning: false),
            recycler: recycler,
            removalFeedbackPlayer: feedbackPlayer,
            successfulRemovalFeedbackDuration: 0.05
        ) { removed in
            XCTAssertEqual(removed, candidate)
            completed.fulfill()
        }

        coordinator.requestRemoval(of: candidate)
        XCTAssertEqual(coordinator.dialog?.kind, .confirmation)
        coordinator.confirmRemoval(of: candidate)
        await fulfillment(of: [recycled], timeout: 1)
        await Task.yield()

        XCTAssertEqual(coordinator.completingAppID, candidate.id)
        XCTAssertEqual(coordinator.isRemovingAppID, candidate.id)
        XCTAssertEqual(feedbackPlayer.playCount, 1)
        XCTAssertEqual(authorizer.endCount, 1)

        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(authorizer.beginCount, 1)
        XCTAssertEqual(authorizer.endCount, 1)
        XCTAssertEqual(recycler.recycledURLs, [URL(fileURLWithPath: candidate.path)])
        XCTAssertNil(coordinator.dialog)
        XCTAssertNil(coordinator.isRemovingAppID)
    }

    func testRecycleFailureBalancesScopeAndDoesNotReportCompletion() async {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        let recycled = expectation(description: "recycler called")
        let recycler = RecyclerMock()
        recycler.error = RemovalTestError.recycle
        recycler.onRecycle = { recycled.fulfill() }
        let feedbackPlayer = RemovalFeedbackPlayerMock()
        var completed = false
        let candidate = app(path: "/Applications/Example.app")
        let coordinator = ApplicationRemovalCoordinator(
            authorizer: authorizer,
            runningDetector: RunningDetectorMock(isRunning: false),
            recycler: recycler,
            removalFeedbackPlayer: feedbackPlayer,
            successfulRemovalFeedbackDuration: 0.01
        ) { _ in
            completed = true
        }

        coordinator.requestRemoval(of: candidate)
        coordinator.confirmRemoval(of: candidate)
        await fulfillment(of: [recycled], timeout: 1)
        await Task.yield()

        XCTAssertFalse(completed)
        XCTAssertEqual(authorizer.endCount, 1)
        XCTAssertEqual(coordinator.dialog?.kind, .failure)
        XCTAssertTrue(coordinator.dialog?.message.contains("原应用没有被") == true)
        XCTAssertNil(coordinator.isRemovingAppID)
        XCTAssertEqual(feedbackPlayer.playCount, 0)
    }

    func testAppManagementDenialOffersOneSettingsRecoveryAndRetriesOnceOnReturn() async {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        let permissionOpener = AppManagementPermissionOpenerMock()
        let recycler = RecyclerMock()
        recycler.error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError
        )
        let firstAttempt = expectation(description: "first recycle attempt")
        let secondAttempt = expectation(description: "automatic retry")
        recycler.onRecycle = {
            if recycler.recycledURLs.count == 1 {
                firstAttempt.fulfill()
            } else if recycler.recycledURLs.count == 2 {
                secondAttempt.fulfill()
            }
        }
        let completed = expectation(description: "removal completed after permission")
        let candidate = app(path: "/Applications/Protected.app")
        let coordinator = ApplicationRemovalCoordinator(
            authorizer: authorizer,
            runningDetector: RunningDetectorMock(isRunning: false),
            recycler: recycler,
            appManagementPermissionOpener: permissionOpener
        ) { removed in
            XCTAssertEqual(removed, candidate)
            completed.fulfill()
        }

        coordinator.requestRemoval(of: candidate)
        coordinator.confirmRemoval(of: candidate)
        await fulfillment(of: [firstAttempt], timeout: 1)
        await Task.yield()

        XCTAssertEqual(coordinator.dialog?.kind, .appManagementPermission)
        XCTAssertTrue(coordinator.dialog?.message.contains("应用管理") == true)
        XCTAssertTrue(coordinator.dialog?.message.contains("只会再尝试一次") == true)
        XCTAssertEqual(authorizer.beginCount, 1)
        XCTAssertEqual(authorizer.endCount, 1)

        coordinator.openAppManagementSettings(for: candidate)
        XCTAssertTrue(coordinator.isAwaitingAppManagementPermission)
        XCTAssertEqual(permissionOpener.openCount, 1)
        coordinator.endManagement(reason: .lifecycle)
        XCTAssertTrue(coordinator.isManagementPresented)

        recycler.error = nil
        coordinator.applicationDidBecomeActive()
        coordinator.applicationDidBecomeActive()
        await fulfillment(of: [secondAttempt, completed], timeout: 1)

        XCTAssertEqual(recycler.recycledURLs.count, 2)
        XCTAssertEqual(authorizer.beginCount, 2)
        XCTAssertEqual(authorizer.endCount, 2)
        XCTAssertFalse(coordinator.isAwaitingAppManagementPermission)
        XCTAssertNil(coordinator.dialog)
    }

    func testFailedPermissionRetryBecomesAStableUnavailableStateWithoutLooping() async {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        let permissionOpener = AppManagementPermissionOpenerMock()
        let recycler = RecyclerMock()
        recycler.error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError
        )
        let firstAttempt = expectation(description: "first recycle attempt")
        let secondAttempt = expectation(description: "single automatic retry")
        recycler.onRecycle = {
            if recycler.recycledURLs.count == 1 {
                firstAttempt.fulfill()
            } else if recycler.recycledURLs.count == 2 {
                secondAttempt.fulfill()
            }
        }
        let candidate = app(path: "/Applications/Protected.app")
        let coordinator = ApplicationRemovalCoordinator(
            authorizer: authorizer,
            runningDetector: RunningDetectorMock(isRunning: false),
            recycler: recycler,
            appManagementPermissionOpener: permissionOpener,
            onRemovalCompleted: { _ in XCTFail("Removal must not complete") }
        )

        coordinator.requestRemoval(of: candidate)
        coordinator.confirmRemoval(of: candidate)
        await fulfillment(of: [firstAttempt], timeout: 1)
        await Task.yield()
        XCTAssertEqual(coordinator.dialog?.kind, .appManagementPermission)

        coordinator.openAppManagementSettings(for: candidate)
        coordinator.applicationDidBecomeActive()
        await fulfillment(of: [secondAttempt], timeout: 1)
        await Task.yield()

        XCTAssertEqual(recycler.recycledURLs.count, 2)
        XCTAssertEqual(coordinator.dialog?.kind, .appManagementUnavailable)
        XCTAssertFalse(coordinator.isAwaitingAppManagementPermission)
        XCTAssertTrue(coordinator.dialog?.message.contains("不会继续要求授权") == true)
        XCTAssertTrue(coordinator.isAppManagementUnavailable(candidate))
        XCTAssertEqual(coordinator.removalCapability(for: candidate), .temporarilyUnavailable)

        coordinator.dismissDialog()
        coordinator.requestRemoval(of: candidate)

        XCTAssertEqual(coordinator.dialog?.kind, .appManagementUnavailable)
        XCTAssertEqual(recycler.recycledURLs.count, 2)
        XCTAssertEqual(permissionOpener.openCount, 1)
    }

    func testAppManagementSettingsOpenFailureReturnsToActionableFailure() async {
        let authorizer = RemovalAuthorizerMock()
        authorizer.isAuthorized = true
        let permissionOpener = AppManagementPermissionOpenerMock()
        permissionOpener.result = false
        let recycler = RecyclerMock()
        recycler.error = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EACCES)
        )
        let attempted = expectation(description: "recycle attempted")
        recycler.onRecycle = { attempted.fulfill() }
        let candidate = app(path: "/Applications/Protected.app")
        let coordinator = ApplicationRemovalCoordinator(
            authorizer: authorizer,
            runningDetector: RunningDetectorMock(isRunning: false),
            recycler: recycler,
            appManagementPermissionOpener: permissionOpener,
            onRemovalCompleted: { _ in XCTFail("Removal must not complete") }
        )

        coordinator.requestRemoval(of: candidate)
        coordinator.confirmRemoval(of: candidate)
        await fulfillment(of: [attempted], timeout: 1)
        await Task.yield()
        XCTAssertEqual(coordinator.dialog?.kind, .appManagementPermission)

        coordinator.openAppManagementSettings(for: candidate)

        XCTAssertEqual(permissionOpener.openCount, 1)
        XCTAssertFalse(coordinator.isAwaitingAppManagementPermission)
        XCTAssertEqual(coordinator.dialog?.kind, .failure)
        XCTAssertEqual(coordinator.dialog?.title, "未能打开“应用管理”设置")
    }

    private func makeCoordinator(
        authorizer: RemovalAuthorizerMock,
        authorizationPresenter: RemovalAuthorizationPresenterMock =
            RemovalAuthorizationPresenterMock(),
        runningDetector: RunningDetectorMock = RunningDetectorMock(isRunning: false),
        managementInactivityTimeout: TimeInterval = 30
    ) -> ApplicationRemovalCoordinator {
        ApplicationRemovalCoordinator(
            authorizer: authorizer,
            authorizationPresenter: authorizationPresenter,
            runningDetector: runningDetector,
            recycler: RecyclerMock(),
            managementInactivityTimeout: managementInactivityTimeout,
            onRemovalCompleted: { _ in }
        )
    }

    private func app(path: String) -> AppInfo {
        AppInfo(
            id: path,
            bundleIdentifier: "com.example.app",
            name: "Example",
            chineseName: "示例",
            path: path,
            purpose: "测试",
            group: .other
        )
    }

    private func assertProtected(
        _ eligibility: ApplicationRemovalEligibility,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .protected = eligibility else {
            XCTFail("Expected protected application", file: file, line: line)
            return
        }
    }

    private func assertProtectedCapability(
        _ capability: ApplicationRemovalCapability,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .protected = capability else {
            XCTFail("Expected protected removal capability", file: file, line: line)
            return
        }
    }
}

@MainActor
private final class RemovalAuthorizationPresenterMock:
    ApplicationRemovalAuthorizationPresenting
{
    private var completion: ((ApplicationRemovalAuthorizationSelection) -> Void)?
    private(set) var presentationCount = 0
    private(set) var cancellationCount = 0

    func selectContainer(
        for _: AppInfo,
        completion: @escaping (ApplicationRemovalAuthorizationSelection) -> Void
    ) {
        presentationCount += 1
        self.completion = completion
    }

    func cancelSelection() {
        cancellationCount += 1
        completion = nil
    }

    func complete(_ result: ApplicationRemovalAuthorizationSelection) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

@MainActor
private final class RemovalAuthorizerMock: ApplicationRemovalAuthorizing {
    var removalErrorMessage: String?
    var isAuthorized = false
    var authorizationResult = true
    var beginResult: URL? = URL(fileURLWithPath: "/Applications")
    var beginCount = 0
    var endCount = 0

    func hasRemovalAuthorization(for applicationURL: URL) -> Bool { isAuthorized }

    func authorizeRemoval(folder: URL, containing applicationURL: URL) -> Bool {
        isAuthorized = authorizationResult
        return authorizationResult
    }

    func beginRemovalAccess(for applicationURL: URL) -> URL? {
        guard isAuthorized else { return nil }
        beginCount += 1
        return beginResult
    }

    func endRemovalAccess(_ folder: URL) {
        endCount += 1
    }

    func reportRemovalSelectionError(_ error: Error) {
        removalErrorMessage = error.localizedDescription
    }
}

@MainActor
private struct RunningDetectorMock: ApplicationRunningDetecting {
    let isRunningValue: Bool

    init(isRunning: Bool) {
        isRunningValue = isRunning
    }

    func isRunning(_ app: AppInfo) -> Bool { isRunningValue }
}

@MainActor
private final class MutableRunningDetectorMock: ApplicationRunningDetecting {
    var isRunningValue = false

    func isRunning(_ app: AppInfo) -> Bool { isRunningValue }
}

@MainActor
private final class RecyclerMock: ApplicationRecycling {
    private(set) var recycledURLs: [URL] = []
    var error: Error?
    var onRecycle: (() -> Void)?

    func recycle(_ applicationURL: URL) async throws -> URL {
        recycledURLs.append(applicationURL)
        onRecycle?()
        if let error { throw error }
        return URL(fileURLWithPath: "/.Trash").appendingPathComponent(applicationURL.lastPathComponent)
    }
}

@MainActor
private final class RemovalFeedbackPlayerMock: ApplicationRemovalFeedbackPlaying {
    private(set) var playCount = 0

    func playSuccessfulRemoval() {
        playCount += 1
    }
}

@MainActor
private final class AppManagementPermissionOpenerMock:
    ApplicationManagementPermissionOpening
{
    var result = true
    private(set) var openCount = 0

    func openAppManagementSettings() -> Bool {
        openCount += 1
        return result
    }
}

private enum RemovalTestError: LocalizedError {
    case selection
    case recycle

    var errorDescription: String? {
        switch self {
        case .selection: return "模拟选择失败"
        case .recycle: return "模拟系统回收失败"
        }
    }
}
