import SwiftUI

/// Owns the top-chrome side of application-management presentation. The
/// normal actions and Done control remain in one stable layout container, so
/// entering edit mode never causes the right edge to jump or hard-swap.
struct ApplicationManagementTopActions: View {
    @EnvironmentObject private var removalCoordinator: ApplicationRemovalCoordinator

    @Binding var searchText: String
    let isSearchPresented: Bool
    @FocusState.Binding var searchFocused: Bool
    @Binding var allAppsFilter: AllAppsFilter
    @Binding var isAllAppsOptionsPresented: Bool
    let reduceMotion: Bool
    let onOpenSearch: () -> Void
    let onClearSearch: () -> Void
    let onExitSearch: () -> Void
    let onSubmitSearch: () -> Void
    let onSelectFilter: (AllAppsFilter) -> Void
    let onCreateGroup: () -> Void
    let onShowHelp: () -> Void

    var body: some View {
        let isManaging = removalCoordinator.isManaging
        ZStack(alignment: .trailing) {
            normalActions
                .opacity(isManaging ? 0 : 1)
                .scaleEffect(
                    isManaging && !reduceMotion ? 0.985 : 1,
                    anchor: .trailing
                )
                .allowsHitTesting(!removalCoordinator.isManagementPresented)
                .modifier(
                    ManagementAccessibilityVisibilityModifier(
                        isHidden: removalCoordinator.isManagementPresented
                    )
                )

            Button("完成") {
                removalCoordinator.endManagement()
            }
            .buttonStyle(.plain)
            .font(ZizaiTypography.bodyMedium)
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 18)
            .frame(height: TopChromeMetrics.controlHeight)
            .zizaiGlassCapsule(interactive: true)
            .opacity(isManaging ? 1 : 0)
            .scaleEffect(
                isManaging || reduceMotion ? 1 : 0.94,
                anchor: .trailing
            )
            .allowsHitTesting(isManaging)
            .modifier(ManagementAccessibilityVisibilityModifier(isHidden: !isManaging))
            .accessibilityLabel("完成应用管理")
            .accessibilityIdentifier(ZizaiAccessibilityID.applicationManagementDone)
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.16)
                : ApplicationManagementMotion.chromeTransition(entering: isManaging),
            value: isManaging
        )
    }

    private var normalActions: some View {
        HStack(spacing: TopChromeMetrics.itemSpacing) {
            ExpandableSearchControl(
                text: $searchText,
                isExpanded: isSearchPresented,
                isFocused: $searchFocused,
                onOpen: onOpenSearch,
                onClear: onClearSearch,
                onExit: onExitSearch,
                onSubmit: onSubmitSearch
            )
            .layoutPriority(1)

            Button(action: onCreateGroup) {
                ZizaiTopChromeActionSymbol(systemName: "plus")
            }
            .buttonStyle(.plain)
            .zizaiGlassCapsule(interactive: true)
            .accessibilityLabel("新建分组")
            .accessibilityHint("创建一个可以改名和调整大小的分组")
            .accessibilityIdentifier(ZizaiAccessibilityID.newGroupButton)

            AppCatalogOptionsHost(
                selection: $allAppsFilter,
                isPresented: $isAllAppsOptionsPresented,
                onSelectFilter: onSelectFilter
            )

            Button(action: onShowHelp) {
                ZizaiTopChromeActionSymbol(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .zizaiGlassCapsule(interactive: true)
            .accessibilityLabel("使用帮助")
            .accessibilityIdentifier(ZizaiAccessibilityID.helpButton)
        }
    }
}

/// Applies an ancestor accessibility override only while the entire subtree is
/// unavailable. Passing `false` to `accessibilityHidden` on a container can
/// override a descendant's own collapsed state, which would leak hidden search
/// controls into VoiceOver. The visible branch deliberately preserves every
/// descendant's independent accessibility contract.
private struct ManagementAccessibilityVisibilityModifier: ViewModifier {
    let isHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isHidden {
            content.accessibilityHidden(true)
        } else {
            content
        }
    }
}
