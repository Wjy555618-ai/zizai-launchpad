import CoreGraphics
import Foundation

// Application placement transactions mutate the persisted aggregate atomically. Every public
// command flows through the store's shared commit/undo/persistence mechanism;
// pointer, keyboard and accessibility paths therefore cannot diverge.
extension LauncherStore {
    /// Resolve only the geometry required to keep the dragged icon under the
    /// pointer. Collision search and swap resolution are deliberately deferred
    /// until mouse-up, instead of sorting thousands of candidate points during
    /// every high-frequency drag event.
    // MARK: - Application movement

    func interactiveAppMovePreview(_ app: AppInfo, to point: CGPoint) -> AppMovePreview? {
        guard let target = SpatialLayoutEngine.nearestGroup(to: point, in: state.userGroups) else {
            return nil
        }
        return AppMovePreview(
            appID: app.id,
            targetGroupID: target.id,
            requestedPoint: point,
            resolvedPoint: SpatialLayoutEngine.clamped(
                point,
                inside: SpatialLayoutEngine.appCenterRect(
                    for: SpatialLayoutEngine.frame(for: target)
                )
            ),
            displacedAppID: nil,
            displacedAppPosition: nil
        )
    }

    func resolvedAppMovePreview(_ app: AppInfo, to point: CGPoint) -> AppMovePreview? {
        guard let target = SpatialLayoutEngine.nearestGroup(to: point, in: state.userGroups) else {
            return nil
        }

        let oldGroupID = state.appGroupIDs[app.id] ?? app.group.stableID
        let clamped = SpatialLayoutEngine.clamped(
            point,
            inside: SpatialLayoutEngine.appCenterRect(
                for: SpatialLayoutEngine.frame(for: target)
            )
        )
        let collidingApps = assignedApps(in: target.id, includeHidden: false).filter { candidate in
            guard candidate.id != app.id else { return false }
            let other = position(for: candidate)
            return abs(clamped.x - other.x) < InteractionGeometry.appCellWidth
                && abs(clamped.y - other.y) < InteractionGeometry.appCellHeight
        }

        if oldGroupID == target.id, collidingApps.count == 1, let displaced = collidingApps.first {
            return AppMovePreview(
                appID: app.id,
                targetGroupID: target.id,
                requestedPoint: point,
                resolvedPoint: position(for: displaced),
                displacedAppID: displaced.id,
                displacedAppPosition: position(for: app)
            )
        }

        let resolved = closestAvailablePosition(for: app.id, proposed: point, in: target)
        return AppMovePreview(
            appID: app.id,
            targetGroupID: target.id,
            requestedPoint: point,
            resolvedPoint: resolved,
            displacedAppID: nil,
            displacedAppPosition: nil
        )
    }

    func updateDropTarget(_ groupID: String?) {
        guard dropTargetGroupID != groupID else { return }
        dropTargetGroupID = groupID
    }

    func commitAppMove(_ app: AppInfo, preview: AppMovePreview) {
        guard preview.appID == app.id else { return }
        let previousState = state
        let oldGroupID = state.appGroupIDs[app.id] ?? app.group.stableID
        if oldGroupID == preview.targetGroupID,
            let resolvedPoint = preview.resolvedPoint
        {
            state.positions[app.id] = StoredPoint(resolvedPoint)
            if let displacedAppID = preview.displacedAppID,
                let displacedPosition = preview.displacedAppPosition
            {
                state.positions[displacedAppID] = StoredPoint(displacedPosition)
            }
            repairSpatialState(affectedGroupIDs: [preview.targetGroupID])
            dropTargetGroupID = nil
            commitStateMutation(from: previousState, message: "位置已保存")
            return
        }
        finishMoving(app, to: preview.requestedPoint, targetGroupID: preview.targetGroupID)
    }

    func finishMoving(_ app: AppInfo, to point: CGPoint) {
        finishMoving(app, to: point, targetGroupID: nil)
    }

    private func finishMoving(_ app: AppInfo, to point: CGPoint, targetGroupID: String?) {
        let previousState = state
        let oldGroupID = state.appGroupIDs[app.id] ?? app.group.stableID
        guard
            let target = targetGroupID.flatMap(group(withID:))
                ?? SpatialLayoutEngine.nearestGroup(to: point, in: state.userGroups)
        else {
            dropTargetGroupID = nil
            return
        }

        if oldGroupID != target.id {
            for id in Array(state.groupAppOrder.keys) {
                state.groupAppOrder[id]?.removeAll(where: { $0 == app.id })
            }
            state.groupAppOrder[target.id, default: []].append(app.id)
        }
        state.appGroupIDs[app.id] = target.id
        LauncherStateReconciler.prepareGroupForPlacement(
            target.id,
            state: &state,
            apps: apps
        )
        guard let resolvedTarget = group(withID: target.id) else {
            dropTargetGroupID = nil
            return
        }
        let finalPoint = resolvedFreePosition(for: app.id, proposed: point, in: resolvedTarget)
        state.positions[app.id] = StoredPoint(finalPoint)
        repairSpatialState(affectedGroupIDs: [target.id, oldGroupID])
        dropTargetGroupID = nil
        let changedGroup = oldGroupID != target.id
        commitStateMutation(
            from: previousState,
            message: changedGroup ? "已放入“\(target.name)”" : "位置已保存"
        )
    }

    func move(
        _ app: AppInfo,
        toGroupID groupID: String,
        relativeToAppID: String? = nil,
        placeAfter: Bool = false
    ) {
        let order = (state.groupAppOrder[groupID] ?? []).filter { $0 != app.id }
        let insertionIndex: Int
        if let relativeToAppID,
            let relativeIndex = order.firstIndex(of: relativeToAppID)
        {
            insertionIndex = relativeIndex + (placeAfter ? 1 : 0)
        } else {
            insertionIndex = order.count
        }
        move(app, toGroupID: groupID, insertionIndex: insertionIndex)
    }

    func move(_ app: AppInfo, toGroupID groupID: String, insertionIndex: Int) {
        let previousState = state
        let oldGroupID = state.appGroupIDs[app.id] ?? app.group.stableID
        guard let destinationGroup = group(withID: groupID) else { return }

        let currentTargetOrder = state.groupAppOrder[groupID] ?? []
        var targetOrder = currentTargetOrder.filter { $0 != app.id }
        let visibleTargetIDs = apps(in: groupID)
            .map(\.id)
            .filter { $0 != app.id }
        let visibleInsertionIndex = min(max(0, insertionIndex), visibleTargetIDs.count)
        let fullInsertionIndex: Int
        if visibleInsertionIndex < visibleTargetIDs.count,
            let nextVisibleIndex = targetOrder.firstIndex(of: visibleTargetIDs[visibleInsertionIndex])
        {
            fullInsertionIndex = nextVisibleIndex
        } else if let lastVisibleID = visibleTargetIDs.last,
            let lastVisibleIndex = targetOrder.firstIndex(of: lastVisibleID)
        {
            fullInsertionIndex = lastVisibleIndex + 1
        } else {
            fullInsertionIndex = 0
        }
        targetOrder.insert(app.id, at: min(fullInsertionIndex, targetOrder.count))

        guard
            oldGroupID != groupID
                || targetOrder != currentTargetOrder
                || state.appGroupIDs[app.id] != groupID
        else { return }

        for id in Array(state.groupAppOrder.keys) {
            state.groupAppOrder[id]?.removeAll(where: { $0 == app.id })
        }
        state.groupAppOrder[groupID] = targetOrder
        state.appGroupIDs[app.id] = groupID
        LauncherStateReconciler.prepareGroupForPlacement(
            groupID,
            state: &state,
            apps: apps
        )
        if oldGroupID != groupID {
            if let updatedGroup = group(withID: groupID) {
                state.positions[app.id] = StoredPoint(
                    resolvedFreePosition(
                        for: app.id,
                        proposed: updatedGroup.center.point,
                        in: updatedGroup
                    )
                )
            }
        }
        repairSpatialState(affectedGroupIDs: [groupID, oldGroupID])
        let message = oldGroupID == groupID ? "“\(displayName(for: app))”的顺序已更新" : "已放入“\(destinationGroup.name)”"
        commitStateMutation(from: previousState, message: message)
    }

    func moveGroup(id: String, relativeTo targetID: String, placeAfter: Bool = false) {
        guard id != targetID,
            let oldIndex = state.userGroups.firstIndex(where: { $0.id == id }),
            let targetIndex = state.userGroups.firstIndex(where: { $0.id == targetID })
        else { return }
        let previousState = state
        let group = state.userGroups.remove(at: oldIndex)
        var adjustedTarget = oldIndex < targetIndex ? targetIndex - 1 : targetIndex
        if placeAfter { adjustedTarget += 1 }
        state.userGroups.insert(group, at: min(state.userGroups.count, max(0, adjustedTarget)))
        commitStateMutation(from: previousState, message: "分组顺序已更新")
    }

    func moveGroup(id: String, toInsertionIndex insertionIndex: Int) {
        guard state.userGroups.contains(where: { $0.id == id }) else { return }
        let previousState = state
        let previous = state.userGroups
        let updatedIDs = InteractionGeometry.reorderedIDs(
            previous.map(\.id),
            movingID: id,
            toInsertionIndex: insertionIndex
        )
        guard updatedIDs != previous.map(\.id) else { return }
        let groupsByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        state.userGroups = updatedIDs.compactMap { groupsByID[$0] }
        guard let group = groupsByID[id] else { return }
        commitStateMutation(from: previousState, message: "“\(group.name)”的顺序已更新")
    }

    func moveGroup(id: String, by offset: Int) {
        guard offset != 0,
            let oldIndex = state.userGroups.firstIndex(where: { $0.id == id })
        else { return }
        let newIndex = min(max(0, oldIndex + offset), state.userGroups.count - 1)
        guard newIndex != oldIndex else { return }
        let previousState = state
        let group = state.userGroups.remove(at: oldIndex)
        state.userGroups.insert(group, at: newIndex)
        commitStateMutation(from: previousState, message: "“\(group.name)”的顺序已更新")
    }

    func moveApp(_ app: AppInfo, inGroupID groupID: String, by offset: Int) {
        guard offset != 0 else { return }
        var order = state.groupAppOrder[groupID] ?? []
        guard let oldIndex = order.firstIndex(of: app.id) else { return }
        let newIndex = min(max(0, oldIndex + offset), order.count - 1)
        guard newIndex != oldIndex else { return }
        let previousState = state
        order.remove(at: oldIndex)
        order.insert(app.id, at: newIndex)
        state.groupAppOrder[groupID] = order
        commitStateMutation(
            from: previousState,
            message: "“\(displayName(for: app))”的顺序已更新"
        )
    }

    /// VoiceOver and keyboard users receive the same cross-group transaction
    /// as pointer dragging: membership, layout repair, persistence, and undo
    /// are committed by the existing `move` command rather than a parallel
    /// accessibility-only code path.
    func moveAppToAdjacentGroup(_ app: AppInfo, offset: Int) {
        guard offset != 0,
            let currentGroup = group(for: app),
            let currentIndex = state.userGroups.firstIndex(where: { $0.id == currentGroup.id })
        else { return }
        let destinationIndex = min(
            max(0, currentIndex + offset),
            state.userGroups.count - 1
        )
        guard destinationIndex != currentIndex else {
            announce(offset < 0 ? "已经是第一个分组" : "已经是最后一个分组")
            return
        }
        let destination = state.userGroups[destinationIndex]
        move(
            app,
            toGroupID: destination.id,
            insertionIndex: apps(in: destination.id).count
        )
    }

    func arrangeApps(in groupID: String) {
        guard let group = group(withID: groupID) else { return }
        let members = orderedAssignedApps(in: groupID, includeHidden: false)
        let previousState = state
        let arranged = SpatialLayoutEngine.gridPositions(
            for: members.map(\.id),
            inside: InteractionGeometry.contentRect(
                for: SpatialLayoutEngine.frame(for: group)
            )
        )
        for (appID, point) in arranged {
            state.positions[appID] = StoredPoint(point)
        }
        commitStateMutation(from: previousState, message: "“\(group.name)”已按网格整理")
    }

    private func resolvedFreePosition(
        for appID: String,
        proposed: CGPoint,
        in group: UserGroup
    ) -> CGPoint {
        if let available = closestAvailablePosition(for: appID, proposed: proposed, in: group) {
            return available
        }

        let frame = SpatialLayoutEngine.frame(for: group)
        let centerRect = SpatialLayoutEngine.appCenterRect(for: frame)
        let clamped = SpatialLayoutEngine.clamped(proposed, inside: centerRect)

        // Capacity is expanded before this path. If an old corrupted layout
        // still leaves no legal free point, rebuild only this group on its
        // established grid. Never persist a collision as a fallback.
        let orderedIDs = orderedAssignedApps(in: group.id, includeHidden: false).map(\.id)
        let repaired = SpatialLayoutEngine.gridPositions(
            for: orderedIDs,
            inside: InteractionGeometry.contentRect(for: frame)
        )
        for (memberID, point) in repaired where memberID != appID {
            state.positions[memberID] = StoredPoint(point)
        }
        return repaired[appID] ?? clamped
    }

    private func closestAvailablePosition(
        for appID: String,
        proposed: CGPoint,
        in group: UserGroup
    ) -> CGPoint? {
        let rect = SpatialLayoutEngine.appCenterRect(
            for: SpatialLayoutEngine.frame(for: group)
        )
        let occupied = assignedApps(in: group.id, includeHidden: false)
            .filter { $0.id != appID }
            .map { position(for: $0) }
        return SpatialLayoutEngine.closestAvailablePosition(
            proposed: proposed,
            inside: rect,
            occupied: occupied
        )
    }

    func repairSpatialState(affectedGroupIDs: [String]? = nil) {
        let displayNamesByID = Dictionary(
            uniqueKeysWithValues: apps.map { ($0.id, displayName(for: $0)) }
        )
        LauncherStateReconciler.repairSpatialIntegrity(
            state: &state,
            apps: apps,
            displayNamesByID: displayNamesByID,
            affectedGroupIDs: affectedGroupIDs.map(Set.init)
        )
    }
}
