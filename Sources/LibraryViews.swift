import AppKit
import SwiftUI

private struct LibraryAppDragSession: Equatable {
    let appID: String
    let sourceGroupID: String
    let sourceIndex: Int
}

private struct LibraryGroupDragSession: Equatable {
    let groupID: String
    let sourceIndex: Int
}

/// Geometry is observational input, not view state. Keeping the live frames in
/// a reference cache prevents measurement from invalidating the same layout
/// pass that produced it. A drag freezes this cache into value snapshots once,
/// so every hit test uses one coherent layout revision.
private final class LibraryGeometrySnapshot {
    var appFrames: [String: AppDragItemFrame] = [:]
    var groupFrames: [String: AppDragGroupFrame] = [:]
}

struct GroupLibraryView: View {
    @EnvironmentObject private var store: LauncherStore
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    let onEditGroup: (UserGroup) -> Void
    let onDeleteGroup: (UserGroup) -> Void

    @State private var appDragSession: LibraryAppDragSession?
    @State private var appInsertion: AppDragInsertion?
    @State private var appDragLocation: CGPoint = .zero
    @State private var appDragFrames: [String: AppDragItemFrame] = [:]
    @State private var appDragGroupFrames: [String: AppDragGroupFrame] = [:]
    @State private var groupDragSession: LibraryGroupDragSession?
    @State private var groupInsertionIndex: Int?
    @State private var groupDragLocation: CGPoint = .zero
    @State private var groupDragFrames: [String: AppDragGroupFrame] = [:]
    @State private var appDragDiagnostic = "idle"
    @State private var geometrySnapshot = LibraryGeometrySnapshot()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                        GroupInsertionTarget(
                            index: index,
                            isActive: groupDragSession != nil && groupInsertionIndex == index
                        )

                        GroupLibraryCard(
                            groupID: group.id,
                            aliasTarget: $aliasTarget,
                            aliasDraft: $aliasDraft,
                            appDragSession: $appDragSession,
                            appInsertion: $appInsertion,
                            onAppDragChanged: updateAppDrag,
                            onAppDragEnded: finishAppDrag,
                            onGroupDragChanged: updateGroupDrag,
                            onGroupDragEnded: finishGroupDrag,
                            geometrySnapshot: geometrySnapshot,
                            onEdit: { onEditGroup(group) },
                            onDelete: { onDeleteGroup(group) }
                        )
                        .opacity(groupDragSession?.groupID == group.id ? 0.24 : 1)
                    }

                    GroupInsertionTarget(
                        index: store.groups.count,
                        isActive: groupDragSession != nil && groupInsertionIndex == store.groups.count
                    )

                    if store.groups.isEmpty {
                        ZizaiUnavailableView(
                            title: "还没有分组",
                            systemImage: "square.grid.2x2",
                            description: "点右上角“新建分组”开始整理。"
                        )
                        .padding(.top, 80)
                    }
                }
                .padding(.horizontal, ZizaiLayout.contentHorizontalPadding)
                .padding(.top, ZizaiLayout.contentTopPadding)
                .padding(.bottom, ZizaiLayout.contentBottomPadding)
            }

            if let session = appDragSession,
                let app = store.apps.first(where: { $0.id == session.appID })
            {
                DragPreview(app: app)
                    .environmentObject(store)
                    .position(appDragLocation)
                    .allowsHitTesting(false)
                    .zIndex(20)
            }

            if let session = groupDragSession,
                let group = store.group(withID: session.groupID)
            {
                GroupDragPreview(group: group, apps: store.apps(in: group.id))
                    .environmentObject(store)
                    .position(groupDragLocation)
                    .allowsHitTesting(false)
                    .zIndex(21)
            }

        }
        .coordinateSpace(name: "library")
        .accessibilityIdentifier(ZizaiAccessibilityID.groupsScreen)
        .accessibilityValue(exposesUITestDiagnostics ? appDragDiagnostic : "")
    }

    private func updateAppDrag(_ app: AppInfo, _ groupID: String, _ sourceIndex: Int, _ location: CGPoint) {
        if appDragSession == nil {
            appDragSession = LibraryAppDragSession(
                appID: app.id,
                sourceGroupID: groupID,
                sourceIndex: sourceIndex
            )
            appDragFrames = geometrySnapshot.appFrames
            appDragGroupFrames = geometrySnapshot.groupFrames
        }
        appDragLocation = location
        appInsertion = resolvedAppInsertion(at: location, excluding: app.id)
        if exposesUITestDiagnostics {
            appDragDiagnostic = dragDiagnostic(
                phase: "changed",
                location: location,
                insertion: appInsertion
            )
        }
    }

    private func finishAppDrag(_ app: AppInfo, _ location: CGPoint) {
        appDragLocation = location
        // The insertion shown during the final drag update is the user's explicit
        // drop target. Prefer a fresh resolution, but preserve that last stable
        // target when SwiftUI has already begun a layout pass before mouse-up.
        // This keeps the visual preview and committed result transactional.
        let insertion = resolvedAppInsertion(at: location, excluding: app.id) ?? appInsertion
        if exposesUITestDiagnostics {
            appDragDiagnostic = dragDiagnostic(
                phase: "ended",
                location: location,
                insertion: insertion
            )
        }
        if let insertion {
            store.move(
                app,
                toGroupID: insertion.groupID,
                insertionIndex: resolvedInsertionIndex(insertion.index, destinationGroupID: insertion.groupID)
            )
        }
        appDragSession = nil
        appInsertion = nil
        appDragFrames = [:]
        appDragGroupFrames = [:]
    }

    private var exposesUITestDiagnostics: Bool {
        #if DEBUG
            return ProcessInfo.processInfo.environment[ZizaiLaunchConfiguration.uiTestingEnvironmentKey] == "1"
        #else
            return false
        #endif
    }

    private func dragDiagnostic(
        phase: String,
        location: CGPoint,
        insertion: AppDragInsertion?
    ) -> String {
        let destination = insertion.map { "\($0.groupID):\($0.index)" } ?? "none"
        let frames = geometrySnapshot.groupFrames.values
            .sorted { $0.groupID < $1.groupID }
            .map {
                "\($0.groupID)[\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.maxX)),\(Int($0.frame.maxY))]"
            }
            .joined(separator: ",")
        return
            "phase=\(phase);apps=\(appDragFrames.count);groups=\(geometrySnapshot.groupFrames.count);x=\(Int(location.x));y=\(Int(location.y));destination=\(destination);frames=\(frames)"
    }

    private func resolvedAppInsertion(at location: CGPoint, excluding appID: String) -> AppDragInsertion? {
        InteractionGeometry.appInsertion(
            at: location,
            appFrames: Array(
                (appDragFrames.isEmpty ? geometrySnapshot.appFrames : appDragFrames).values
            ),
            groupFrames: Array(
                (appDragGroupFrames.isEmpty
                    ? geometrySnapshot.groupFrames : appDragGroupFrames).values
            ),
            excluding: appID
        )
    }

    private func resolvedInsertionIndex(_ proposed: Int, destinationGroupID: String) -> Int {
        guard let session = appDragSession,
            session.sourceGroupID == destinationGroupID
        else { return proposed }
        return InteractionGeometry.normalizedInsertionIndex(
            movingFrom: session.sourceIndex,
            proposed: proposed,
            itemCount: store.apps(in: destinationGroupID).count
        )
    }

    private func updateGroupDrag(_ group: UserGroup, _ sourceIndex: Int, _ location: CGPoint) {
        if groupDragSession == nil {
            groupDragSession = LibraryGroupDragSession(groupID: group.id, sourceIndex: sourceIndex)
            groupDragFrames = geometrySnapshot.groupFrames
        }
        groupDragLocation = location
        groupInsertionIndex = resolvedGroupInsertion(at: location, excluding: group.id)
    }

    private func finishGroupDrag(_ group: UserGroup, _ location: CGPoint) {
        groupDragLocation = location
        if let insertion = resolvedGroupInsertion(at: location, excluding: group.id) ?? groupInsertionIndex {
            store.moveGroup(id: group.id, toInsertionIndex: insertion)
        }
        groupDragSession = nil
        groupInsertionIndex = nil
        groupDragFrames = [:]
    }

    private func resolvedGroupInsertion(at location: CGPoint, excluding groupID: String) -> Int? {
        let stableFrames =
            groupDragFrames.isEmpty ? geometrySnapshot.groupFrames : groupDragFrames
        return InteractionGeometry.groupInsertionIndex(
            at: location,
            groupFrames: Array(stableFrames.values),
            orderedGroupIDs: store.groups.map(\.id),
            movingGroupID: groupID
        )
    }
}

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

private struct GroupLibraryCard: View {
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

private struct GroupInsertionTarget: View {
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

private struct LibraryAppTile: View {
    @EnvironmentObject private var store: LauncherStore
    let app: AppInfo
    let groupID: String
    let index: Int
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    let onDragChanged: (AppInfo, String, Int, CGPoint) -> Void
    let onDragEnded: (AppInfo, CGPoint) -> Void
    @State private var suppressLaunch = false

    var body: some View {
        Button {
            if !suppressLaunch { store.launch(app) }
        } label: {
            AppIconContent(app: app, size: 64)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous))
        // A library tile has two mutually exclusive pointer meanings: a click
        // launches, while movement reorganizes. Give the drag recognizer
        // priority over Button's press recognizer so AppKit delivers the full
        // pointer sequence to one owner; the minimum distance preserves clicks.
        .simultaneousGesture(appDragGesture)
        .contextMenu {
            appMenu
        }
        .accessibilityLabel(store.displayName(for: app))
        .accessibilityValue(
            "当前分组：\(store.group(withID: groupID)?.name ?? "未知")，第 \(index + 1) 个，\(app.purpose)"
        )
        .accessibilityHint("单击打开；拖到应用之间可以插入换序，拖到其他分组可以换组")
        .accessibilityIdentifier(ZizaiAccessibilityID.appTile(app.id))
    }

    private var appDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("library"))
            .onChanged { value in
                suppressLaunch = true
                onDragChanged(app, groupID, index, value.location)
            }
            .onEnded { value in
                onDragEnded(app, value.location)
                DispatchQueue.main.async {
                    suppressLaunch = false
                }
            }
    }

    @ViewBuilder
    private var appMenu: some View {
        let orderedApps = store.apps(in: groupID)
        let index = orderedApps.firstIndex(of: app) ?? 0

        Button("向前移动", systemImage: "arrow.left") {
            store.moveApp(app, inGroupID: groupID, by: -1)
        }
        .disabled(index == 0)
        Button("向后移动", systemImage: "arrow.right") {
            store.moveApp(app, inGroupID: groupID, by: 1)
        }
        .disabled(index >= orderedApps.count - 1)
        Divider()
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
        Button("从空间和分组中隐藏", systemImage: "eye.slash") {
            store.setHidden(true, for: app)
        }
        Divider()
        Button("在访达中显示", systemImage: "folder") { store.revealInFinder(app) }
        Button("打开应用", systemImage: "arrow.up.forward.app") { store.launch(app) }
    }
}

private struct DragPreview: View {
    let app: AppInfo

    var body: some View {
        AppIconContent(app: app, size: 58)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous))
    }
}

private struct GroupDragPreview: View {
    let group: UserGroup
    let apps: [AppInfo]

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Palette.tint(for: group.tint))
                .frame(width: 11, height: 11)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(ZizaiTypography.groupTitle)
                    .foregroundStyle(Color.primary.opacity(ZizaiTypography.primaryLabelOpacity))
                Text("移动整个分组 · \(apps.count) 个应用")
                    .font(ZizaiTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: -5) {
                ForEach(Array(apps.prefix(5))) { app in
                    Image(nsImage: IconCache.shared.icon(for: app.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: ZizaiRadius.control, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 430, height: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                .stroke(Palette.tint(for: group.tint).opacity(0.30), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(ZizaiShadow.floatingOpacity),
            radius: ZizaiShadow.floatingRadius,
            y: ZizaiShadow.floatingY
        )
    }
}

struct DockStyleTooltip: View {
    let text: String
    var tailX: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.86))
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .background {
                ZStack {
                    DockTooltipMaterial()
                    Color(nsColor: .textBackgroundColor).opacity(0.76)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(ZizaiShadow.glassHighlightTopOpacity * 0.24),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(DockTooltipShape(tailX: tailX))
            }
            .overlay {
                DockTooltipShape(tailX: tailX)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(ZizaiShadow.glassHighlightTopOpacity),
                                Color.primary.opacity(ZizaiShadow.glassHighlightBottomOpacity),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            }
            .shadow(
                color: .black.opacity(ZizaiShadow.glassOpacity),
                radius: ZizaiShadow.glassRadius,
                y: ZizaiShadow.glassY
            )
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct DockTooltipMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.blendingMode = .withinWindow
        nsView.state = .followsWindowActiveState
    }
}

struct DockTooltipShape: Shape {
    let tailX: CGFloat?

    func path(in rect: CGRect) -> Path {
        let tailHeight: CGFloat = 7
        let tailHalfWidth: CGFloat = 6
        let bubbleBottom = max(rect.minY, rect.maxY - tailHeight)
        let bubbleHeight = max(0, bubbleBottom - rect.minY)
        let cornerRadius = min(bubbleHeight / 2, rect.width / 2)
        let minimumTailCenter = rect.minX + cornerRadius + tailHalfWidth + 3
        let maximumTailCenter = rect.maxX - cornerRadius - tailHalfWidth - 3
        let preferredTailCenter = tailX.map { rect.minX + $0 } ?? rect.midX
        let tailCenter = min(max(preferredTailCenter, minimumTailCenter), maximumTailCenter)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bubbleBottom - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: bubbleBottom),
            control: CGPoint(x: rect.maxX, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: tailCenter + tailHalfWidth, y: bubbleBottom))
        path.addQuadCurve(
            to: CGPoint(x: tailCenter, y: rect.maxY),
            control: CGPoint(x: tailCenter + 3, y: bubbleBottom + 4)
        )
        path.addQuadCurve(
            to: CGPoint(x: tailCenter - tailHalfWidth, y: bubbleBottom),
            control: CGPoint(x: tailCenter - 3, y: bubbleBottom + 4)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: bubbleBottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: bubbleBottom - cornerRadius),
            control: CGPoint(x: rect.minX, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct AppInsertionMarker: View {
    var body: some View {
        Capsule()
            .fill(Palette.accent)
            .frame(width: 4, height: 96)
            .shadow(color: Palette.accent.opacity(0.35), radius: ZizaiRadius.badge)
            .accessibilityHidden(true)
    }
}
