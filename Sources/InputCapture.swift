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
    let onPointerAnchor: (CGPoint) -> Void
    let onArrow: (CanvasArrowDirection) -> Void

    func makeNSView(context: Context) -> CanvasEventView {
        let view = CanvasEventView()
        view.shouldCapture = shouldCapture
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        view.onZoom = onZoom
        view.onPointerAnchor = onPointerAnchor
        view.onArrow = onArrow
        return view
    }

    func updateNSView(_ view: CanvasEventView, context: Context) {
        view.shouldCapture = shouldCapture
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        view.onZoom = onZoom
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
    var onPointerAnchor: ((CGPoint) -> Void)?
    var onArrow: ((CanvasArrowDirection) -> Void)?

    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var pointerMonitor: Any?
    private var keyMonitor: Any?
    private weak var monitoredWindow: NSWindow?
    private var scrollEndWorkItem: DispatchWorkItem?

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
                self.onZoom?(CGFloat(raw) * 0.006, anchor)
            } else {
                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
                self.onScroll?(
                    CGSize(
                        width: CGFloat(event.scrollingDeltaX) * multiplier,
                        height: CGFloat(event.scrollingDeltaY) * multiplier
                    ))
                self.scheduleScrollEnd()
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
            self.onZoom?(event.magnification, anchor)
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

    private func scheduleScrollEnd() {
        scrollEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.shouldCapture?() == true else { return }
            self.onScrollEnd?()
        }
        scrollEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: workItem)
    }

    private func removeMonitors() {
        scrollEndWorkItem?.cancel()
        scrollEndWorkItem = nil
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
