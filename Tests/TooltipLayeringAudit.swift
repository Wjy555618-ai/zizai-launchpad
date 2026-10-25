import AppKit
import SwiftUI

@main
@MainActor
enum TooltipLayeringAudit {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)

        let window = NSWindow(
            contentRect: CGRect(x: 140, y: 140, width: 900, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content

        let firstAnchor = NSView(frame: CGRect(x: 96, y: 356, width: 72, height: 72))
        let secondAnchor = NSView(frame: CGRect(x: 420, y: 356, width: 72, height: 72))
        content.addSubview(firstAnchor)
        content.addSubview(secondAnchor)
        window.orderBack(nil)

        AppTooltipPanelController.shared.show(
            id: "first",
            text: "网页浏览",
            anchorView: firstAnchor
        )
        settle()

        guard let firstPanel = window.childWindows?.first as? NSPanel else {
            fail("气泡没有以主窗口的顶层子窗口呈现")
        }
        require(firstPanel.isVisible, "气泡子窗口未显示")
        require(firstPanel.styleMask.contains(.nonactivatingPanel), "气泡会错误抢占焦点")
        require(firstPanel.ignoresMouseEvents, "气泡错误拦截了应用交互")
        require(firstPanel.parent === window, "气泡未绑定到所属主窗口")
        require(centered(firstPanel, above: firstAnchor, in: window), "气泡未对齐到所属图标上方")

        AppTooltipPanelController.shared.setPresentationEnabled(false)
        settle()
        require(window.childWindows?.isEmpty != false, "搜索或导航切换后气泡未立即收起")
        require(!firstPanel.isVisible, "禁用气泡展示后子窗口仍可见")

        AppTooltipPanelController.shared.show(
            id: "blocked",
            text: "搜索期间不应出现",
            anchorView: firstAnchor
        )
        settle()
        require(window.childWindows?.isEmpty != false, "搜索期间旧图标重新弹出气泡")

        AppTooltipPanelController.shared.setPresentationEnabled(true)

        AppTooltipPanelController.shared.show(
            id: "second",
            text: "图片与 PDF",
            anchorView: secondAnchor
        )
        AppTooltipPanelController.shared.hide(id: "first")
        settle()

        guard let secondPanel = window.childWindows?.first as? NSPanel else {
            fail("旧图标退出时误关了新图标气泡")
        }
        require(secondPanel.isVisible, "切换图标后气泡消失")
        require(centered(secondPanel, above: secondAnchor, in: window), "切换后气泡仍停留在旧图标")

        AppTooltipPanelController.shared.hide(id: "second")
        settle()
        require(window.childWindows?.isEmpty != false, "离开图标后气泡子窗口没有收起")
        require(!secondPanel.isVisible, "离开图标后气泡仍可见")

        print("气泡层级验收通过：所有应用气泡共享不抢焦点的顶层子窗口，不受标题、卡片、网格、滚动区或画布层级限制。")
    }

    private static func centered(_ panel: NSPanel, above anchor: NSView, in window: NSWindow) -> Bool {
        let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        return abs(panel.frame.midX - anchorRect.midX) < 1
            && panel.frame.maxY > anchorRect.maxY
    }

    private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("气泡层级验收失败：\(message)\n".utf8))
        exit(1)
    }
}
