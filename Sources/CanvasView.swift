import AppKit
import SwiftUI

struct SpaceCanvasView: View {
    @EnvironmentObject private var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let shouldCaptureInput: () -> Bool
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    let onEditGroup: (UserGroup) -> Void
    let onDeleteGroup: (UserGroup) -> Void

    @State private var panStart: CGSize?
    @State private var panPreview: CGSize = .zero

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 320, proxy.size.height >= 240 {
                let offset = store.canvasOffset
                let scale = store.canvasScale
                let visualOffset = CGSize(
                    width: offset.width + panPreview.width,
                    height: offset.height + panPreview.height
                )
                let viewport = CGSize(
                    width: max(1, proxy.size.width),
                    height: max(1, proxy.size.height)
                )

                ZStack {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("空间视图")
                        .accessibilityIdentifier(ZizaiAccessibilityID.spaceScreen)
                        .allowsHitTesting(false)

                    InfiniteGrid(offset: visualOffset, scale: scale)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selectedGroupID = nil
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        .gesture(panGesture(current: offset))

                    CanvasInputCapture(
                        shouldCapture: shouldCaptureInput,
                        onScroll: { delta in
                            previewCanvasPan(by: delta)
                        },
                        onScrollEnd: commitCanvasPanPreview,
                        onZoom: { delta, anchor in
                            store.adjustCanvasZoom(by: delta, around: anchor, in: viewport)
                        },
                        onPointerAnchor: { anchor in
                            store.updateCanvasZoomAnchor(anchor, in: viewport)
                        },
                        onArrow: moveCanvas
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                    CanvasWorldLayer(
                        offset: offset,
                        scale: scale,
                        viewport: viewport,
                        aliasTarget: $aliasTarget,
                        aliasDraft: $aliasDraft,
                        onEditGroup: onEditGroup,
                        onDeleteGroup: onDeleteGroup
                    )
                    // Pointer movement now changes one compositor transform.
                    // The persistent store, every icon and every glass card
                    // stay untouched until the interaction ends.
                    .offset(x: panPreview.width, y: panPreview.height)

                    CanvasBottomControls(viewport: viewport)
                        .zIndex(100)
                }
                .clipped()
                .zizaiAnimation(ZizaiMotion.control, value: store.dropTargetGroupID)
                .onAppear { store.normalizeCanvasViewport(viewport) }
                .zizaiOnChange(of: viewport) { size in store.normalizeCanvasViewport(size) }
            } else {
                Color.clear
            }
        }
    }

    private func panGesture(current: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panStart == nil { panStart = current }
                setPanPreview(value.translation)
            }
            .onEnded { value in
                guard let start = panStart else { return }
                let committed = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                panStart = nil
                commitCanvasPan(to: committed)
            }
    }

    private func previewCanvasPan(by delta: CGSize) {
        setPanPreview(
            CGSize(
                width: panPreview.width + delta.width,
                height: panPreview.height + delta.height
            )
        )
    }

    private func setPanPreview(_ preview: CGSize) {
        guard
            abs(preview.width - panPreview.width) > 0.01
                || abs(preview.height - panPreview.height) > 0.01
        else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            panPreview = preview
        }
    }

    private func commitCanvasPanPreview() {
        guard panStart == nil,
            abs(panPreview.width) > 0.01 || abs(panPreview.height) > 0.01
        else { return }
        commitCanvasPan(
            to: CGSize(
                width: store.canvasOffset.width + panPreview.width,
                height: store.canvasOffset.height + panPreview.height
            )
        )
    }

    private func commitCanvasPan(to offset: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            panPreview = .zero
            store.updateCanvas(offset: offset, persist: true)
        }
    }

    private func moveCanvas(_ direction: CanvasArrowDirection) {
        let step: CGFloat = 88
        var offset = store.canvasOffset
        switch direction {
        case .left: offset.width += step
        case .right: offset.width -= step
        case .up: offset.height += step
        case .down: offset.height -= step
        }
        zizaiAnimate(ZizaiMotion.spatial, reduceMotion: reduceMotion) {
            store.updateCanvas(offset: offset, persist: true)
        }
    }
}

private struct CanvasWorldLayer: View {
    @EnvironmentObject private var store: LauncherStore
    let offset: CGSize
    let scale: CGFloat
    let viewport: CGSize
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    let onEditGroup: (UserGroup) -> Void
    let onDeleteGroup: (UserGroup) -> Void

    var body: some View {
        let showsHeaderChrome = InteractionGeometry.showsUnifiedGroupHeaders(atScale: scale)

        ForEach(store.groups) { group in
            SpaceGroupCluster(
                groupID: group.id,
                offset: offset,
                scale: scale,
                viewport: viewport,
                showsHeaderChrome: showsHeaderChrome,
                aliasTarget: $aliasTarget,
                aliasDraft: $aliasDraft,
                onEdit: { onEditGroup(group) },
                onDelete: { onDeleteGroup(group) }
            )
        }
    }
}

private struct InfiniteGrid: View {
    let offset: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = max(28, 70 * scale)
            let startX = (offset.width + size.width / 2).truncatingRemainder(dividingBy: spacing)
            let startY = (offset.height + size.height / 2).truncatingRemainder(dividingBy: spacing)
            let color = Color.primary.opacity(0.065)
            for x in stride(from: startX - spacing, through: size.width + spacing, by: spacing) {
                for y in stride(from: startY - spacing, through: size.height + spacing, by: spacing) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

private struct ResizeSnapshot {
    let frame: CGRect
    let appPositions: [String: CGPoint]
}

private struct SpaceGroupCluster: View {
    @EnvironmentObject private var store: LauncherStore
    let groupID: String
    let offset: CGSize
    let scale: CGFloat
    let viewport: CGSize
    let showsHeaderChrome: Bool
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var groupMoveDelta: CGSize = .zero
    @State private var resizePreview: GroupResizePreview?

    var body: some View {
        let isSelected = store.selectedGroupID == groupID
        let layerBase: Double = isSelected ? 10 : 1

        // Keep this wrapper layout-transparent. A viewport-sized wrapper for
        // every group creates overlapping invisible hit regions; whichever
        // group is on top then starves the other cards and the canvas of mouse
        // events. The children below already use viewport coordinates, so they
        // can participate directly in the parent canvas ZStack.
        Group {
            GroupCanvasCard(
                groupID: groupID,
                offset: offset,
                scale: scale,
                viewport: viewport,
                showsHeaderChrome: showsHeaderChrome,
                isDropTarget: store.dropTargetGroupID == groupID,
                isSelected: isSelected,
                groupMoveDelta: $groupMoveDelta,
                resizePreview: $resizePreview,
                onSelect: { store.selectedGroupID = groupID },
                onEdit: onEdit,
                onDelete: onDelete
            )
            .zIndex(layerBase)

            ForEach(store.apps(in: groupID)) { app in
                SpaceAppIcon(
                    app: app,
                    offset: offset,
                    scale: scale,
                    viewport: viewport,
                    resizePreview: resizePreview,
                    aliasTarget: $aliasTarget,
                    aliasDraft: $aliasDraft
                )
                .zIndex(layerBase + 1)
            }

            if isSelected {
                GroupResizeControls(
                    groupID: groupID,
                    offset: offset,
                    scale: scale,
                    viewport: viewport,
                    resizePreview: $resizePreview
                )
                .zIndex(layerBase + 2)
            }
        }
        // Move the complete group as one render-layer transform. Previously
        // every icon recomputed its world position on every pointer event.
        .offset(
            x: groupMoveDelta.width * scale,
            y: groupMoveDelta.height * scale
        )
    }
}

private struct GroupCanvasCard: View {
    @EnvironmentObject private var store: LauncherStore
    @Environment(\.colorScheme) private var colorScheme
    let groupID: String
    let offset: CGSize
    let scale: CGFloat
    let viewport: CGSize
    let showsHeaderChrome: Bool
    let isDropTarget: Bool
    let isSelected: Bool
    @Binding var groupMoveDelta: CGSize
    @Binding var resizePreview: GroupResizePreview?
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var moveOrigin: CGPoint?
    @State private var appOrigins: [String: CGPoint] = [:]

    var body: some View {
        if let group = store.group(withID: groupID) {
            let storedFrame = CGRect(
                x: group.center.x - group.size.width / 2,
                y: group.center.y - group.size.height / 2,
                width: group.size.width,
                height: group.size.height
            )
            let visualFrame =
                resizePreview?.groupID == group.id
                ? resizePreview?.frame ?? storedFrame
                : storedFrame
            let center = screenPoint(CGPoint(x: visualFrame.midX, y: visualFrame.midY))
            let scaledSize = CGSize(
                width: max(1, visualFrame.width * scale),
                height: max(1, visualFrame.height * scale)
            )
            let tint = Palette.tint(for: group.tint)
            let cardRadius = ZizaiRadius.canvasCard(scale: scale)

            ZStack {
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                            .fill(tint.opacity(isDropTarget ? 0.12 : ZizaiOpacity.quietTintFill))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                            .stroke(
                                isDropTarget
                                    ? tint.opacity(0.90)
                                    : (isSelected
                                        ? Palette.selectedCardOutline(for: colorScheme)
                                        : tint.opacity(isHovering ? 0.30 : ZizaiOpacity.quietBorder)),
                                lineWidth: isDropTarget ? 2.5 : (isSelected ? 1.5 : 1)
                            )
                    }
                    .shadow(
                        color: .black.opacity(
                            isDropTarget
                                ? ZizaiShadow.dropTargetOpacity
                                : (isSelected ? ZizaiShadow.selectedCardOpacity : ZizaiShadow.cardOpacity)
                        ),
                        radius: isSelected ? ZizaiShadow.selectedCardRadius : ZizaiShadow.cardRadius,
                        y: ZizaiShadow.cardY
                    )
                    .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                    .onTapGesture { onSelect() }
                    .simultaneousGesture(moveGesture(group: group))

                VStack(spacing: 0) {
                    if showsHeaderChrome {
                        HStack(spacing: 10) {
                            GroupHeaderTitle(
                                title: group.name,
                                detail: "\(store.appCount(in: group.id)) 个应用 · \(group.subtitle)",
                                tint: tint,
                                identifier: ZizaiAccessibilityID.groupDragHandle(group.id)
                            )

                            Spacer()

                            // Reserve the menu's visual space. The actual menu
                            // remains interactive above the card background.
                            Color.clear.frame(width: 28, height: 28)
                        }
                        .padding(.horizontal, max(16, 22 * scale))
                        .padding(.top, max(14, 18 * scale))
                        .padding(.bottom, 12)
                    }

                    Spacer()
                }

                if showsHeaderChrome {
                    Menu {
                        groupActions(for: group)
                    } label: {
                        GroupMoreMenuIcon()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .position(
                        x: scaledSize.width - max(16, 22 * scale) - 14,
                        y: max(14, 18 * scale) + 14
                    )
                }
            }
            .frame(width: scaledSize.width, height: scaledSize.height)
            // Attach every interactive modifier while this view still has the
            // real card bounds. If `position` comes first, SwiftUI exposes the
            // positioned layout proxy (the canvas proposal) to hit testing and
            // an off-screen card can steal input from the entire workspace.
            .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            .contextMenu {
                groupActions(for: group)
            }
            .onHover { isHovering = $0 }
            .zizaiAnimation(ZizaiMotion.control, value: isDropTarget)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(ZizaiAccessibilityID.groupCard(group.id))
            .accessibilityLabel("\(group.name)，\(store.appCount(in: group.id)) 个应用")
            .accessibilityHint(
                "可打开操作菜单移动、调整大小或整理分组；指针用户也可拖动卡片和边缘"
            )
            .accessibilityAction(named: Text("向左移动")) {
                store.nudgeGroup(id: group.id, direction: .left)
            }
            .accessibilityAction(named: Text("向右移动")) {
                store.nudgeGroup(id: group.id, direction: .right)
            }
            .accessibilityAction(named: Text("向上移动")) {
                store.nudgeGroup(id: group.id, direction: .up)
            }
            .accessibilityAction(named: Text("向下移动")) {
                store.nudgeGroup(id: group.id, direction: .down)
            }
            .accessibilityAction(named: Text("增大分组")) {
                store.adjustGroupSize(id: group.id, by: 40)
            }
            .accessibilityAction(named: Text("缩小分组")) {
                store.adjustGroupSize(id: group.id, by: -40)
            }
            .accessibilityAction(named: Text("整理应用")) {
                store.arrangeApps(in: group.id)
            }
            .accessibilityAction(named: Text("适配内容")) {
                store.fitGroupToContent(id: group.id)
            }
            .position(center)
        }
    }

    @ViewBuilder
    private func groupActions(for group: UserGroup) -> some View {
        Button("重命名与颜色", systemImage: "pencil") { onEdit() }
        Button("整理应用", systemImage: "square.grid.3x3") {
            store.arrangeApps(in: group.id)
        }
        Button("适配内容", systemImage: "arrow.up.left.and.arrow.down.right") {
            store.fitGroupToContent(id: group.id)
        }
        Button("在分组视图中查看", systemImage: "square.grid.2x2") {
            store.requestLayoutMode(.groups)
        }
        Divider()
        Button("删除分组", systemImage: "trash", role: .destructive) { onDelete() }
            .disabled(store.groups.count <= 1)
    }

    private func moveGesture(group: UserGroup) -> some Gesture {
        // Use the global coordinate space because this view moves with the
        // pointer. A local gesture would continuously move its own coordinate
        // origin and make the reported translation jump or oscillate.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if moveOrigin == nil {
                    onSelect()
                    moveOrigin = group.center.point
                    appOrigins = Dictionary(
                        uniqueKeysWithValues:
                            store.assignedApps(in: group.id).map { ($0.id, store.position(for: $0)) }
                    )
                }
                // Preview the pointer translation directly. Collision
                // resolution is intentionally deferred until release so it
                // cannot snap between candidate positions on every frame.
                groupMoveDelta = InteractionGeometry.worldTranslation(
                    fromScreen: value.translation,
                    scale: scale
                )
            }
            .onEnded { _ in
                guard let originalCenter = moveOrigin else { return }
                let originalPositions = appOrigins
                let committedDelta = groupMoveDelta
                moveOrigin = nil
                appOrigins = [:]
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    store.commitGroupMove(
                        id: group.id,
                        originalCenter: originalCenter,
                        originalAppPositions: originalPositions,
                        delta: committedDelta
                    )
                    groupMoveDelta = .zero
                }
            }
    }

    private func screenPoint(_ world: CGPoint) -> CGPoint {
        CGPoint(
            x: viewport.width / 2 + offset.width + world.x * scale,
            y: viewport.height / 2 + offset.height + world.y * scale
        )
    }
}

private struct GroupResizeControls: View {
    @EnvironmentObject private var store: LauncherStore
    let groupID: String
    let offset: CGSize
    let scale: CGFloat
    let viewport: CGSize
    @Binding var resizePreview: GroupResizePreview?

    @State private var hoveredHandle: ResizeHandle?
    @State private var activeHandle: ResizeHandle?
    @State private var resizeSnapshot: ResizeSnapshot?

    var body: some View {
        if let group = store.group(withID: groupID) {
            let storedFrame = CGRect(
                x: group.center.x - group.size.width / 2,
                y: group.center.y - group.size.height / 2,
                width: group.size.width,
                height: group.size.height
            )
            let visualFrame =
                resizePreview?.groupID == group.id
                ? resizePreview?.frame ?? storedFrame
                : storedFrame
            let center = screenPoint(CGPoint(x: visualFrame.midX, y: visualFrame.midY))
            let scaledSize = CGSize(
                width: max(1, visualFrame.width * scale),
                height: max(1, visualFrame.height * scale)
            )

            // Emit only the eight edge targets into the parent canvas. A
            // card-sized GeometryReader here becomes a transparent overlay
            // after selection and can swallow every pointer event inside the
            // card even though only its edges are meant to be interactive.
            Group {
                ForEach(ResizeHandle.allCases, id: \.self) { handle in
                    resizeZone(
                        handle,
                        cardSize: scaledSize,
                        cardCenter: center,
                        group: group
                    )
                }
            }
        }
    }

    private func resizeZone(
        _ handle: ResizeHandle,
        cardSize: CGSize,
        cardCenter: CGPoint,
        group: UserGroup
    ) -> some View {
        let geometry = zoneGeometry(handle, size: cardSize)
        let absoluteCenter = CGPoint(
            x: cardCenter.x - cardSize.width / 2 + geometry.origin.x,
            y: cardCenter.y - cardSize.height / 2 + geometry.origin.y
        )
        return Color.clear
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            // Gesture and hover must be attached before absolute positioning.
            // Otherwise each invisible edge target can inherit the full canvas
            // proposal and block every click and drag after a card is selected.
            .gesture(resizeGesture(handle: handle, group: group))
            .onHover { hovering in
                if hovering {
                    hoveredHandle = handle
                    setResizeCursor(for: activeHandle ?? handle)
                } else if hoveredHandle == handle {
                    hoveredHandle = nil
                    if let activeHandle {
                        setResizeCursor(for: activeHandle)
                    } else {
                        NSCursor.arrow.set()
                    }
                }
            }
            .help("拖动调整“\(group.name)”的大小")
            .accessibilityLabel("从\(handle.accessibilityName)调整“\(group.name)”")
            .accessibilityHint("拖动调整大小；辅助功能用户可以上下调整")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: store.adjustGroupSize(id: group.id, by: 40)
                case .decrement: store.adjustGroupSize(id: group.id, by: -40)
                @unknown default: break
                }
            }
            .position(absoluteCenter)
    }

    private func zoneGeometry(_ handle: ResizeHandle, size: CGSize) -> (origin: CGPoint, size: CGSize) {
        // Keep the resize affordance visually invisible, like a native macOS
        // window edge, while retaining a forgiving pointer target.
        let edgeHit: CGFloat = 14
        let cornerHit: CGFloat = 24
        switch handle {
        case .top:
            return (
                CGPoint(x: size.width / 2, y: 0), CGSize(width: max(1, size.width - cornerHit * 2), height: edgeHit)
            )
        case .bottom:
            return (
                CGPoint(x: size.width / 2, y: size.height),
                CGSize(width: max(1, size.width - cornerHit * 2), height: edgeHit)
            )
        case .left:
            return (
                CGPoint(x: 0, y: size.height / 2), CGSize(width: edgeHit, height: max(1, size.height - cornerHit * 2))
            )
        case .right:
            return (
                CGPoint(x: size.width, y: size.height / 2),
                CGSize(width: edgeHit, height: max(1, size.height - cornerHit * 2))
            )
        case .topLeft:
            return (CGPoint(x: 0, y: 0), CGSize(width: cornerHit, height: cornerHit))
        case .topRight:
            return (CGPoint(x: size.width, y: 0), CGSize(width: cornerHit, height: cornerHit))
        case .bottomLeft:
            return (CGPoint(x: 0, y: size.height), CGSize(width: cornerHit, height: cornerHit))
        case .bottomRight:
            return (CGPoint(x: size.width, y: size.height), CGSize(width: cornerHit, height: cornerHit))
        }
    }

    private func resizeGesture(handle: ResizeHandle, group: UserGroup) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if resizeSnapshot == nil {
                    activeHandle = handle
                    setResizeCursor(for: handle)
                    let frame = CGRect(
                        x: group.center.x - group.size.width / 2,
                        y: group.center.y - group.size.height / 2,
                        width: group.size.width,
                        height: group.size.height
                    )
                    resizeSnapshot = ResizeSnapshot(
                        frame: frame,
                        appPositions: Dictionary(
                            uniqueKeysWithValues:
                                store.assignedApps(in: group.id).map { ($0.id, store.position(for: $0)) }
                        )
                    )
                }
                guard let snapshot = resizeSnapshot else { return }
                let translation = CGSize(
                    width: value.translation.width / scale,
                    height: value.translation.height / scale
                )
                if let resolved = store.resolvedGroupResize(
                    id: group.id,
                    proposedFrame: handle.resizedFrame(from: snapshot.frame, translation: translation),
                    originalFrame: snapshot.frame
                ) {
                    resizePreview = resolved
                }
            }
            .onEnded { _ in
                let snapshot = resizeSnapshot
                resizeSnapshot = nil
                activeHandle = nil
                if hoveredHandle == handle {
                    setResizeCursor(for: handle)
                } else {
                    NSCursor.arrow.set()
                }
                guard let snapshot,
                    let committedPreview = resizePreview
                else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    store.commitGroupResize(
                        id: group.id,
                        originalFrame: snapshot.frame,
                        originalAppPositions: snapshot.appPositions,
                        preview: committedPreview
                    )
                    resizePreview = nil
                }
            }
    }

    private func setResizeCursor(for handle: ResizeHandle) {
        if #available(macOS 15.0, *) {
            NSCursor.frameResize(position: handle.cursorPosition, directions: .all).set()
        } else {
            switch handle {
            case .left, .right:
                NSCursor.resizeLeftRight.set()
            case .top, .bottom:
                NSCursor.resizeUpDown.set()
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                NSCursor.crosshair.set()
            }
        }
    }

    private func screenPoint(_ world: CGPoint) -> CGPoint {
        CGPoint(
            x: viewport.width / 2 + offset.width + world.x * scale,
            y: viewport.height / 2 + offset.height + world.y * scale
        )
    }
}

private struct SpaceAppIcon: View {
    @EnvironmentObject private var store: LauncherStore
    let app: AppInfo
    let offset: CGSize
    let scale: CGFloat
    let viewport: CGSize
    let resizePreview: GroupResizePreview?
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String

    @State private var dragOrigin: CGPoint?
    @State private var dragPreview: AppMovePreview?
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        Button {
            if !isDragging { store.launch(app) }
        } label: {
            AppIconContent(
                app: app,
                size: 74,
                showName: scale >= 0.58,
                layoutScale: scale
            )
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .scaleEffect(isDragging ? 1.08 : (isHovering ? 1.035 : 1))
        .shadow(
            color: .black.opacity(isDragging ? ZizaiShadow.floatingOpacity : 0),
            radius: ZizaiShadow.floatingRadius,
            y: ZizaiShadow.floatingY
        )
        .zizaiAnimation(ZizaiMotion.hover, value: isHovering)
        .zizaiAnimation(ZizaiMotion.control, value: isDragging)
        // Keep hit testing on the icon's intrinsic bounds. Interactive
        // modifiers after `position` can turn an off-screen icon into an
        // invisible canvas-sized input layer.
        .onHover { isHovering = $0 }
        .simultaneousGesture(dragGesture)
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
            Button("从空间和分组中隐藏", systemImage: "eye.slash") {
                store.setHidden(true, for: app)
            }
            Divider()
            Button("在访达中显示", systemImage: "folder") { store.revealInFinder(app) }
            Button("打开应用", systemImage: "arrow.up.forward.app") { store.launch(app) }
        }
        .accessibilityLabel(store.displayName(for: app))
        .accessibilityValue(store.instanceLabel(for: app) ?? app.purpose)
        .accessibilityHint("单击打开；操作菜单可以移动分组、隐藏或在访达中显示")
        .accessibilityIdentifier(ZizaiAccessibilityID.appTile(app.id))
        .accessibilityAction(named: Text("移到上一个分组")) {
            store.moveAppToAdjacentGroup(app, offset: -1)
        }
        .accessibilityAction(named: Text("移到下一个分组")) {
            store.moveAppToAdjacentGroup(app, offset: 1)
        }
        .accessibilityAction(named: Text("从启动台隐藏")) {
            store.setHidden(true, for: app)
        }
        .accessibilityAction(named: Text("在访达中显示")) {
            store.revealInFinder(app)
        }
        .accessibilityHidden(!isAccessibilityVisible)
        .position(screenPoint(previewedPosition))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = store.position(for: app)
                    isDragging = true
                }
                guard let origin = dragOrigin else { return }
                let delta = InteractionGeometry.worldTranslation(
                    fromScreen: value.translation,
                    scale: scale
                )
                let point = CGPoint(x: origin.x + delta.width, y: origin.y + delta.height)
                let preview = store.interactiveAppMovePreview(app, to: point)
                dragPreview = preview
                store.updateDropTarget(preview?.targetGroupID)
            }
            .onEnded { _ in
                let committedPreview = dragPreview
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if let committedPreview,
                        let resolvedPreview = store.resolvedAppMovePreview(
                            app,
                            to: committedPreview.requestedPoint
                        )
                    {
                        store.commitAppMove(app, preview: resolvedPreview)
                    } else {
                        store.updateDropTarget(nil)
                    }
                    dragPreview = nil
                    dragOrigin = nil
                    DispatchQueue.main.async {
                        isDragging = false
                    }
                }
            }
    }

    private func screenPoint(_ world: CGPoint) -> CGPoint {
        CGPoint(
            x: viewport.width / 2 + offset.width + world.x * scale,
            y: viewport.height / 2 + offset.height + world.y * scale
        )
    }

    private var previewedPosition: CGPoint {
        let point = store.position(for: app)
        if let preview = dragPreview,
            preview.appID == app.id
        {
            return preview.resolvedPoint ?? point
        }
        if let preview = resizePreview,
            let resizedPosition = preview.appPositions[app.id]
        {
            return resizedPosition
        }
        return point
    }

    private var isAccessibilityVisible: Bool {
        InteractionGeometry.isVisibleInViewport(
            center: screenPoint(previewedPosition),
            viewport: viewport,
            margin: 72
        )
    }
}

private struct CanvasBottomControls: View {
    @EnvironmentObject private var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let viewport: CGSize

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    var body: some View {
        let groupStripWidth = min(680, max(48, measuredGroupStripWidth))
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.groups) { group in
                            Button {
                                zizaiAnimate(ZizaiMotion.spatial, reduceMotion: reduceMotion) {
                                    store.focus(on: group.id, in: viewport)
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(Palette.tint(for: group.tint))
                                        .frame(width: 8, height: 8)
                                    Text(group.name)
                                        .lineLimit(1)
                                }
                                .font(ZizaiTypography.secondaryMedium)
                                .padding(.horizontal, 11)
                                .frame(height: ZizaiControlMetrics.canvasBarItemHeight)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Capsule())
                            .help("定位到“\(group.name)”")
                        }
                    }
                }
                .frame(width: groupStripWidth)
                .padding(4)
                .zizaiGlassCapsule(interactive: true)

                Spacer()
                HStack(spacing: 2) {
                    Button {
                        zizaiAnimate(ZizaiMotion.spatial, reduceMotion: reduceMotion) {
                            store.adjustCanvasZoom(by: -0.1)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(
                                width: ZizaiControlMetrics.canvasBarButtonSize,
                                height: ZizaiControlMetrics.canvasBarButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("缩小")
                    .accessibilityIdentifier(ZizaiAccessibilityID.canvasZoomOut)

                    Text("\(Int(store.canvasScale * 100))%")
                        .font(ZizaiTypography.captionMedium)
                        .monospacedDigit()
                        .frame(width: 44)
                        .accessibilityIdentifier(ZizaiAccessibilityID.canvasZoomValue)
                        .accessibilityValue("\(Int(store.canvasScale * 100))")

                    Button {
                        zizaiAnimate(ZizaiMotion.spatial, reduceMotion: reduceMotion) {
                            store.adjustCanvasZoom(by: 0.1)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(
                                width: ZizaiControlMetrics.canvasBarButtonSize,
                                height: ZizaiControlMetrics.canvasBarButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("放大")
                    .accessibilityIdentifier(ZizaiAccessibilityID.canvasZoomIn)

                    Divider().frame(height: 16)

                    Button {
                        zizaiAnimate(ZizaiMotion.spatial, reduceMotion: reduceMotion) {
                            store.fitAllGroups(in: viewport)
                        }
                    } label: {
                        Image(systemName: "scope")
                            .frame(
                                width: ZizaiControlMetrics.canvasBarButtonSize,
                                height: ZizaiControlMetrics.canvasBarButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("适合全部内容")
                    .help("在可用区域内显示全部分组")
                    .accessibilityIdentifier(ZizaiAccessibilityID.canvasFit)
                }
                .padding(4)
                .zizaiGlassCapsule(interactive: true)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private var measuredGroupStripWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let buttonWidths = store.groups.map { group in
            let textWidth = (group.name as NSString).size(withAttributes: [.font: font]).width
            return ceil(textWidth) + 8 + 7 + 22
        }
        let spacing = CGFloat(max(0, buttonWidths.count - 1)) * 4
        return buttonWidths.reduce(0, +) + spacing + 8
    }
}
