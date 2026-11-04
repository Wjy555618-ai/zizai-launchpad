import AppKit
import SwiftUI

struct SpaceCanvasView: View {
    @EnvironmentObject private var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.primaryLayerIsActive) private var primaryLayerIsActive
    let shouldCaptureInput: () -> Bool
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    let onEditGroup: (UserGroup) -> Void
    let onDeleteGroup: (UserGroup) -> Void

    @State private var viewportSession: CanvasViewportInteractionSession?
    @State private var panOrigin: CanvasViewportTransform?

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 320, proxy.size.height >= 240 {
                let baseline = CanvasViewportTransform(
                    scale: store.canvasScale,
                    offset: store.canvasOffset
                )
                let activeSession = viewportSession
                let presentation = activeSession?.presentation ?? baseline
                let compositorScale = activeSession?.compositorScale ?? 1
                let compositorOffset = activeSession?.compositorOffset ?? .zero
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

                    ZStack {
                        InfiniteGrid(offset: baseline.offset, scale: baseline.scale)

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.selectedGroupID = nil
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                            .gesture(panGesture(baseline: baseline))

                        CanvasWorldLayer(
                            offset: baseline.offset,
                            scale: baseline.scale,
                            viewport: viewport,
                            aliasTarget: $aliasTarget,
                            aliasDraft: $aliasDraft,
                            onEditGroup: onEditGroup,
                            onDeleteGroup: onDeleteGroup
                        )
                    }
                    // The complete world is rendered at the immutable baseline.
                    // Pointer-frequency pan and zoom update only this compositor
                    // transform; Store publication and persistence happen once.
                    .scaleEffect(compositorScale, anchor: .center)
                    .offset(x: compositorOffset.width, y: compositorOffset.height)

                    CanvasInputCapture(
                        shouldCapture: shouldCaptureInput,
                        onScroll: { delta in
                            updateViewportSession(from: baseline) { session in
                                session.translate(by: delta)
                            }
                        },
                        onScrollEnd: commitViewportSession,
                        onZoom: { delta, anchor in
                            updateViewportSession(from: baseline) { session in
                                session.zoom(by: delta, around: anchor, in: viewport)
                            }
                        },
                        onZoomEnd: commitViewportSession,
                        onPointerAnchor: { anchor in
                            store.updateCanvasZoomAnchor(anchor, in: viewport)
                        },
                        onArrow: moveCanvas
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                    CanvasBottomControls(
                        viewport: viewport,
                        displayedScale: presentation.scale
                    )
                    .zIndex(100)
                }
                .clipped()
                .zizaiAnimation(ZizaiMotion.control, value: store.dropTargetGroupID)
                .onAppear { store.normalizeCanvasViewport(viewport) }
                .zizaiOnChange(of: viewport) { size in store.normalizeCanvasViewport(size) }
                .zizaiOnChange(of: primaryLayerIsActive) { isActive in
                    if !isActive { commitViewportSession() }
                }
                .onDisappear { commitViewportSession() }
            } else {
                Color.clear
            }
        }
    }

    private func panGesture(baseline: CanvasViewportTransform) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if panOrigin == nil {
                    if viewportSession == nil {
                        viewportSession = CanvasViewportInteractionSession(baseline: baseline)
                    }
                    panOrigin = viewportSession?.presentation ?? baseline
                }
                guard let origin = panOrigin else { return }
                updateViewportSession(from: baseline) { session in
                    session.setTranslation(value.translation, from: origin)
                }
            }
            .onEnded { _ in
                panOrigin = nil
                commitViewportSession()
            }
    }

    private func updateViewportSession(
        from baseline: CanvasViewportTransform,
        _ update: (inout CanvasViewportInteractionSession) -> Void
    ) {
        var session = viewportSession ?? CanvasViewportInteractionSession(baseline: baseline)
        update(&session)
        guard session != viewportSession else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewportSession = session
        }
    }

    private func commitViewportSession() {
        guard let session = viewportSession else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            store.updateCanvas(
                offset: session.presentation.offset,
                scale: session.presentation.scale,
                persist: true
            )
            viewportSession = nil
            panOrigin = nil
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
