import SwiftUI

private struct ApplicationIconAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private enum LaunchpadRemovalMetrics {
    static let badgeDiameter: CGFloat = 20
    static let cornerOverlap: CGFloat = 4
    static let hitPadding: CGFloat = 4
}

private struct LaunchpadRemovalBadge: View {
    @EnvironmentObject private var removalCoordinator: ApplicationRemovalCoordinator
    let app: AppInfo

    private var capability: ApplicationRemovalCapability {
        removalCoordinator.removalCapability(for: app)
    }

    private var isInteractive: Bool {
        removalCoordinator.managementPhase == .active
            && !removalCoordinator.hasBlockingInteraction
            && removalCoordinator.isRemovingAppID == nil
    }

    var body: some View {
        if capability.presentsManagementBadge {
            Button {
                removalCoordinator.requestRemoval(of: app)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.94))
                    if removalCoordinator.isRemovingAppID == app.id {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color(nsColor: .darkGray))
                    } else {
                        Image(systemName: capability.isDestructiveAction ? "xmark" : "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .darkGray).opacity(0.88))
                    }
                }
                .frame(width: LaunchpadRemovalMetrics.badgeDiameter, height: LaunchpadRemovalMetrics.badgeDiameter)
                .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                .contentShape(Circle())
                .padding(LaunchpadRemovalMetrics.hitPadding)
            }
            .buttonStyle(LaunchpadRemovalButtonStyle())
            .disabled(!isInteractive)
            .allowsHitTesting(isInteractive)
            .accessibilityHidden(!isInteractive)
            .help(capability.actionTitle)
            .accessibilityLabel(
                capability.isDestructiveAction
                    ? "将\(app.chineseName)移到废纸篓"
                    : "了解为什么当前无法移除\(app.chineseName)"
            )
            .accessibilityIdentifier(ZizaiAccessibilityID.applicationRemovalButton(app.id))
        }
    }
}

private struct ApplicationRemovalBadgeModifier: ViewModifier {
    @EnvironmentObject private var removalCoordinator: ApplicationRemovalCoordinator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.primaryLayerIsActive) private var primaryLayerIsActive
    let app: AppInfo

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    private var isVisible: Bool {
        primaryLayerIsActive
            && removalCoordinator.isManaging
            && removalCoordinator.removalCapability(for: app).presentsManagementBadge
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.76)),
            removal: .opacity.combined(with: .scale(scale: 0.88))
        )
    }

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ApplicationIconAnchorPreferenceKey.self) { anchor in
            GeometryReader { proxy in
                ZStack {
                    if let anchor, isVisible {
                        let iconBounds = proxy[anchor]
                        LaunchpadRemovalBadge(app: app)
                            .position(
                                x: iconBounds.minX + LaunchpadRemovalMetrics.cornerOverlap,
                                y: iconBounds.minY + LaunchpadRemovalMetrics.cornerOverlap
                            )
                            .transition(transition)
                    }
                }
                .animation(
                    reduceMotion
                        ? .easeInOut(duration: 0.16)
                        : ApplicationManagementMotion.chromeTransition(entering: isVisible),
                    value: isVisible
                )
            }
        }
    }
}

private struct LaunchpadRemovalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension View {
    func applicationIconAnchor() -> some View {
        anchorPreference(key: ApplicationIconAnchorPreferenceKey.self, value: .bounds) { $0 }
    }

    func launchpadRemovalChrome(for app: AppInfo) -> some View {
        modifier(ApplicationRemovalBadgeModifier(app: app))
    }
}
