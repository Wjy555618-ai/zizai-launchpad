import SwiftUI

extension ApplicationRemovalDialog {
    @ViewBuilder
    @MainActor
    func makeAlertActions(coordinator: ApplicationRemovalCoordinator) -> some View {
        switch kind {
        case .confirmation:
            Button("取消", role: .cancel) {
                coordinator.dismissDialog()
            }
            Button("移到废纸篓", role: .destructive) {
                coordinator.confirmRemoval(of: app)
            }
        case .authorization:
            Button("取消", role: .cancel) {
                coordinator.cancelAuthorizationSelection()
            }
            Button("重新授权") {
                coordinator.beginAuthorizationSelection(for: app)
            }
        case .appManagementPermission:
            Button("取消", role: .cancel) {
                coordinator.dismissDialog()
            }
            Button("打开系统设置") {
                coordinator.openAppManagementSettings(for: app)
            }
        case .appManagementUnavailable:
            Button("知道了", role: .cancel) {
                coordinator.dismissDialog()
            }
            Button("在访达中显示") {
                coordinator.revealInFinder(app)
            }
        case .blocked, .running, .failure:
            Button("知道了") {
                coordinator.dismissDialog()
            }
        }
    }
}
private struct ApplicationManagementTileModifier: ViewModifier {
    @EnvironmentObject private var removalCoordinator: ApplicationRemovalCoordinator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let app: AppInfo
    private var reduceMotion: Bool { ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion) }
    private var isCompletingRemoval: Bool { removalCoordinator.completingAppID == app.id }

    func body(content: Content) -> some View {
        content
            .launchpadRemovalChrome(for: app)
            .scaleEffect(
                isCompletingRemoval && !reduceMotion
                    ? ApplicationManagementMotion.removalScale : 1
            )
            .offset(
                y: isCompletingRemoval && !reduceMotion
                    ? ApplicationManagementMotion.removalOffsetY : 0
            )
            .blur(
                radius: isCompletingRemoval && !reduceMotion
                    ? ApplicationManagementMotion.removalBlur : 0
            )
            .opacity(isCompletingRemoval ? 0 : 1)
            .animation(
                ApplicationManagementMotion.removalTransition(reduceMotion: reduceMotion),
                value: isCompletingRemoval
            )
            .allowsHitTesting(!isCompletingRemoval)
            .accessibilityHidden(isCompletingRemoval)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6, maximumDistance: 4)
                    .onEnded { _ in
                        removalCoordinator.beginManagement(trigger: .longPress)
                    }
            )
            .accessibilityAction(named: Text("管理应用")) {
                removalCoordinator.beginManagement(trigger: .accessibility)
            }
            .modifier(ApplicationRemovalAccessibilityActionModifier(app: app))
    }
}

/// Exposes an honest custom action for every capability state. Protected and
/// denied applications offer an explanation action, never a destructive action
/// that VoiceOver users cannot complete.
private struct ApplicationRemovalAccessibilityActionModifier: ViewModifier {
    @EnvironmentObject private var removalCoordinator: ApplicationRemovalCoordinator
    let app: AppInfo

    func body(content: Content) -> some View {
        let capability = removalCoordinator.removalCapability(for: app)
        content.accessibilityAction(named: Text(capability.actionTitle)) {
            removalCoordinator.requestRemoval(of: app)
        }
    }
}

extension View {
    func applicationManagement(for app: AppInfo) -> some View {
        modifier(ApplicationManagementTileModifier(app: app))
    }
}

struct ApplicationRemovalMenuItem: View {
    @EnvironmentObject private var removalCoordinator: ApplicationRemovalCoordinator
    let app: AppInfo

    var body: some View {
        let capability = removalCoordinator.removalCapability(for: app)
        Button(role: capability.isDestructiveAction ? .destructive : nil) {
            removalCoordinator.requestRemoval(of: app)
        } label: {
            Label(
                capability.actionTitle,
                systemImage: capability.actionSystemImage
            )
        }
    }
}
