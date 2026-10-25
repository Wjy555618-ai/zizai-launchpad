import AppKit
import SwiftUI

/// Bridges SwiftUI application tiles to the single AppKit tooltip panel.
/// Presentation policy remains owned by `AppTooltipPanelController`; this
/// adapter only mirrors anchor identity and geometry across framework layers.
final class AppTooltipAnchorNSView: NSView {
    var tooltipID = ""
    var tooltipText = ""
    var isTooltipPresented = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard isTooltipPresented else { return }
        let id = tooltipID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isTooltipPresented, self.tooltipID == id else { return }
            AppTooltipPanelController.shared.updatePosition(id: id)
        }
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
