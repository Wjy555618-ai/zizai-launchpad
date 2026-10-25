import AppKit
import SwiftUI

/// Owns the single application-tooltip window and its presentation lifecycle.
///
/// Tooltips live in a child panel so they can appear above every launcher
/// surface without being clipped. Because that panel is outside SwiftUI's
/// normal view hierarchy, navigation must explicitly suspend it while the
/// owning content is unavailable (for example, while search is presented).
@MainActor
final class AppTooltipPanelController {
    static let shared = AppTooltipPanelController()

    private static let shadowClearance: CGFloat = 16
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AppTooltipPanelContent>?
    private weak var parentWindow: NSWindow?
    private weak var anchorView: NSView?
    private var currentID: String?
    private var presentationRevision: UInt64 = 0
    private(set) var isPresentationEnabled = true

    var currentPresentationRevision: UInt64 { presentationRevision }

    /// Suspends or resumes all tooltip presentation as one product-level
    /// boundary. Advancing the revision also invalidates queued show requests
    /// that were created before a navigation or search transition.
    func setPresentationEnabled(_ isEnabled: Bool) {
        guard isPresentationEnabled != isEnabled else {
            if !isEnabled { dismissAll() }
            return
        }
        isPresentationEnabled = isEnabled
        presentationRevision &+= 1
        if !isEnabled { dismissAll() }
    }

    func show(id: String, text: String, anchorView: NSView) {
        show(
            id: id,
            text: text,
            anchorView: anchorView,
            expectedRevision: presentationRevision
        )
    }

    func show(
        id: String,
        text: String,
        anchorView: NSView,
        expectedRevision: UInt64
    ) {
        guard isPresentationEnabled,
            expectedRevision == presentationRevision,
            !text.isEmpty,
            let window = anchorView.window
        else {
            hide(id: id)
            return
        }

        currentID = id
        self.anchorView = anchorView
        let content = AppTooltipPanelContent(
            text: text,
            iconSize: max(1, anchorView.bounds.height),
            clearance: Self.shadowClearance
        )

        let hostingView: NSHostingView<AppTooltipPanelContent>
        if let existing = self.hostingView {
            hostingView = existing
            hostingView.rootView = content
        } else {
            hostingView = NSHostingView(rootView: content)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            self.hostingView = hostingView
        }

        let panel = tooltipPanel(hostingView: hostingView)
        panel.appearance = window.effectiveAppearance
        attach(panel, to: window)
        updatePosition(id: id)

        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func updatePosition(id: String) {
        guard isPresentationEnabled,
            currentID == id,
            let panel,
            let hostingView,
            let anchorView,
            let window = anchorView.window
        else { return }

        let anchorInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorOnScreen = window.convertToScreen(anchorInWindow)
        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        hostingView.frame = CGRect(origin: .zero, size: fittingSize)
        panel.setFrame(
            CGRect(
                x: anchorOnScreen.midX - fittingSize.width / 2,
                y: anchorOnScreen.minY - Self.shadowClearance,
                width: fittingSize.width,
                height: fittingSize.height
            ),
            display: false
        )
    }

    func hide(id: String) {
        guard currentID == id else { return }
        dismissAll()
    }

    func dismissAll() {
        currentID = nil
        anchorView = nil
        if let panel {
            parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
        parentWindow = nil
    }

    private func tooltipPanel(
        hostingView: NSHostingView<AppTooltipPanelContent>
    ) -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    private func attach(_ panel: NSPanel, to window: NSWindow) {
        guard parentWindow !== window else { return }
        parentWindow?.removeChildWindow(panel)
        parentWindow = window
        window.addChildWindow(panel, ordered: .above)
    }
}

private struct AppTooltipPanelContent: View {
    let text: String
    let iconSize: CGFloat
    let clearance: CGFloat

    var body: some View {
        AppTooltipAboveIcon(text: text, iconSize: iconSize)
            .padding(clearance)
            .fixedSize()
    }
}

/// Anchors the tooltip by geometry instead of a fragile alignment-guide
/// offset. The transparent icon-sized spacer makes the bubble's tail end at a
/// fixed clear gap above the artwork for every icon size and canvas zoom.
struct AppTooltipAboveIcon: View {
    let text: String
    let iconSize: CGFloat

    var body: some View {
        VStack(spacing: ZizaiLayout.appTooltipTargetGap) {
            DockStyleTooltip(text: text)
            Color.clear
                .frame(width: 1, height: iconSize)
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
