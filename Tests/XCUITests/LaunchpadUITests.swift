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

        clickParentWindowOutsidePresentedSheet()
        XCTAssertTrue(help.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testSearchReturnsEveryInstanceAndDismissesFromContent() {
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
        assertSearchIsClosed()
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
        let diagnostic = element("screen.groups")
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
        waitForApplicationReadiness()
        XCTAssertTrue(createdGroup.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApplication() {
        sessionID = "\(name)-\(UUID().uuidString)"
        app = XCUIApplication()
        configureLaunch(resetState: true)
        app.launch()
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
}
