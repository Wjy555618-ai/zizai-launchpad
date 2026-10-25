import Foundation
import SwiftUI

enum AllAppsFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case visible = "正在显示"
    case hidden = "已隐藏"
    var id: String { rawValue }
}

/// An eager counterpart to LazyVGrid for the bounded all-apps collection.
/// The app count is small enough to lay out once at launch, which removes the
/// otherwise unavoidable first-tab construction pause.
private struct EagerAdaptiveGrid: Layout {
    let minimum: CGFloat
    let spacing: CGFloat

    struct Cache {
        var width: CGFloat?
        var itemCount = 0
        var columns = 1
        var itemWidth: CGFloat = 0
        var rowHeights: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let fallbackColumns = max(1, min(subviews.count, 9))
        let fallbackWidth =
            minimum * CGFloat(fallbackColumns)
            + spacing * CGFloat(max(0, fallbackColumns - 1))
        let proposedWidth = proposal.width ?? fallbackWidth
        let width = proposedWidth.isFinite ? max(minimum, proposedWidth) : fallbackWidth
        prepareCache(for: width, subviews: subviews, cache: &cache)
        let totalSpacing = spacing * CGFloat(max(0, cache.rowHeights.count - 1))
        return CGSize(width: width, height: cache.rowHeights.reduce(0, +) + totalSpacing)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        prepareCache(for: bounds.width, subviews: subviews, cache: &cache)
        var rowOrigins: [CGFloat] = []
        var y = bounds.minY
        for height in cache.rowHeights {
            rowOrigins.append(y)
            y += height + spacing
        }

        for (index, subview) in subviews.enumerated() {
            let row = index / cache.columns
            let column = index % cache.columns
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(column) * (cache.itemWidth + spacing),
                    y: rowOrigins[row]
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cache.itemWidth, height: cache.rowHeights[row])
            )
        }
    }

    private func prepareCache(for width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.width != width || cache.itemCount != subviews.count else { return }
        let metrics = metrics(for: width, itemCount: subviews.count)
        cache.width = width
        cache.itemCount = subviews.count
        cache.columns = metrics.columns
        cache.itemWidth = metrics.itemWidth
        cache.rowHeights = measuredRowHeights(
            subviews: subviews,
            columns: metrics.columns,
            itemWidth: metrics.itemWidth
        )
    }

    private func metrics(for width: CGFloat, itemCount: Int) -> (columns: Int, itemWidth: CGFloat) {
        let safeWidth = width.isFinite ? max(minimum, width) : minimum
        let columns = max(1, min(itemCount, Int((safeWidth + spacing) / (minimum + spacing))))
        let itemWidth = (safeWidth - spacing * CGFloat(max(0, columns - 1))) / CGFloat(columns)
        return (columns, itemWidth)
    }

    private func measuredRowHeights(
        subviews: Subviews,
        columns: Int,
        itemWidth: CGFloat
    ) -> [CGFloat] {
        guard !subviews.isEmpty else { return [] }
        var heights = Array(repeating: CGFloat.zero, count: Int(ceil(Double(subviews.count) / Double(columns))))
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            heights[index / columns] = max(heights[index / columns], size.height)
        }
        return heights
    }
}

struct AllAppsView: View {
    @EnvironmentObject private var store: LauncherStore
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    @Binding var filter: AllAppsFilter

    private var filteredApps: [AppInfo] {
        store.allFilteredApps.filter { app in
            switch filter {
            case .all: return true
            case .visible: return !store.isHidden(app)
            case .hidden: return store.isHidden(app)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ZizaiLayout.cardPadding) {
                if filteredApps.isEmpty {
                    ZizaiUnavailableView(
                        title: filter == .hidden ? "没有已隐藏的应用" : "没有可显示的应用",
                        systemImage: filter == .hidden ? "eye" : "square.grid.3x3",
                        description: filter == .hidden ? "隐藏应用后会在这里集中管理。" : "请重新扫描应用，或切换筛选条件。"
                    )
                    .frame(minHeight: 320)
                } else {
                    EagerAdaptiveGrid(minimum: 124, spacing: ZizaiLayout.gridSpacing) {
                        ForEach(filteredApps) { app in
                            AllAppsTile(
                                app: app,
                                aliasTarget: $aliasTarget,
                                aliasDraft: $aliasDraft
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, ZizaiLayout.contentHorizontalPadding)
            .padding(.top, ZizaiLayout.contentTopPadding)
            .padding(.bottom, ZizaiLayout.contentBottomPadding)
        }
        .accessibilityIdentifier(ZizaiAccessibilityID.allAppsScreen)
    }
}

struct AllAppsOptionsButton: View {
    @EnvironmentObject private var store: LauncherStore
    @Binding var selection: AllAppsFilter
    @Binding var isPresented: Bool
    @State private var isTriggerHovered = false
    @State private var isPopoverHovered = false
    @State private var openWorkItem: DispatchWorkItem?
    @State private var closeWorkItem: DispatchWorkItem?

    var body: some View {
        Button {
            cancelPendingWork()
            isPresented.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: TopChromeMetrics.actionSymbolSize, weight: .medium))
                .frame(
                    width: TopChromeMetrics.actionButtonSize,
                    height: TopChromeMetrics.actionButtonSize
                )
        }
        .buttonStyle(.plain)
        .zizaiGlassCapsule(interactive: true)
        .onHover(perform: handleTriggerHover)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 4) {
                ForEach(AllAppsFilter.allCases) { item in
                    AllAppsOptionsRow(
                        title: item.rawValue,
                        systemImage: "checkmark",
                        reservesImageSpace: true,
                        showsImage: selection == item
                    ) {
                        selection = item
                        isPresented = false
                    }
                    .accessibilityValue(selection == item ? "已选中" : "")
                }

                Divider()
                    .padding(.vertical, 3)

                AllAppsOptionsRow(
                    title: "重新扫描",
                    systemImage: "arrow.clockwise",
                    reservesImageSpace: true,
                    showsImage: true
                ) {
                    isPresented = false
                    store.reloadApps(announce: true)
                }
            }
            .padding(8)
            .frame(width: 178)
            .onHover(perform: handlePopoverHover)
            .onExitCommand {
                isPresented = false
            }
        }
        .help("筛选与重新扫描")
        .accessibilityLabel("筛选与重新扫描")
        .accessibilityHint("显示全部、正在显示、已隐藏和重新扫描选项")
        .onDisappear(perform: cancelPendingWork)
    }

    private func handleTriggerHover(_ hovering: Bool) {
        isTriggerHovered = hovering
        if hovering {
            closeWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                guard isTriggerHovered else { return }
                isPresented = true
            }
            openWorkItem?.cancel()
            openWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
        } else {
            openWorkItem?.cancel()
            scheduleClose()
        }
    }

    private func handlePopoverHover(_ hovering: Bool) {
        isPopoverHovered = hovering
        if hovering {
            closeWorkItem?.cancel()
        } else {
            scheduleClose()
        }
    }

    private func scheduleClose() {
        closeWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard !isTriggerHovered && !isPopoverHovered else { return }
            isPresented = false
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
    }

    private func cancelPendingWork() {
        openWorkItem?.cancel()
        closeWorkItem?.cancel()
    }
}

private struct AllAppsOptionsRow: View {
    let title: String
    let systemImage: String
    let reservesImageSpace: Bool
    let showsImage: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if reservesImageSpace {
                    Image(systemName: systemImage)
                        .font(ZizaiTypography.secondaryMedium)
                        .foregroundStyle(.secondary)
                        .opacity(showsImage ? 1 : 0)
                        .frame(width: 16)
                }

                Text(title)
                    .font(ZizaiTypography.body)

                Spacer(minLength: 8)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .frame(height: ZizaiControlMetrics.compactRowHeight)
            .contentShape(RoundedRectangle(cornerRadius: ZizaiRadius.control, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: ZizaiRadius.control, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? ZizaiOpacity.hoverFill : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .zizaiAnimation(ZizaiMotion.hover, value: isHovered)
        .accessibilityLabel(title)
    }
}

private struct AllAppsTile: View {
    @EnvironmentObject private var store: LauncherStore
    let app: AppInfo
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String

    @State private var isHovering = false

    var body: some View {
        Button {
            store.launch(app)
        } label: {
            AppIconContent(
                app: app,
                size: 68,
                isHidden: store.isHidden(app),
                isSelected: false
            )
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppTileButtonStyle())
        .scaleEffect(isHovering ? 1.015 : 1)
        .brightness(isHovering ? 0.025 : 0)
        .onHover { isHovering = $0 }
        .zizaiAnimation(ZizaiMotion.hover, value: isHovering)
        .contextMenu { appMenu }
        .accessibilityLabel(store.displayName(for: app))
        .accessibilityValue(
            "\(store.isHidden(app) ? "已隐藏" : "正在显示")，\(store.instanceLabel(for: app) ?? app.purpose)"
        )
        .accessibilityHint(store.isHidden(app) ? "单击打开；当前未在空间和分组中显示" : "单击打开")
        .accessibilityIdentifier(ZizaiAccessibilityID.appTile(app.id))
    }

    @ViewBuilder
    private var appMenu: some View {
        Button(
            store.isHidden(app) ? "恢复到空间和分组" : "从空间和分组中隐藏",
            systemImage: store.isHidden(app) ? "eye" : "eye.slash"
        ) {
            store.setHidden(!store.isHidden(app), for: app)
        }
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
        Divider()
        Button("在访达中显示", systemImage: "folder") { store.revealInFinder(app) }
        Button("打开应用", systemImage: "arrow.up.forward.app") { store.launch(app) }
    }
}
