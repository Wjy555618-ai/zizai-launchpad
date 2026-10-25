import CoreGraphics
import Foundation

// Canvas navigation is isolated from catalog and library membership commands.
// Geometry stays in the pure InteractionGeometry/SpatialLayoutEngine services.
extension LauncherStore {
    // MARK: - Canvas navigation

    func updateCanvas(offset: CGSize? = nil, scale: CGFloat? = nil, persist: Bool) {
        var nextState = state
        if let offset {
            nextState.canvasOffsetX = offset.width
            nextState.canvasOffsetY = offset.height
        }
        if let scale {
            nextState.canvasScale = CanvasViewportMetrics.clampedScale(scale)
        }
        guard nextState != state else {
            if persist { save() }
            return
        }
        // Assign the complete value once so @Published emits one coherent
        // invalidation instead of one for each coordinate plus a manual send.
        state = nextState
        if persist { save() }
    }

    func updateCanvasZoomAnchor(_ anchor: CGPoint, in viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        canvasViewport = viewport
        lastCanvasZoomAnchor = CGPoint(
            x: min(max(0, anchor.x), viewport.width),
            y: min(max(0, anchor.y), viewport.height)
        )
    }

    func adjustCanvasZoom(
        by delta: CGFloat,
        around anchor: CGPoint? = nil,
        in viewport: CGSize? = nil
    ) {
        let resolvedViewport = viewport ?? canvasViewport
        guard resolvedViewport.width > 0, resolvedViewport.height > 0 else { return }
        canvasViewport = resolvedViewport

        if let anchor {
            updateCanvasZoomAnchor(anchor, in: resolvedViewport)
        }
        let rememberedAnchor =
            lastCanvasZoomAnchor
            ?? CGPoint(
                x: resolvedViewport.width / 2,
                y: resolvedViewport.height / 2
            )
        let resolvedAnchor = CGPoint(
            x: min(max(0, rememberedAnchor.x), resolvedViewport.width),
            y: min(max(0, rememberedAnchor.y), resolvedViewport.height)
        )
        lastCanvasZoomAnchor = resolvedAnchor
        let oldScale = canvasScale
        let newScale = CanvasViewportMetrics.clampedScale(oldScale + delta)
        guard abs(newScale - oldScale) > 0.000_001 else { return }
        let newOffset = InteractionGeometry.anchoredCanvasOffset(
            currentOffset: canvasOffset,
            oldScale: oldScale,
            newScale: newScale,
            anchor: resolvedAnchor,
            viewport: resolvedViewport
        )
        updateCanvas(offset: newOffset, scale: newScale, persist: true)
    }

    func updateCanvasViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        canvasViewport = size
    }

    func normalizeCanvasViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0, !state.userGroups.isEmpty else { return }
        canvasViewport = size
        let safeRect = CanvasViewportMetrics.safeRect(in: size)
        let currentScale = canvasScale
        let currentOffset = canvasOffset

        let currentTransform = CanvasViewportTransform(scale: currentScale, offset: currentOffset)

        let target =
            state.userGroups.max { lhs, rhs in
                let left = CanvasViewportMetrics.screenFrame(
                    for: SpatialLayoutEngine.frame(for: lhs),
                    transform: currentTransform,
                    in: size
                ).intersection(safeRect)
                let right = CanvasViewportMetrics.screenFrame(
                    for: SpatialLayoutEngine.frame(for: rhs),
                    transform: currentTransform,
                    in: size
                ).intersection(safeRect)
                return max(0, left.width) * max(0, left.height) < max(0, right.width) * max(0, right.height)
            } ?? state.userGroups[0]
        let targetFrame = SpatialLayoutEngine.frame(for: target)
        let currentFrame = CanvasViewportMetrics.screenFrame(
            for: targetFrame,
            transform: currentTransform,
            in: size
        )
        guard !safeRect.contains(currentFrame) else { return }

        let fittingScale = min(
            currentScale,
            safeRect.width / target.size.width,
            safeRect.height / target.size.height
        )
        let scale = min(
            CanvasViewportMetrics.focusedMaximumScale,
            max(CanvasViewportMetrics.focusedMinimumScale, fittingScale)
        )
        state.canvasScale = scale
        state.canvasOffsetX = safeRect.midX - size.width / 2 - target.center.x * scale
        state.canvasOffsetY = safeRect.midY - size.height / 2 - target.center.y * scale
        objectWillChange.send()
        save()
    }

    func focus(on groupID: String, in viewport: CGSize? = nil) {
        guard let group = group(withID: groupID) else { return }
        let viewport = viewport ?? canvasViewport
        let transform = CanvasViewportMetrics.fittedTransform(
            for: SpatialLayoutEngine.frame(for: group),
            in: viewport,
            minimumScale: CanvasViewportMetrics.focusedMinimumScale,
            maximumScale: CanvasViewportMetrics.focusedMaximumScale
        )
        state.canvasScale = transform.scale
        state.canvasOffsetX = transform.offset.width
        state.canvasOffsetY = transform.offset.height
        objectWillChange.send()
        save()
    }

    func resetCanvasView() {
        fitAllGroups()
    }

    func fitAllGroups(in viewport: CGSize? = nil) {
        let viewport = viewport ?? canvasViewport
        guard let first = state.userGroups.first else {
            state.canvasOffsetX = 0
            state.canvasOffsetY = 0
            state.canvasScale = 0.94
            objectWillChange.send()
            save()
            return
        }
        let bounds = state.userGroups.dropFirst().reduce(SpatialLayoutEngine.frame(for: first)) {
            partial,
            group in
            partial.union(SpatialLayoutEngine.frame(for: group))
        }
        let transform = CanvasViewportMetrics.fittedTransform(
            for: bounds,
            in: viewport,
            minimumScale: CanvasViewportMetrics.minimumScale,
            maximumScale: CanvasViewportMetrics.overviewMaximumScale
        )
        state.canvasScale = transform.scale
        state.canvasOffsetX = transform.offset.width
        state.canvasOffsetY = transform.offset.height
        objectWillChange.send()
        save()
    }

}
