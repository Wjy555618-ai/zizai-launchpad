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
