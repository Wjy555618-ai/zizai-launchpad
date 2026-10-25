import AppKit
import XCTest

@testable import 自在启动台

final class TooltipPresentationTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            AppTooltipPanelController.shared.setPresentationEnabled(true)
            AppTooltipPanelController.shared.dismissAll()
        }
        try await super.tearDown()
    }

    @MainActor
    func testSuspendingPresentationClosesAndBlocksTooltip() {
        let (window, anchor) = makeWindowAndAnchor()
        let controller = AppTooltipPanelController.shared

        controller.show(id: "source", text: "音乐", anchorView: anchor)
        XCTAssertEqual(window.childWindows?.count, 1)

        controller.setPresentationEnabled(false)
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
}
