import AppKit
import SwiftUI

struct GroupHeaderTitle: View {
    @State private var isTitleHovered = false

    let title: String
    let detail: String
    let tint: Color
    let identifier: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(title)
                .font(ZizaiTypography.groupTitle)
                .foregroundStyle(Color.primary.opacity(ZizaiTypography.primaryLabelOpacity))
                .lineLimit(1)
                .onHover { isTitleHovered = $0 }
                .overlay(alignment: .topLeading) {
                    if isTitleHovered {
                        DockStyleTooltip(text: detail, tailX: 44)
                            .offset(x: -24, y: -47)
                            .transition(ZizaiMotion.tooltipTransition)
                            .zIndex(10)
                    }
                }
        }
        .frame(height: ZizaiControlMetrics.groupMenuButtonSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(detail)")
        .accessibilityIdentifier(identifier)
        .zizaiAnimation(ZizaiMotion.hover, value: isTitleHovered)
        .zIndex(isTitleHovered ? 2 : 0)
    }
}

struct GroupLibraryCard: View {
    @EnvironmentObject private var store: LauncherStore
    let groupID: String
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    @Binding var appDragSession: LibraryAppDragSession?
    @Binding var appInsertion: AppDragInsertion?
    let onAppDragChanged: (AppInfo, String, Int, CGPoint) -> Void
    let onAppDragEnded: (AppInfo, CGPoint) -> Void
    let onGroupDragChanged: (UserGroup, Int, CGPoint) -> Void
    let onGroupDragEnded: (UserGroup, CGPoint) -> Void
    let geometrySnapshot: LibraryGeometrySnapshot
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if let group = store.group(withID: groupID) {
            let apps = store.apps(in: group.id)
            let renderedApps = apps
            let tint = Palette.tint(for: group.tint)
            let isDropTarget = appDragSession != nil && appInsertion?.groupID == group.id

            VStack(alignment: .leading, spacing: ZizaiLayout.sectionSpacing) {
                HStack(alignment: .center, spacing: 10) {
                    GroupHeaderTitle(
                        title: group.name,
                        detail: "\(apps.count) 个应用 · \(group.subtitle)",
                        tint: tint,
                        identifier: ZizaiAccessibilityID.groupDragHandle(group.id)
                    )
                    .contentShape(Rectangle())
                    .gesture(groupDragGesture(group))
                    .accessibilityHint("拖动分组标题可以调整顺序")

                    Spacer()

                    Menu {
                        Button("重命名与颜色", systemImage: "pencil") { onEdit() }
                        Button("在空间中定位", systemImage: "scope") {
                            store.requestLayoutMode(.space)
                            store.focus(on: group.id)
                        }
                        Button("整理空间位置", systemImage: "square.grid.3x3") {
                            store.arrangeApps(in: group.id)
                        }
                        Button("适配空间大小", systemImage: "arrow.up.left.and.arrow.down.right") {
                            store.fitGroupToContent(id: group.id)
                        }
                        Divider()
                        Button("向上移动", systemImage: "arrow.up") {
                            store.moveGroup(id: group.id, by: -1)
                        }
                        .disabled(store.groups.first?.id == group.id)
                        Button("向下移动", systemImage: "arrow.down") {
                            store.moveGroup(id: group.id, by: 1)
                        }
                        .disabled(store.groups.last?.id == group.id)
                        Divider()
                        Button("删除分组", systemImage: "trash", role: .destructive) { onDelete() }
                            .disabled(store.groups.count <= 1)
                    } label: {
                        GroupMoreMenuIcon()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("\(group.name)更多操作")
                    .accessibilityIdentifier(ZizaiAccessibilityID.groupMenu(group.id))
                }
                .frame(height: ZizaiControlMetrics.groupMenuButtonSize)
                .zIndex(2)

                if apps.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.down.app")
                        Text(
                            isDropTarget
                                ? "松开放入这里"
                                : (store.searchText.isEmpty ? "把应用拖到这里" : "没有符合搜索的应用")
                        )
                    }
                    .font(ZizaiTypography.bodyMedium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 104)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 116, maximum: 164), spacing: ZizaiLayout.gridSpacing)],
                        alignment: .leading,
                        spacing: ZizaiLayout.gridSpacing
                    ) {
                        ForEach(Array(renderedApps.enumerated()), id: \.element.id) { index, app in
                            LibraryAppTile(
                                app: app,
                                groupID: group.id,
                                index: index,
                                aliasTarget: $aliasTarget,
                                aliasDraft: $aliasDraft,
                                onDragChanged: onAppDragChanged,
                                onDragEnded: onAppDragEnded
                            )
                            .background {
                                GeometryReader { proxy in
                                    let frame = proxy.frame(in: .named("library"))
                                    Color.clear
                                        .onAppear {
                                            geometrySnapshot.appFrames[app.id] = AppDragItemFrame(
                                                appID: app.id,
                                                groupID: group.id,
                                                index: index,
                                                frame: frame
                                            )
                                        }
                                        .zizaiOnChange(of: frame) { updatedFrame in
                                            geometrySnapshot.appFrames[app.id] = AppDragItemFrame(
                                                appID: app.id,
                                                groupID: group.id,
                                                index: index,
                                                frame: updatedFrame
                                            )
                                        }
                                        .onDisappear {
                                            geometrySnapshot.appFrames.removeValue(forKey: app.id)
                                        }
                                }
                            }
                            .opacity(appDragSession?.appID == app.id ? 0.20 : 1)
                            .overlay(
                                alignment: insertionMarkerAlignment(at: index, appCount: renderedApps.count)
                            ) {
                                if showsInsertionMarker(at: index, appCount: renderedApps.count) {
                                    AppInsertionMarker()
                                        .offset(
                                            x: insertionMarkerOffset(at: index, appCount: renderedApps.count)
                                        )
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                }
            }
            .padding(ZizaiLayout.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: ZizaiRadius.card, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: ZizaiRadius.card, style: .continuous)
                            .fill(Color.white.opacity(ZizaiOpacity.cardGlassVeil))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: ZizaiRadius.card, style: .continuous)
                            .fill(tint.opacity(ZizaiOpacity.quietTintFill))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: ZizaiRadius.card, style: .continuous)
                            .stroke(
                                tint.opacity(isDropTarget ? 0.42 : ZizaiOpacity.quietBorder),
                                lineWidth: isDropTarget ? 1.4 : 1
                            )
                    }
            }
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("library"))
                    Color.clear
                        .onAppear {
                            geometrySnapshot.groupFrames[group.id] = AppDragGroupFrame(
                                groupID: group.id,
                                frame: frame
                            )
                        }
                        .zizaiOnChange(of: frame) { updatedFrame in
                            geometrySnapshot.groupFrames[group.id] = AppDragGroupFrame(
                                groupID: group.id,
                                frame: updatedFrame
                            )
                        }
                        .onDisappear {
                            geometrySnapshot.groupFrames.removeValue(forKey: group.id)
                        }
                }
            }
            .zizaiAnimation(ZizaiMotion.control, value: isDropTarget)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(group.name)，\(apps.count) 个应用")
            .accessibilityValue(
                "第 \((store.groups.firstIndex(where: { $0.id == group.id }) ?? 0) + 1) 个分组"
            )
            .accessibilityIdentifier(ZizaiAccessibilityID.groupCard(group.id))
        }
    }

    private func showsInsertionMarker(at index: Int, appCount: Int) -> Bool {
        guard let appInsertion, appInsertion.groupID == groupID else { return false }
        return appInsertion.index == index
            || (index == appCount - 1 && appInsertion.index == appCount)
    }

    private func insertionMarkerAlignment(at index: Int, appCount: Int) -> Alignment {
        guard let appInsertion,
            index == appCount - 1,
            appInsertion.index == appCount
        else { return .leading }
        return .trailing
    }

    private func insertionMarkerOffset(at index: Int, appCount: Int) -> CGFloat {
        guard let appInsertion,
            index == appCount - 1,
            appInsertion.index == appCount
        else { return -8 }
        return 8
    }

    private func groupDragGesture(_ group: UserGroup) -> some Gesture {
        let sourceIndex = store.groups.firstIndex(where: { $0.id == group.id }) ?? 0
        return DragGesture(minimumDistance: 4, coordinateSpace: .named("library"))
            .onChanged { value in
                onGroupDragChanged(group, sourceIndex, value.location)
            }
            .onEnded { value in
                onGroupDragEnded(group, value.location)
            }
    }
}

struct GroupInsertionTarget: View {
    let index: Int
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                .fill(Palette.accent.opacity(isActive ? 0.07 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                        .strokeBorder(
                            Palette.accent.opacity(isActive ? 0.44 : 0),
                            style: StrokeStyle(lineWidth: 1.25, dash: [6, 5])
                        )
                }

            if isActive {
                Label("插入分组到这里", systemImage: "arrow.down.to.line.compact")
                    .font(ZizaiTypography.captionMedium)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10)
                    .frame(height: ZizaiControlMetrics.compactRowHeight)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isActive ? 112 : 10)
        .contentShape(Rectangle())
        .zizaiAnimation(ZizaiMotion.control, value: isActive)
        // This is a pointer-only drag target. Exposing every dormant slot
        // makes VoiceOver read controls that cannot currently be acted on.
        .accessibilityHidden(!isActive)
        .accessibilityLabel("把分组插入到第 \(index + 1) 个位置")
    }
}
