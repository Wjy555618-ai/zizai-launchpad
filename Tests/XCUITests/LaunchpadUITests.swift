@preconcurrency import XCTest

final class LaunchpadUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionID = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryNavigationAndHelpDismissal() {
        launchApplication()
        let groups = element("navigation.groups")
        let space = element("navigation.space")
        let allApps = element("navigation.all-apps")

        assertCurrentScreen(navigation: groups, screen: element("screen.groups"))

        navigate(to: space, screen: element("screen.space"))

        navigate(to: allApps, screen: element("screen.all-apps"))

        navigate(to: groups, screen: element("screen.groups"))

        element("help.open").click()
        let help = element("help.heading")
        XCTAssertTrue(help.waitForExistence(timeout: 3))

        app.buttons["查看完整隐私政策"].click()
        let privacyDate = app.staticTexts["更新日期：2026 年 11 月 2 日"]
        XCTAssertTrue(privacyDate.waitForExistence(timeout: 3))
        element("privacy-policy.done").click()
        XCTAssertTrue(privacyDate.waitForNonExistence(timeout: 3))

        clickParentWindowOutsidePresentedSheet()
        XCTAssertTrue(help.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testSearchReturnsEveryInstanceWithoutContentStealingResultInteraction() {
        launchApplication()
        openSearch()
        let searchField = element("search.field")
        typeLatinText("fig", into: searchField)
        assertValue("fig", for: searchField)

        XCTAssertTrue(element("search.results.heading").waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Figma")).count,
            2
        )

        app.staticTexts["搜索结果"].click()
        XCTAssertTrue(searchField.exists)
        XCTAssertTrue(element("search.results.heading").exists)
        element("brand.capsule").click()
        assertSearchIsClosed()
    }

    @MainActor
    func testSearchResultSingleAndDoubleClickReachApplicationLaunchAction() {
        launchApplication(applicationCount: 8)
        openSearch()
        let searchField = element("search.field")
        typeLatinText("test application 8", into: searchField)
        assertValue("test application 8", for: searchField)

        let appID =
            "local.wangzhentao.ZizaiLaunchpadUITest.7::/Applications/ZizaiLaunchpadUITest-7.app"
        let result = element("app.tile.\(appID)")
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        app.activate()
        assertHittable(result, timeout: 3)

        // The synthetic app intentionally does not exist. Seeing the launch
        // failure is end-to-end proof that the pointer reached the result tile
        // and invoked the same launch action used by production applications.
        result.click()
        let launchFailure = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "无法打开“测试应用 8”")
        ).firstMatch
        XCTAssertTrue(launchFailure.waitForExistence(timeout: 3))
        XCTAssertTrue(searchField.exists)

        result.doubleClick()
        XCTAssertTrue(launchFailure.waitForExistence(timeout: 3))
        XCTAssertTrue(searchField.exists)
    }

    @MainActor
    func testSearchDismissesFromBrandCapsule() {
        launchApplication()
        openSearch()
        let brandButton = app.buttons["brand.capsule"]
        XCTAssertTrue(brandButton.waitForExistence(timeout: 3))
        XCTAssertTrue(brandButton.isHittable)
        brandButton.click()
        assertSearchIsClosed()
    }

    @MainActor
    func testGroupReorderAndUndo() {
        launchApplication()
        let group = element("group.card.ai-creative")
        XCTAssertTrue(group.waitForExistence(timeout: 3))
        let initialY = group.frame.midY

        element("group.menu.ai-creative").click()
        app.menuItems["向下移动"].click()
        assertFrameY(of: group, isGreaterThan: initialY)

        let undo = element("toast.undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        assertFrameY(of: group, equals: initialY)
    }

    @MainActor
    func testPointerDragReordersGroupsAndUndoRestoresOrder() {
        launchApplication()
        let sourceGroup = element("group.card.ai-creative")
        let sourceHandle = element("group.drag-handle.ai-creative")
        let destinationHandle = element("group.drag-handle.communication")
        XCTAssertTrue(sourceHandle.waitForExistence(timeout: 3))
        XCTAssertTrue(destinationHandle.waitForExistence(timeout: 3))
        let initialY = sourceGroup.frame.midY

        sourceHandle.press(forDuration: 0.15, thenDragTo: destinationHandle)
        assertFrameY(of: sourceGroup, isGreaterThan: initialY)

        let undo = element("toast.undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        assertFrameY(of: sourceGroup, equals: initialY)
    }

    @MainActor
    func testCrossGroupMoveAndUndo() {
        launchApplication()
        let source = element("app.tile.com.tencent.xinWeChat::/Applications/WeChat.app")
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        assertValuePrefix("当前分组：沟通协作", for: source)

        source.rightClick()
        app.menuItems["移到分组"].click()
        app.menuItems["AI 与创作"].click()
        assertValuePrefix("当前分组：AI 与创作", for: source)

        let undo = element("toast.undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        assertValuePrefix("当前分组：沟通协作", for: source)
    }

    @MainActor
    func testPointerDragMovesApplicationAcrossGroupsAndUndoRestoresIt() {
        launchApplication()
        let source = element("app.tile.com.tencent.xinWeChat::/Applications/WeChat.app")
        let destination = element("app.tile.com.figma.Desktop::/Applications/Figma.app")
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        assertValuePrefix("当前分组：沟通协作", for: source)

        source.press(forDuration: 0.15, thenDragTo: destination)
        // The page identifier is intentionally inherited by its rendered
        // accessibility descendants after a drag. Query the semantic scroll
        // container directly so the diagnostic value remains unambiguous.
        let diagnostic = app.scrollViews["screen.groups"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 3))
        XCTAssertTrue(
            String(describing: diagnostic.value ?? "")
                .contains("destination=ai-creative:")
        )
        assertValuePrefix("当前分组：AI 与创作", for: source)

        let undo = element("toast.undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        assertValuePrefix("当前分组：沟通协作", for: source)
    }

    @MainActor
    func testPointerDragMovesApplicationInSpaceAndUndoRestoresPosition() {
        launchApplication()
        navigate(to: element("navigation.space"), screen: element("screen.space"))

        let source = element("app.tile.com.figma.Desktop::/Applications/Figma.app")
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        let initialFrame = source.frame
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = start.withOffset(CGVector(dx: 110, dy: 70))

        start.press(forDuration: 0.15, thenDragTo: destination)
        assertFrame(of: source, changesFrom: initialFrame)

        let undo = element("toast.undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        assertFrame(of: source, returnsTo: initialFrame)
    }

    @MainActor
    func testAllAppsVisibilityChangeAndUndo() {
        launchApplication()
        navigate(to: element("navigation.all-apps"), screen: element("screen.all-apps"))

        let preview = element("app.tile.com.apple.Preview::/System/Applications/Preview.app")
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        assertValuePrefix("正在显示", for: preview)

        preview.rightClick()
        app.menuItems["从空间和分组中隐藏"].click()
        assertValuePrefix("已隐藏", for: preview)

        let undo = element("toast.undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        assertValuePrefix("正在显示", for: preview)
    }

    @MainActor
    func testApplicationManagementAuthorizesApplicationsOnceAndReusesGrant() {
        // The defect reproduced only at production catalog density: continuous
        // per-tile animation saturated the main thread while a modal alert was
        // present. Seven fixture apps allowed the same broken architecture to
        // pass. Keep this journey dense, use normal pointer clicks, and prove
        // the complete first-use contract: no explanatory detour, no app hunt,
        // one system grant, then reuse that grant for a second application.
        launchApplication(applicationCount: 96)
        // Use the first visible synthetic fixture rather than any real process.
        // Its visibility and running state are deterministic at dense scale.
        let managedAppID =
            "local.wangzhentao.ZizaiLaunchpadUITest.7::/Applications/ZizaiLaunchpadUITest-7.app"
        let managedApp = element("app.tile.\(managedAppID)")
        XCTAssertTrue(managedApp.waitForExistence(timeout: 3))

        managedApp.press(forDuration: 0.7)
        let done = element("application-management.done")
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        let removal = element("application-removal.\(managedAppID)")
        XCTAssertTrue(removal.waitForExistence(timeout: 3))
        removal.click()

        let obsoleteExplanation = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "重新授权“应用程序”")
        ).firstMatch
        XCTAssertFalse(obsoleteExplanation.exists)
        let panelMessage = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "无需查找、选择或打开")
        ).firstMatch
        XCTAssertTrue(panelMessage.waitForExistence(timeout: 3))

        let location = app.popUpButtons["where popup"]
        XCTAssertTrue(location.waitForExistence(timeout: 3))
        let applicationsLocation = NSPredicate(
            format: "value CONTAINS %@ OR value CONTAINS %@",
            "应用程序",
            "Applications"
        )
        let locationExpectation = XCTNSPredicateExpectation(
            predicate: applicationsLocation,
            object: location
        )
        XCTAssertEqual(XCTWaiter.wait(for: [locationExpectation], timeout: 3), .completed)

        // Cancellation must fully release the sheet state so a retry remains
        // responsive in the same dense management session.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panelMessage.waitForNonExistence(timeout: 3))
        // Powerbox is a separate system process. Re-activate the target after
        // its sheet closes so XCUI refreshes the foreground accessibility
        // session instead of querying the now-stale modal session.
        app.activate()
        // Escape is also an outside-management gesture, so re-enter the same
        // way a person does instead of assuming edit mode remains latched.
        let resumedManagedApp = element("app.tile.\(managedAppID)")
        XCTAssertTrue(resumedManagedApp.waitForExistence(timeout: 3))
        resumedManagedApp.press(forDuration: 0.7)
        let resumedDone = element("application-management.done")
        XCTAssertTrue(resumedDone.waitForExistence(timeout: 3))
        let resumedRemoval = element("application-removal.\(managedAppID)")
        assertHittable(resumedRemoval, timeout: 3)
        resumedRemoval.click()
        XCTAssertTrue(panelMessage.waitForExistence(timeout: 3))

        // This is the only authorization click in the successful first-use
        // journey. No folder or application item is selected beforehand.
        let authorizeApplications = app.buttons["OKButton"]
        assertHittable(authorizeApplications, timeout: 3)
        authorizeApplications.click()

        let firstConfirmation = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "将“测试应用 8”移到废纸篓？")
        ).firstMatch
        XCTAssertTrue(firstConfirmation.waitForExistence(timeout: 3))
        assertHittable(app.buttons["action-button-2"], timeout: 3)
        app.buttons["action-button-2"].click()
        XCTAssertTrue(firstConfirmation.waitForNonExistence(timeout: 3))

        // A second app under /Applications must go directly to its destructive
        // confirmation. Seeing the open panel here would mean the shared grant
        // was not persisted or not reused.
        let secondAppID =
            "local.wangzhentao.ZizaiLaunchpadUITest.9::/Applications/ZizaiLaunchpadUITest-9.app"
        let secondRemoval = element("application-removal.\(secondAppID)")
        assertHittable(secondRemoval, timeout: 3)
        secondRemoval.click()
        let secondConfirmation = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "将“测试应用 10”移到废纸篓？")
        ).firstMatch
        XCTAssertTrue(secondConfirmation.waitForExistence(timeout: 3))
        XCTAssertFalse(panelMessage.exists)
        assertHittable(app.buttons["action-button-2"], timeout: 3)
        app.buttons["action-button-2"].click()
        XCTAssertTrue(secondConfirmation.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testApplicationRemovalMovesDedicatedFixtureIntoTrashAfterOneGrant() {
        let fileManager = FileManager.default
        let fixtureURL = URL(
            fileURLWithPath: "/Applications/ZizaiLaunchpadUITest-7.app",
            isDirectory: true
        )
        let markerURL = fixtureURL.appendingPathComponent("ZizaiLaunchpadRemovalMarker")
        XCTAssertTrue(
            fileManager.fileExists(atPath: markerURL.path),
            "外层 UI 验收脚本未准备带标记的专用回收测试 App。"
        )

        launchApplication(applicationCount: 8)
        let appID =
            "local.wangzhentao.ZizaiLaunchpadUITest.7::/Applications/ZizaiLaunchpadUITest-7.app"
        let managedApp = element("app.tile.\(appID)")
        XCTAssertTrue(managedApp.waitForExistence(timeout: 3))
        managedApp.press(forDuration: 0.7)

        let removal = element("application-removal.\(appID)")
        assertHittable(removal, timeout: 3)
        removal.click()

        let panelMessage = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "无需查找、选择或打开")
        ).firstMatch
        XCTAssertTrue(panelMessage.waitForExistence(timeout: 3))
        let authorizeApplications = app.buttons["OKButton"]
        assertHittable(authorizeApplications, timeout: 3)
        authorizeApplications.click()

        let confirmation = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "将“测试应用 8”移到废纸篓？")
        ).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        let moveToTrash = app.buttons["action-button-1"]
        assertHittable(moveToTrash, timeout: 3)
        moveToTrash.click()

        let sourceDisappeared = NSPredicate { _, _ in
            !fileManager.fileExists(atPath: fixtureURL.path)
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: sourceDisappeared, object: nil)],
                timeout: 5
            ),
            .completed
        )
        let success = app.descendants(matching: .any).matching(
            NSPredicate(format: "value CONTAINS %@", "已将“测试应用 8”移到废纸篓")
        ).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 3))
    }

    @MainActor
    func testApplicationManagementProtectsSystemApps() {
        launchApplication()
        navigate(to: element("navigation.all-apps"), screen: element("screen.all-apps"))
        let previewID = "com.apple.Preview::/System/Applications/Preview.app"
        let preview = element("app.tile.\(previewID)")
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.press(forDuration: 0.7)
        XCTAssertTrue(element("application-management.done").waitForExistence(timeout: 3))
        let protectedRemoval = element("application-removal.\(previewID)")
        XCTAssertFalse(protectedRemoval.exists)

        // Page changes are a public management-exit contract and use a stable,
        // non-animated hit target in XCUITest. The Done button itself is
        // verified through its accessibility action in the visual QA pass.
        navigate(to: element("navigation.groups"), screen: element("screen.groups"))
        navigate(to: element("navigation.all-apps"), screen: element("screen.all-apps"))
        let stationaryPreview = element("app.tile.\(previewID)")
        XCTAssertTrue(stationaryPreview.waitForExistence(timeout: 3))
        stationaryPreview.rightClick()
        app.menuItems["了解为什么无法移除"].click()
        let protectionText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "无法移除“预览”")
        ).firstMatch
        XCTAssertTrue(protectionText.waitForExistence(timeout: 3))
    }

    @MainActor
    func testApplicationManagementStartsStillAndOutsideClickRestoresStillState() {
        launchApplication()
        let managedAppID =
            "com.figma.Desktop::/Applications/ZizaiLaunchpadUITest-FigmaCopy.app"
        let managedApp = element("app.tile.\(managedAppID)")
        let removal = element("application-removal.\(managedAppID)")
        let done = element("application-management.done")
        XCTAssertTrue(managedApp.waitForExistence(timeout: 3))
        XCTAssertFalse(done.exists)
        XCTAssertFalse(removal.exists)
        assertFrameRemainsStable(for: managedApp, duration: 0.35)

        managedApp.press(forDuration: 0.7)
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        assertHittable(removal, timeout: 3)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.18)).click()
        XCTAssertTrue(done.waitForNonExistence(timeout: 3))
        XCTAssertTrue(removal.waitForNonExistence(timeout: 3))
        assertFrameRemainsStable(for: managedApp, duration: 0.35)
    }

    @MainActor
    func testApplicationManagementAutomaticallyEndsAfterInactivity() {
        launchApplication(managementTimeout: 2.5)
        let managedAppID =
            "com.figma.Desktop::/Applications/ZizaiLaunchpadUITest-FigmaCopy.app"
        let managedApp = element("app.tile.\(managedAppID)")
        XCTAssertTrue(managedApp.waitForExistence(timeout: 3))

        managedApp.press(forDuration: 0.7)
        let done = element("application-management.done")
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        assertFrameRemainsStable(for: managedApp, duration: 0.35)
    }

    @MainActor
    func testCatalogFilterIsGloballyDiscoverableAndNavigatesToAllApps() {
        launchApplication()
        let options = element("app-catalog.options")
        XCTAssertTrue(options.waitForExistence(timeout: 3))
        XCTAssertTrue(options.isHittable)

        options.click()
        let hiddenFilter = element("app-catalog.filter.hidden")
        XCTAssertTrue(hiddenFilter.waitForExistence(timeout: 3))
        hiddenFilter.click()

        assertCurrentScreen(
            navigation: element("navigation.all-apps"),
            screen: element("screen.all-apps")
        )
    }

    @MainActor
    func testCanvasZoomControlsExposeAndChangeState() {
        launchApplication()
        navigate(to: element("navigation.space"), screen: element("screen.space"))

        let zoomValue = element("canvas.zoom-value")
        XCTAssertTrue(zoomValue.waitForExistence(timeout: 3))
        let initialValue = String(describing: zoomValue.value ?? "")

        element("canvas.zoom-in").click()
        assertValueChanges(from: initialValue, for: zoomValue)

        element("canvas.fit").click()
        XCTAssertTrue(element("canvas.zoom-out").isHittable)
    }

    @MainActor
    func testGroupEditorOutsideDismissalAndPersistenceAcrossRelaunch() {
        launchApplication()
        element("group.new").click()
        let editor = element("group-editor.heading")
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        clickParentWindowOutsidePresentedSheet()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 3))

        element("group.new").click()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let nameField = element("group-editor.name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("持久化测试")
        app.buttons["创建"].click()
        let createdGroup = app.groups.matching(
            NSPredicate(format: "label BEGINSWITH %@", "持久化测试")
        ).firstMatch
        XCTAssertTrue(createdGroup.waitForExistence(timeout: 3))

        app.terminate()
        configureLaunch(resetState: false)
        app.launch()
        app.activate()
        waitForApplicationReadiness()
        XCTAssertTrue(createdGroup.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApplication(
        managementTimeout: TimeInterval? = nil,
        applicationCount: Int? = nil
    ) {
        sessionID = "\(name)-\(UUID().uuidString)"
        app = XCUIApplication()
        configureLaunch(resetState: true)
        if let managementTimeout {
            app.launchEnvironment["ZIZAI_UI_TEST_MANAGEMENT_TIMEOUT"] = String(managementTimeout)
        } else {
            app.launchEnvironment.removeValue(forKey: "ZIZAI_UI_TEST_MANAGEMENT_TIMEOUT")
        }
        if let applicationCount {
            app.launchEnvironment["ZIZAI_UI_TEST_APPLICATION_COUNT"] = String(applicationCount)
        } else {
            app.launchEnvironment.removeValue(forKey: "ZIZAI_UI_TEST_APPLICATION_COUNT")
        }
        app.launch()
        // A system permission or settings window can remain open from a prior
        // manual session. Make foreground ownership part of the shared launch
        // contract instead of weakening individual hittability assertions.
        app.activate()
        waitForApplicationReadiness()
    }

    @MainActor
    private func configureLaunch(resetState: Bool) {
        app.launchEnvironment["ZIZAI_UI_TESTING"] = "1"
        app.launchEnvironment["ZIZAI_UI_TEST_SESSION"] = sessionID
        app.launchEnvironment["ZIZAI_UI_TEST_RESET"] = resetState ? "1" : "0"
    }

    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Launch exposes the native accessibility tree before the one-time page
    /// prewarm has finished. Readiness therefore means the initial page is
    /// present and its navigation control is actually interactive, not merely
    /// that a top-chrome element has been registered.
    @MainActor
    private func waitForApplicationReadiness() {
        let groups = element("navigation.groups")
        XCTAssertTrue(groups.waitForExistence(timeout: 10))
        assertHittable(groups, timeout: 10)
        assertCurrentScreen(navigation: groups, screen: element("screen.groups"))
    }

    /// A navigation transition is complete only when both public contracts
    /// agree: the selected tab exposes its state and the destination page is
    /// present in the accessibility tree. This avoids coordinate- or timing-
    /// based assumptions while still detecting stale selection semantics.
    @MainActor
    private func navigate(to navigation: XCUIElement, screen: XCUIElement) {
        assertHittable(navigation, timeout: 3)
        navigation.click()
        assertCurrentScreen(navigation: navigation, screen: screen)
    }

    @MainActor
    private func assertCurrentScreen(navigation: XCUIElement, screen: XCUIElement) {
        XCTAssertTrue(screen.waitForExistence(timeout: 3))
        assertValue("selected", for: navigation)
        for identifier in ["screen.groups", "screen.space", "screen.all-apps"]
        where identifier != screen.identifier {
            XCTAssertFalse(
                element(identifier).exists,
                "非当前页面仍暴露在辅助功能树中：\(identifier)"
            )
        }
    }

    @MainActor
    private func assertHittable(_ element: XCUIElement, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    @MainActor
    private func openSearch() {
        element("search.open").click()
        let searchField = element("search.field")
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertTrue(searchField.isHittable)
        XCTAssertFalse(app.buttons["收起搜索"].exists)
    }

    @MainActor
    private func assertSearchIsClosed() {
        XCTAssertTrue(element("search.field").waitForNonExistence(timeout: 3))
        XCTAssertTrue(element("search.open").waitForExistence(timeout: 3))
    }

    @MainActor
    private func clickParentWindowOutsidePresentedSheet() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.72)).click()
    }

    @MainActor
    private func typeLatinText(_ text: String, into element: XCUIElement) {
        element.click()
        // Search is case-insensitive, so enter lowercase text as one logical
        // operation. Pressing Shift for every character is not locale-neutral
        // on macOS: for several Chinese input methods Shift switches the input
        // source and presents the system InputSource HUD over the text field.
        element.typeText(text.lowercased())
    }

    @MainActor
    private func assertValue(_ expected: String, for element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    @MainActor
    private func assertValuePrefix(_ expectedPrefix: String, for element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let predicate = NSPredicate(format: "value BEGINSWITH %@", expectedPrefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    @MainActor
    private func assertValueChanges(from initialValue: String, for element: XCUIElement) {
        let predicate = NSPredicate(format: "value != %@", initialValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    @MainActor
    private func assertFrameY(of element: XCUIElement, isGreaterThan initialY: CGFloat) {
        let predicate = NSPredicate { evaluated, _ in
            guard let evaluated = evaluated as? XCUIElement else { return false }
            return evaluated.frame.midY > initialY + 20
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    @MainActor
    private func assertFrameY(of element: XCUIElement, equals expectedY: CGFloat) {
        let predicate = NSPredicate { evaluated, _ in
            guard let evaluated = evaluated as? XCUIElement else { return false }
            return abs(evaluated.frame.midY - expectedY) < 2
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    @MainActor
    private func assertFrame(of element: XCUIElement, changesFrom initialFrame: CGRect) {
        let predicate = NSPredicate { evaluated, _ in
            guard let evaluated = evaluated as? XCUIElement else { return false }
            let frame = evaluated.frame
            return abs(frame.midX - initialFrame.midX) > 20
                || abs(frame.midY - initialFrame.midY) > 20
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed)
    }

    @MainActor
    private func assertFrame(of element: XCUIElement, returnsTo expectedFrame: CGRect) {
        let predicate = NSPredicate { evaluated, _ in
            guard let evaluated = evaluated as? XCUIElement else { return false }
            let frame = evaluated.frame
            return abs(frame.midX - expectedFrame.midX) < 3
                && abs(frame.midY - expectedFrame.midY) < 3
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed)
    }

    @MainActor
    private func assertFrameRemainsStable(
        for element: XCUIElement,
        duration: TimeInterval,
        tolerance: CGFloat = 0.5
    ) {
        // Let the accessibility snapshot catch up with the visual hierarchy.
        // Let the finite management-mode transition settle before comparing frames.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let initialFrame = element.frame
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
        let finalFrame = element.frame
        XCTAssertLessThanOrEqual(abs(finalFrame.minX - initialFrame.minX), tolerance)
        XCTAssertLessThanOrEqual(abs(finalFrame.minY - initialFrame.minY), tolerance)
        XCTAssertLessThanOrEqual(abs(finalFrame.width - initialFrame.width), tolerance)
        XCTAssertLessThanOrEqual(abs(finalFrame.height - initialFrame.height), tolerance)
    }
}
