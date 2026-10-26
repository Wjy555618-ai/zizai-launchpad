import AppKit
import SwiftUI

struct SpaceAppIcon: View {
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

struct CanvasBottomControls: View {
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
