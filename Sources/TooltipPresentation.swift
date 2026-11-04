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

    static let fadeInDuration: TimeInterval = 0.10
    static let fadeOutDuration: TimeInterval = 0.08
    private static let shadowClearance: CGFloat = 16
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AppTooltipPanelContent>?
    private weak var parentWindow: NSWindow?
    private weak var anchorView: NSView?
    private var currentID: String?
    private var presentationRevision: UInt64 = 0
    private var visibilityRevision: UInt64 = 0
    private var movementSuppressedIDs: Set<String> = []
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
        if isEnabled {
            movementSuppressedIDs.removeAll()
        } else {
            dismissAll()
        }
    }

    /// Ends the current page's transient hover context without disabling
    /// tooltips for the destination page. The revision rejects any queued show
    /// request emitted by a persistent but now-hidden page.
    func invalidatePresentationContext() {
        presentationRevision &+= 1
        movementSuppressedIDs.removeAll()
        dismissAll()
    }

    /// A detached tooltip window cannot remain spatially correct while its
    /// SwiftUI content is scrolling or otherwise moving. Invalidate the hover
    /// revision, fade the current panel, and suppress that same hover identity
    /// until the pointer actually leaves its anchor.
    func handleViewportMovement() {
        presentationRevision &+= 1
        if let currentID {
            movementSuppressedIDs.insert(currentID)
        }
        dismissAll()
    }

    func handleAnchorMovement(id: String) {
        presentationRevision &+= 1
        movementSuppressedIDs.insert(id)
        guard currentID == id else { return }
        dismissAll()
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
            if currentID == id { dismissAll() }
            return
        }
        guard !movementSuppressedIDs.contains(id) else { return }

        let previousID = currentID
        currentID = id
        self.anchorView = anchorView
        visibilityRevision &+= 1
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

        if !panel.isVisible || previousID != id {
            panel.alphaValue = 0
        }
        if !panel.isVisible {
            panel.orderFront(nil)
        }
        guard panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
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
        movementSuppressedIDs.remove(id)
        guard currentID == id else { return }
        dismissAll()
    }

    func dismissAll(animated: Bool = true) {
        currentID = nil
        anchorView = nil
        visibilityRevision &+= 1
        let expectedVisibilityRevision = visibilityRevision

        guard let panel, panel.isVisible else {
            detachPanelIfNeeded(panel)
            return
        }

        guard animated else {
            finishDismissal(panel: panel, expectedRevision: expectedVisibilityRevision)
            return
        }

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Self.fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self, weak panel] in
                MainActor.assumeIsolated {
                    guard let self, let panel else { return }
                    self.finishDismissal(
                        panel: panel,
                        expectedRevision: expectedVisibilityRevision
                    )
                }
            }
        )
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

    private func finishDismissal(panel: NSPanel, expectedRevision: UInt64) {
        guard visibilityRevision == expectedRevision, currentID == nil else { return }
        detachPanelIfNeeded(panel)
    }

    private func detachPanelIfNeeded(_ panel: NSPanel?) {
        guard let panel else {
            parentWindow = nil
            return
        }
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.alphaValue = 1
        parentWindow = nil
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
