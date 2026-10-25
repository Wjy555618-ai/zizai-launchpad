import AppKit
import SwiftUI

enum SearchResultsGridLayout {
    static let minimumColumnWidth: CGFloat = 240
    static let maximumColumnWidth: CGFloat = 340
    static let maximumColumnCount = 3

    /// Constrains sparse result sets to the width they can actually use. An
    /// unconstrained adaptive grid reserves an invisible third column for two
    /// results, making the screen look left-heavy even though the grid itself
    /// is centered. Dense result sets still grow to three responsive columns.
    static func maximumWidth(resultCount: Int, spacing: CGFloat) -> CGFloat {
        let columnCount = min(max(resultCount, 1), maximumColumnCount)
        return CGFloat(columnCount) * maximumColumnWidth
            + CGFloat(columnCount - 1) * spacing
    }
}

/// The search affordance owns one fixed surface and changes only its visible
/// viewport. This prevents top-chrome reflow while the field opens and closes.
struct ExpandableSearchControl: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Binding var text: String
    let isExpanded: Bool
    @FocusState.Binding var isFocused: Bool
    let onOpen: () -> Void
    let onClear: () -> Void
    let onClose: () -> Void
    let onExit: () -> Void
    let onSubmit: () -> Void

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    var body: some View {
        Color.clear
            .frame(
                width: TopChromeMetrics.actionButtonSize,
                height: TopChromeMetrics.controlHeight
            )
            .overlay(alignment: .trailing) {
                searchViewport
            }
            .overlay {
                if !isExpanded {
                    Button(action: onOpen) {
                        Color.clear
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索")
                    .accessibilityHint("从右侧按钮向左展开搜索框")
                    .accessibilityIdentifier(ZizaiAccessibilityID.searchButton)
                }
            }
            .zizaiAnimation(ZizaiMotion.searchExpansion, value: isExpanded)
            .zizaiAnimation(ZizaiMotion.control, value: isFocused)
            .zizaiAnimation(ZizaiMotion.control, value: text.isEmpty)
    }

    private var searchViewport: some View {
        searchSurface
            .offset(
                x: isExpanded
                    ? 0
                    : TopChromeMetrics.searchWidth - TopChromeMetrics.actionButtonSize
            )
            .frame(
                width: TopChromeMetrics.searchWidth,
                height: TopChromeMetrics.controlHeight,
                alignment: .trailing
            )
            .clipShape(Capsule())
            .allowsHitTesting(isExpanded)
    }

    private var searchSurface: some View {
        searchContents
            .frame(
                width: TopChromeMetrics.searchWidth,
                height: TopChromeMetrics.controlHeight,
                alignment: .leading
            )
            .contentShape(Capsule())
            .zizaiGlassCapsule(interactive: true)
            .overlay {
                Capsule()
                    .strokeBorder(
                        Palette.accent.opacity(isExpanded && isFocused ? 0.30 : 0),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
    }

    private var searchContents: some View {
        HStack(spacing: 8) {
            ZizaiTopChromeActionSymbol(
                systemName: "magnifyingglass",
                frameWidth: 16,
                frameHeight: 18
            )
            .accessibilityHidden(true)

            TextField("搜索名称、用途或分组", text: $text)
                .textFieldStyle(.plain)
                .font(ZizaiTypography.body)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onExit)
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
                .accessibilityLabel("搜索应用")
                .accessibilityHint("按名称、用途或分组查找应用")
                .accessibilityIdentifier(ZizaiAccessibilityID.searchField)

            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.72))
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
                .accessibilityLabel("清除搜索")
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }

            Button(action: onClose) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isExpanded ? 0.78 : 0)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .accessibilityLabel("收起搜索")
            .accessibilityHint("清除搜索并返回当前视图")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(
            width: TopChromeMetrics.searchWidth,
            height: TopChromeMetrics.controlHeight,
            alignment: .leading
        )
        .animation(
            reduceMotion ? nil : ZizaiMotion.searchDisclosure,
            value: isExpanded
        )
    }
}

struct SearchResultsView: View {
    @EnvironmentObject private var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: ZizaiLayout.sectionSpacing) {
                    VStack(spacing: 6) {
                        Text("搜索结果")
                            .font(ZizaiTypography.pageTitle)
                            .accessibilityIdentifier(ZizaiAccessibilityID.searchResultsHeading)
                        if store.searchResults.isEmpty {
                            Text("没有找到“\(store.searchText)”")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("找到 \(store.searchResults.count) 个应用 · 回车可依次定位")
                                .font(ZizaiTypography.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 84)

                    if store.searchResults.isEmpty {
                        ZizaiUnavailableView(
                            title: "没有符合的应用",
                            systemImage: "magnifyingglass",
                            description: "优先按名称、用途和分组匹配；英文名称支持按字母顺序容错。"
                        )
                        .frame(minHeight: 320)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(
                                        minimum: SearchResultsGridLayout.minimumColumnWidth,
                                        maximum: SearchResultsGridLayout.maximumColumnWidth
                                    ),
                                    spacing: ZizaiLayout.gridSpacing
                                )
                            ],
                            spacing: ZizaiLayout.gridSpacing
                        ) {
                            ForEach(store.searchResults) { app in
                                SearchResultTile(
                                    app: app,
                                    isCurrent: store.currentSearchResultID == app.id,
                                    aliasTarget: $aliasTarget,
                                    aliasDraft: $aliasDraft
                                )
                                .id(app.id)
                            }
                        }
                        .frame(
                            maxWidth: SearchResultsGridLayout.maximumWidth(
                                resultCount: store.searchResults.count,
                                spacing: ZizaiLayout.gridSpacing
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 48)
                .padding(.bottom, ZizaiLayout.contentBottomPadding)
            }
            .onAppear {
                store.refreshSearchSelection()
                scrollToCurrent(using: reader)
            }
            .zizaiOnChange(of: store.currentSearchResultID) { _ in
                scrollToCurrent(using: reader)
            }
        }
    }

    private func scrollToCurrent(using reader: ScrollViewProxy) {
        guard let current = store.currentSearchResultID else { return }
        if reduceMotion {
            reader.scrollTo(current, anchor: .center)
        } else {
            zizaiAnimate(ZizaiMotion.spatial, reduceMotion: reduceMotion) {
                reader.scrollTo(current, anchor: .center)
            }
        }
    }
}

private struct SearchResultTile: View {
    @EnvironmentObject private var store: LauncherStore
    let app: AppInfo
    let isCurrent: Bool
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String

    private var instanceLabel: String? {
        store.instanceLabel(for: app)
    }

    var body: some View {
        Button {
            store.launch(app)
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: IconCache.shared.icon(for: app.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 68, height: 68)
                        .shadow(
                            color: .black.opacity(ZizaiShadow.iconOpacity),
                            radius: 68 * ZizaiShadow.iconRadiusScale,
                            y: 68 * ZizaiShadow.iconYScale
                        )

                    if store.isHidden(app) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.62), in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.editableDisplayName(for: app))
                        .font(ZizaiTypography.appName(size: 72, scale: 1))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(instanceLabel ?? app.purpose)
                        .font(ZizaiTypography.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                    .fill(Palette.accent.opacity(isCurrent ? 0.13 : 0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                    .stroke(
                        Palette.accent.opacity(isCurrent ? 0.92 : 0.36),
                        lineWidth: isCurrent ? 2.5 : 1
                    )
            }
            .shadow(
                color: Palette.accent.opacity(isCurrent ? ZizaiShadow.selectedOpacity : 0.05),
                radius: isCurrent ? ZizaiShadow.selectedRadius : ZizaiRadius.badge,
                y: ZizaiShadow.selectedY
            )
        }
        .buttonStyle(AppTileButtonStyle())
        .contextMenu {
            Menu("移到分组", systemImage: "folder") {
                ForEach(store.groups) { group in
                    Button(group.name) { store.move(app, toGroupID: group.id) }
                        .disabled(store.group(for: app)?.id == group.id)
                }
            }
            Button("重命名", systemImage: "pencil") {
                aliasDraft = store.editableDisplayName(for: app)
                aliasTarget = app
            }
            Button(
                store.isHidden(app) ? "恢复到空间和分组" : "从空间和分组中隐藏",
                systemImage: store.isHidden(app) ? "eye" : "eye.slash"
            ) {
                store.setHidden(!store.isHidden(app), for: app)
            }
            Divider()
            Button("在访达中显示", systemImage: "folder") { store.revealInFinder(app) }
            Button("打开应用", systemImage: "arrow.up.forward.app") { store.launch(app) }
        }
        .accessibilityLabel(
            [store.editableDisplayName(for: app), instanceLabel]
                .compactMap { $0 }
                .joined(separator: "，")
        )
        .accessibilityValue(isCurrent ? "当前搜索结果" : "搜索匹配")
        .accessibilityHint("单击打开；按回车依次定位搜索结果")
    }
}
