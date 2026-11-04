import AppKit
import SwiftUI

enum CanvasArrowDirection {
    case left, right, up, down
}

struct CanvasInputCapture: NSViewRepresentable {
    let shouldCapture: () -> Bool
    let onScroll: (CGSize) -> Void
    let onScrollEnd: () -> Void
    let onZoom: (CGFloat, CGPoint) -> Void
    let onZoomEnd: () -> Void
    let onPointerAnchor: (CGPoint) -> Void
    let onArrow: (CanvasArrowDirection) -> Void

    func makeNSView(context: Context) -> CanvasEventView {
        let view = CanvasEventView()
        view.shouldCapture = shouldCapture
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        view.onZoom = onZoom
        view.onZoomEnd = onZoomEnd
        view.onPointerAnchor = onPointerAnchor
        view.onArrow = onArrow
        return view
    }

    func updateNSView(_ view: CanvasEventView, context: Context) {
        view.shouldCapture = shouldCapture
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        view.onZoom = onZoom
        view.onZoomEnd = onZoomEnd
        view.onPointerAnchor = onPointerAnchor
        view.onArrow = onArrow
        view.refreshMonitorsIfNeeded()
    }
}

final class CanvasEventView: NSView {
    var shouldCapture: (() -> Bool)?
    var onScroll: ((CGSize) -> Void)?
    var onScrollEnd: (() -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onZoomEnd: (() -> Void)?
    var onPointerAnchor: ((CGPoint) -> Void)?
    var onArrow: ((CanvasArrowDirection) -> Void)?

    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var pointerMonitor: Any?
    private var keyMonitor: Any?
    private weak var monitoredWindow: NSWindow?
    private var interactionEndWorkItem: DispatchWorkItem?
    private var displayFlushWorkItem: DispatchWorkItem?
    private var pendingScroll: CGSize = .zero
    private var pendingZoom: CGFloat = 0
    private var pendingZoomAnchor: CGPoint?

    private enum PendingInteraction {
        case scroll
        case zoom
    }

    private static let interactionEndQuietPeriod: TimeInterval = 0.09
    private static let fallbackRefreshRate = 60

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshMonitorsIfNeeded()
    }

    func refreshMonitorsIfNeeded() {
        guard monitoredWindow !== window else { return }
        removeMonitors()
        monitoredWindow = window
        guard window != nil else { return }
        monitoredWindow?.acceptsMouseMovedEvents = true

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                self.shouldCapture?() == true,
                event.window === self.monitoredWindow,
                self.monitoredWindow?.isKeyWindow == true,
                let anchor = self.canvasPoint(for: event)
            else { return event }

            if event.modifierFlags.contains(.command) {
                let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
                self.queueZoom(CGFloat(raw) * 0.006, anchor: anchor)
                self.finishIfEventEnded(event, interaction: .zoom)
            } else {
                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
                self.queueScroll(
                    CGSize(
                        width: CGFloat(event.scrollingDeltaX) * multiplier,
                        height: CGFloat(event.scrollingDeltaY) * multiplier
                    ))
                self.finishIfEventEnded(event, interaction: .scroll)
            }
            return nil
        }

        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self,
                self.shouldCapture?() == true,
                event.window === self.monitoredWindow,
                self.monitoredWindow?.isKeyWindow == true,
                let anchor = self.canvasPoint(for: event)
            else { return event }
            self.queueZoom(event.magnification, anchor: anchor)
            self.finishIfEventEnded(event, interaction: .zoom)
            return nil
        }

        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { [weak self] event in
            guard let self,
                self.shouldCapture?() == true,
                event.window === self.monitoredWindow,
                self.monitoredWindow?.isKeyWindow == true,
                let anchor = self.canvasPoint(for: event),
                anchor.y < self.bounds.maxY - 72
            else { return event }
            self.onPointerAnchor?(anchor)
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                self.shouldCapture?() == true,
                event.window === self.monitoredWindow,
                self.monitoredWindow?.isKeyWindow == true
            else { return event }

            if self.monitoredWindow?.firstResponder is NSTextView { return event }
            let direction: CanvasArrowDirection?
            switch event.keyCode {
            case 123: direction = .left
            case 124: direction = .right
            case 125: direction = .down
            case 126: direction = .up
            default: direction = nil
            }
            guard let direction else { return event }
            self.onArrow?(direction)
            return nil
        }
    }

    private func canvasPoint(for event: NSEvent) -> CGPoint? {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return nil }
        return point
    }

    private func queueScroll(_ delta: CGSize) {
        pendingScroll = CGSize(
            width: pendingScroll.width + delta.width,
            height: pendingScroll.height + delta.height
        )
        scheduleDisplayFlush()
        scheduleInteractionEnd(.scroll)
    }

    private func queueZoom(_ delta: CGFloat, anchor: CGPoint) {
        pendingZoom += delta
        pendingZoomAnchor = anchor
        scheduleDisplayFlush()
        scheduleInteractionEnd(.zoom)
    }

    private func scheduleDisplayFlush() {
        guard displayFlushWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingInput()
        }
        displayFlushWorkItem = workItem
        let refreshRate = max(
            1,
            window?.screen?.maximumFramesPerSecond
                ?? NSScreen.main?.maximumFramesPerSecond
                ?? Self.fallbackRefreshRate
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1 / Double(refreshRate),
            execute: workItem
        )
    }

    private func flushPendingInput() {
        displayFlushWorkItem = nil
        guard shouldCapture?() == true else {
            clearPendingInput()
            return
        }
        let scroll = pendingScroll
        let zoom = pendingZoom
        let anchor = pendingZoomAnchor
        clearPendingInput()
        if abs(scroll.width) > 0.001 || abs(scroll.height) > 0.001 {
            onScroll?(scroll)
        }
        if abs(zoom) > 0.000_001, let anchor {
            onZoom?(zoom, anchor)
        }
    }

    private func clearPendingInput() {
        pendingScroll = .zero
        pendingZoom = 0
        pendingZoomAnchor = nil
    }

    private func scheduleInteractionEnd(_ interaction: PendingInteraction) {
        interactionEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishInteraction(interaction)
        }
        interactionEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.interactionEndQuietPeriod,
            execute: workItem
        )
    }

    private func finishIfEventEnded(_ event: NSEvent, interaction: PendingInteraction) {
        guard event.phase == .ended || event.phase == .cancelled else { return }
        finishInteraction(interaction)
    }

    private func finishInteraction(_ interaction: PendingInteraction) {
        interactionEndWorkItem?.cancel()
        interactionEndWorkItem = nil
        displayFlushWorkItem?.cancel()
        displayFlushWorkItem = nil
        flushPendingInput()
        switch interaction {
        case .scroll: onScrollEnd?()
        case .zoom: onZoomEnd?()
        }
    }

    private func removeMonitors() {
        interactionEndWorkItem?.cancel()
        interactionEndWorkItem = nil
        displayFlushWorkItem?.cancel()
        displayFlushWorkItem = nil
        clearPendingInput()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        scrollMonitor = nil
        magnifyMonitor = nil
        pointerMonitor = nil
        keyMonitor = nil
    }

    deinit {
        MainActor.assumeIsolated {
            removeMonitors()
        }
    }
}
