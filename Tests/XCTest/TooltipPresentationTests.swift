import AppKit
import XCTest

@testable import 自在启动台

final class TooltipPresentationTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            AppTooltipPanelController.shared.setPresentationEnabled(true)
            AppTooltipPanelController.shared.dismissAll(animated: false)
        }
        try await super.tearDown()
    }

    @MainActor
    func testSuspendingPresentationClosesAndBlocksTooltip() async {
        let (window, anchor) = makeWindowAndAnchor()
        let controller = AppTooltipPanelController.shared

        controller.show(id: "source", text: "音乐", anchorView: anchor)
        XCTAssertEqual(window.childWindows?.count, 1)

        controller.setPresentationEnabled(false)
        await settleTooltipFade()
        XCTAssertNotEqual(window.childWindows?.isEmpty, false)

        controller.show(id: "stale-source", text: "不应重现", anchorView: anchor)
        XCTAssertNotEqual(window.childWindows?.isEmpty, false)
    }

    @MainActor
    func testNavigationRevisionRejectsQueuedPresentationFromPreviousContext() {
        let (window, anchor) = makeWindowAndAnchor()
        let controller = AppTooltipPanelController.shared
        let staleRevision = controller.currentPresentationRevision

        controller.setPresentationEnabled(false)
        controller.setPresentationEnabled(true)
        controller.show(
            id: "stale",
            text: "旧视图气泡",
            anchorView: anchor,
            expectedRevision: staleRevision
        )
        XCTAssertNotEqual(window.childWindows?.isEmpty, false)

        controller.show(id: "current", text: "当前视图气泡", anchorView: anchor)
        XCTAssertEqual(window.childWindows?.count, 1)
    }

    @MainActor
    func testChangingPersistentPageInvalidatesVisibleAndQueuedTooltip() async {
        let (window, anchor) = makeWindowAndAnchor()
        let controller = AppTooltipPanelController.shared

        controller.show(id: "old-page", text: "旧页面气泡", anchorView: anchor)
        XCTAssertEqual(window.childWindows?.count, 1)
        let staleRevision = controller.currentPresentationRevision

        controller.invalidatePresentationContext()
        await settleTooltipFade()
        XCTAssertNotEqual(window.childWindows?.isEmpty, false)

        controller.show(
            id: "queued-old-page",
            text: "不应出现在新页面",
            anchorView: anchor,
            expectedRevision: staleRevision
        )
        XCTAssertNotEqual(window.childWindows?.isEmpty, false)
    }

    @MainActor
    func testViewportMovementFadesAndSuppressesTooltipUntilPointerLeaves() async {
        let (window, anchor) = makeWindowAndAnchor()
        let controller = AppTooltipPanelController.shared

        controller.show(id: "moving", text: "AI 助手", anchorView: anchor)
        guard let panel = window.childWindows?.first else {
            return XCTFail("气泡没有显示")
        }

        controller.handleViewportMovement()
        XCTAssertTrue(panel.isVisible, "滚动开始时气泡被硬切，没有执行渐隐")
        await settleTooltipFade()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNotEqual(window.childWindows?.isEmpty, false)

        controller.show(id: "moving", text: "不应在滚动后复活", anchorView: anchor)
        XCTAssertNotEqual(window.childWindows?.isEmpty, false)

        controller.hide(id: "moving")
        controller.show(id: "moving", text: "重新移入后出现", anchorView: anchor)
        XCTAssertEqual(window.childWindows?.count, 1)
    }

    @MainActor
    private func makeWindowAndAnchor() -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: CGRect(x: 120, y: 120, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: window.contentLayoutRect)
        let anchor = NSView(frame: CGRect(x: 180, y: 220, width: 72, height: 72))
        content.addSubview(anchor)
        window.contentView = content
        window.orderBack(nil)
        return (window, anchor)
    }

    @MainActor
    private func settleTooltipFade() async {
        try? await Task.sleep(
            nanoseconds: UInt64(
                (AppTooltipPanelController.fadeOutDuration + 0.04) * 1_000_000_000
            )
        )
    }
}
