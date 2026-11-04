import AppKit
import Combine
import SwiftUI

extension View {
    func applicationManagementLifecycle(
        layoutModeController: LayoutModeController,
        isTooltipEligible: Bool
    ) -> some View {
        modifier(
            ApplicationManagementLifecycleModifier(
                layoutModeController: layoutModeController,
                isTooltipEligible: isTooltipEligible
            )
        )
    }
}

/// Owns every window- and navigation-level boundary of an application
/// management session. Keeping these exits beside the coordinator's input
/// monitor prevents RootView and individual pages from developing competing
/// lifecycle rules.
private struct ApplicationManagementLifecycleModifier: ViewModifier {
    @EnvironmentObject private var coordinator: ApplicationRemovalCoordinator
    @ObservedObject var layoutModeController: LayoutModeController
    let isTooltipEligible: Bool

    func body(content: Content) -> some View {
        content
            .background(
                ApplicationManagementInputMonitor(coordinator: coordinator)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            )
            .onAppear {
                coordinator.endManagement(reason: .lifecycle)
                AppTooltipPanelController.shared.invalidatePresentationContext()
                synchronizeTooltipPresentation()
            }
            .zizaiOnChange(of: coordinator.isManagementPresented) { _ in
                synchronizeTooltipPresentation()
            }
            .zizaiOnChange(of: isTooltipEligible) { _ in
                synchronizeTooltipPresentation()
            }
            .onReceive(layoutModeController.$selection.dropFirst()) { _ in
                coordinator.endManagement(reason: .navigation)
                AppTooltipPanelController.shared.invalidatePresentationContext()
                synchronizeTooltipPresentation()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didResignActiveNotification
                )
            ) { _ in
                endForLifecycleBoundary()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )
            ) { _ in
                coordinator.applicationDidBecomeActive()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            ) { notification in
                guard let window = notification.object as? NSWindow,
                    window.title == "自在启动台"
                else { return }
                endForLifecycleBoundary()
            }
    }

    private func synchronizeTooltipPresentation() {
        AppTooltipPanelController.shared.setPresentationEnabled(
            isTooltipEligible && !coordinator.isManagementPresented
        )
    }

    private func endForLifecycleBoundary() {
        coordinator.endManagement(reason: .lifecycle)
        AppTooltipPanelController.shared.invalidatePresentationContext()
    }
}

/// Observes the parent window once, independent of the three persistent page
/// hosts. Scroll invalidates any detached tooltip before content moves. While
/// management is active, unclaimed pointer-up exits and keyboard or scroll
/// activity extends the deadline. The native event is never intercepted.
private struct ApplicationManagementInputMonitor: NSViewRepresentable {
    @ObservedObject var coordinator: ApplicationRemovalCoordinator

    func makeNSView(context: Context) -> ApplicationManagementInputMonitoringView {
        let view = ApplicationManagementInputMonitoringView()
        view.coordinator = coordinator
        return view
    }

    func updateNSView(
        _ nsView: ApplicationManagementInputMonitoringView,
        context: Context
    ) {
        nsView.coordinator = coordinator
    }

    static func dismantleNSView(
        _ nsView: ApplicationManagementInputMonitoringView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}

@MainActor
private final class ApplicationManagementInputMonitoringView: NSView {
    weak var coordinator: ApplicationRemovalCoordinator?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoringIfNeeded()
        }
    }

    func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func startMonitoringIfNeeded() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .scrollWheel, .keyDown]
        ) { [weak self] event in
            guard let self,
                let parentWindow = self.window,
                event.window === parentWindow
            else { return event }

            if event.type == .scrollWheel {
                AppTooltipPanelController.shared.handleViewportMovement()
            }

            guard let coordinator = self.coordinator, coordinator.isManaging else {
                return event
            }

            switch event.type {
            case .leftMouseUp:
                coordinator.endAfterUnclaimedPointerInteraction()
            case .scrollWheel:
                coordinator.noteActivity()
            case .keyDown:
                if event.keyCode == 53 {
                    coordinator.endManagement(reason: .explicit)
                } else {
                    coordinator.noteActivity()
                }
            default:
                break
            }
            return event
        }
    }
}
