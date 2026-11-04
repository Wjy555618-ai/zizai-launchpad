import AppKit
import SwiftUI

/// Bridges SwiftUI application tiles to the single AppKit tooltip panel.
/// Presentation policy remains owned by `AppTooltipPanelController`; this
/// adapter only mirrors anchor identity and geometry across framework layers.
final class AppTooltipAnchorNSView: NSView {
    var tooltipID = ""
    var tooltipText = ""
    var isTooltipPresented = false {
        didSet {
            guard oldValue != isTooltipPresented else { return }
            trackedScreenFrame = isTooltipPresented ? screenFrame : nil
            // A presentation change does not necessarily coincide with an
            // AppKit geometry pass. Request one explicitly so the anchor's
            // position contract is active from the first visible frame.
            needsLayout = true
        }
    }
    private var trackedScreenFrame: CGRect?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard isTooltipPresented else { return }
        let id = tooltipID
        if let screenFrame {
            if let trackedScreenFrame,
                !screenFrame.isApproximatelyEqual(to: trackedScreenFrame)
            {
                self.trackedScreenFrame = screenFrame
                AppTooltipPanelController.shared.handleAnchorMovement(id: id)
                return
            }
            trackedScreenFrame = screenFrame
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isTooltipPresented, self.tooltipID == id else { return }
            AppTooltipPanelController.shared.updatePosition(id: id)
        }
    }

    private var screenFrame: CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

struct AppTooltipWindowAnchor: NSViewRepresentable {
    let id: String
    let text: String
    let isPresented: Bool

    func makeNSView(context: Context) -> AppTooltipAnchorNSView {
        let view = AppTooltipAnchorNSView(frame: .zero)
        view.wantsLayer = false
        return view
    }

    func updateNSView(_ nsView: AppTooltipAnchorNSView, context: Context) {
        nsView.tooltipID = id
        nsView.tooltipText = text
        nsView.isTooltipPresented = isPresented
        let expectedRevision = AppTooltipPanelController.shared.currentPresentationRevision
        DispatchQueue.main.async {
            guard nsView.tooltipID == id else { return }
            if isPresented {
                AppTooltipPanelController.shared.show(
                    id: id,
                    text: text,
                    anchorView: nsView,
                    expectedRevision: expectedRevision
                )
            } else {
                AppTooltipPanelController.shared.hide(id: id)
            }
        }
    }

    static func dismantleNSView(_ nsView: AppTooltipAnchorNSView, coordinator: ()) {
        nsView.isTooltipPresented = false
        AppTooltipPanelController.shared.hide(id: nsView.tooltipID)
    }
}
