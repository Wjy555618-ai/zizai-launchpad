import AppKit
import SwiftUI

struct LayoutModeSwitcherHost: View {
    @EnvironmentObject private var store: LauncherStore
    @ObservedObject var layoutModeController: LayoutModeController
    @Binding var isAllAppsOptionsPresented: Bool
    let reduceMotion: Bool

    var body: some View {
        ViewModeSwitcher(
            selection: Binding(
                get: { layoutModeController.selection },
                set: { mode in
                    guard layoutModeController.selection != mode else { return }
                    isAllAppsOptionsPresented = false
                    zizaiAnimate(ZizaiMotion.selection, reduceMotion: reduceMotion) {
                        layoutModeController.selection = mode
                    }
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    store.stageLayoutModePersistence(mode)
                }
            )
        )
    }
}

struct LayoutModeAllAppsOptions: View {
    @ObservedObject var layoutModeController: LayoutModeController
    @Binding var selection: AllAppsFilter
    @Binding var isPresented: Bool

    var body: some View {
        if layoutModeController.selection == .allApps {
            AllAppsOptionsButton(
                selection: $selection,
                isPresented: $isPresented
            )
            .transition(ZizaiMotion.controlTransition)
        }
    }
}

struct ViewModeSwitcher: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: LayoutMode
    @Namespace private var selectionIndicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LayoutMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(selection == mode ? ZizaiTypography.selectedTab : ZizaiTypography.tab)
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .frame(width: TopChromeMetrics.tabItemWidth, height: TopChromeMetrics.tabItemHeight)
                        .contentShape(Capsule())
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(selectedFill)
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.72), lineWidth: 0.8)
                                    }
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.05), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "layout-mode-selection", in: selectionIndicator)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.rawValue)
                .accessibilityValue(selection == mode ? "selected" : "not-selected")
                .accessibilityHint(mode.usageDescription)
                .accessibilityIdentifier(ZizaiAccessibilityID.layoutMode(mode))
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(TopChromeMetrics.tabContainerPadding)
        .zizaiGlassCapsule(interactive: true)
        .zizaiAnimation(ZizaiMotion.selection, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("视图")
    }

    private var selectedFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.08)
    }
}
