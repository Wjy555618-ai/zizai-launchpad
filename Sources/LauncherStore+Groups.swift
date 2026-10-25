import CoreGraphics
import Foundation

// Group lifecycle and geometry commands share the same aggregate transaction
// boundary as application placement. They never own parallel state.
extension LauncherStore {
    // MARK: - Group lifecycle and geometry

    func fitGroupToContent(id: String) {
        guard let index = state.userGroups.firstIndex(where: { $0.id == id }) else { return }
        let previousState = state
        let previousGroup = state.userGroups[index]
        let members = orderedAssignedApps(in: id, includeHidden: false)
        let fittedSize = InteractionGeometry.fittedGroupSize(for: members.count)
        state.userGroups[index].size = StoredSize(fittedSize)
        state.userGroups[index].center = StoredPoint(
            SpatialLayoutEngine.constrainedCenter(
                for: id,
                proposed: previousGroup.center.point,
                in: state.userGroups
            )
        )
        let fittedFrame = SpatialLayoutEngine.frame(for: state.userGroups[index])
        for (appID, point) in SpatialLayoutEngine.gridPositions(
            for: members.map(\.id),
            inside: InteractionGeometry.contentRect(for: fittedFrame)
        ) {
            state.positions[appID] = StoredPoint(point)
        }
        commitStateMutation(from: previousState, message: "“\(previousGroup.name)”已适配内容")
    }

    func createGroup(name: String, tint: GroupTint, center: CGPoint) {
        let previousState = state
        let trimmed = name.zizaiVisibleTrimmed
        let group = UserGroup(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "新分组" : trimmed,
            subtitle: "自定义分组",
            tint: tint,
            center: StoredPoint(center),
            size: StoredSize(InteractionGeometry.fittedGroupSize(for: 0)),
            isStarterGroup: false
        )
        state.userGroups.append(group)
        if let index = state.userGroups.firstIndex(where: { $0.id == group.id }) {
            state.userGroups[index].center = StoredPoint(
                SpatialLayoutEngine.constrainedCenter(
                    for: group.id,
                    proposed: center,
                    in: state.userGroups
                )
            )
        }
        commitStateMutation(from: previousState, message: "已创建“\(group.name)”")
    }

    func updateGroup(id: String, name: String, tint: GroupTint) {
        guard let index = state.userGroups.firstIndex(where: { $0.id == id }) else { return }
        let previousState = state
        let previous = state.userGroups[index]
        let trimmed = name.zizaiVisibleTrimmed
        state.userGroups[index].name = trimmed.isEmpty ? previous.name : trimmed
        state.userGroups[index].tint = tint
        commitStateMutation(from: previousState, message: "分组已更新")
    }

    func resolvedGroupCenter(id: String, proposedCenter: CGPoint) -> CGPoint {
        SpatialLayoutEngine.constrainedCenter(
            for: id,
            proposed: proposedCenter,
            in: state.userGroups
        )
    }

    func commitGroupMove(
        id: String,
        originalCenter: CGPoint,
        originalAppPositions: [String: CGPoint],
        delta: CGSize
    ) {
        guard let index = state.userGroups.firstIndex(where: { $0.id == id }) else { return }
        let requestedCenter = CGPoint(
            x: originalCenter.x + delta.width,
            y: originalCenter.y + delta.height
        )
        let resolvedCenter = SpatialLayoutEngine.constrainedCenter(
            for: id,
            proposed: requestedCenter,
            in: state.userGroups
        )
        let committedDelta = CGSize(
            width: resolvedCenter.x - originalCenter.x,
            height: resolvedCenter.y - originalCenter.y
        )
        guard abs(committedDelta.width) > 0.5 || abs(committedDelta.height) > 0.5 else { return }
        let previousState = state
        state.userGroups[index].center = StoredPoint(resolvedCenter)
        for (appID, point) in originalAppPositions {
            state.positions[appID] = StoredPoint(
                CGPoint(
                    x: point.x + committedDelta.width,
                    y: point.y + committedDelta.height
                )
            )
        }
        guard let group = group(withID: id) else { return }
        commitStateMutation(from: previousState, message: "“\(group.name)”的位置已保存")
    }

    /// Deterministic directional movement for accessibility and keyboard
    /// interaction. It reuses the pointer command so collision resolution,
    /// child positions, persistence, announcements, and undo stay identical.
    func nudgeGroup(
        id: String,
        direction: SpatialMoveDirection,
        step: CGFloat = 24
    ) {
        guard let group = group(withID: id) else { return }
        let originalPositions = Dictionary(
            uniqueKeysWithValues:
                assignedApps(in: id).map { ($0.id, position(for: $0)) }
        )
        commitGroupMove(
            id: id,
            originalCenter: group.center.point,
            originalAppPositions: originalPositions,
            delta: direction.delta(step: step)
        )
    }

    func resolvedGroupResize(
        id: String,
        proposedFrame: CGRect,
        originalFrame: CGRect
    ) -> GroupResizePreview? {
        guard state.userGroups.contains(where: { $0.id == id }) else { return nil }
        let minimum = CGSize(
            width: InteractionGeometry.minimumGroupWidth,
            height: InteractionGeometry.minimumGroupHeight
        )
        guard proposedFrame.width >= minimum.width,
            proposedFrame.height >= minimum.height,
            InteractionGeometry.capacity(of: proposedFrame)
                >= assignedApps(in: id, includeHidden: false).count,
            !SpatialLayoutEngine.collides(
                proposedFrame,
                excluding: id,
                in: state.userGroups
            )
        else {
            return nil
        }

        let orderedIDs = orderedAssignedApps(in: id, includeHidden: false).map(\.id)
        let originalPositions = Dictionary(
            uniqueKeysWithValues:
                assignedApps(in: id, includeHidden: false).map { ($0.id, position(for: $0)) }
        )
        let mapped = SpatialLayoutEngine.mappedPositions(
            originalPositions,
            from: InteractionGeometry.contentRect(for: originalFrame),
            to: InteractionGeometry.contentRect(for: proposedFrame)
        )
        let safePositions =
            SpatialLayoutEngine.needsRepair(
                mapped,
                inside: SpatialLayoutEngine.appCenterRect(for: proposedFrame)
            )
            ? SpatialLayoutEngine.gridPositions(
                for: orderedIDs,
                inside: InteractionGeometry.contentRect(for: proposedFrame)
            )
            : mapped
        return GroupResizePreview(
            groupID: id,
            frame: proposedFrame,
            appPositions: safePositions
        )
    }

    func adjustGroupSize(id: String, by delta: CGFloat) {
        guard let group = group(withID: id) else { return }
        let originalFrame = SpatialLayoutEngine.frame(for: group)
        let originalPositions = Dictionary(
            uniqueKeysWithValues:
                assignedApps(in: id, includeHidden: false).map { ($0.id, position(for: $0)) }
        )
        let proposed = originalFrame.insetBy(dx: -delta / 2, dy: -delta / 2)
        guard
            let preview = resolvedGroupResize(
                id: id,
                proposedFrame: proposed,
                originalFrame: originalFrame
            )
        else {
            announce("当前大小已达到可用边界")
            return
        }
        commitGroupResize(
            id: id,
            originalFrame: originalFrame,
            originalAppPositions: originalPositions,
            preview: preview
        )
    }

    func commitGroupResize(
        id: String,
        originalFrame: CGRect,
        originalAppPositions: [String: CGPoint],
        preview: GroupResizePreview
    ) {
        guard preview.groupID == id,
            let index = state.userGroups.firstIndex(where: { $0.id == id })
        else {
            return
        }
        let frameChanged =
            abs(preview.frame.minX - originalFrame.minX) > 0.5
            || abs(preview.frame.minY - originalFrame.minY) > 0.5
            || abs(preview.frame.width - originalFrame.width) > 0.5
            || abs(preview.frame.height - originalFrame.height) > 0.5
        let positionsChanged = preview.appPositions.contains { appID, point in
            guard let original = originalAppPositions[appID] else { return true }
            return hypot(point.x - original.x, point.y - original.y) > 0.5
        }
        guard frameChanged || positionsChanged else { return }
        let previousState = state
        state.userGroups[index].center = StoredPoint(
            CGPoint(x: preview.frame.midX, y: preview.frame.midY)
        )
        state.userGroups[index].size = StoredSize(preview.frame.size)
        for (appID, position) in preview.appPositions {
            state.positions[appID] = StoredPoint(position)
        }
        guard let group = group(withID: id) else { return }
        commitStateMutation(from: previousState, message: "“\(group.name)”的大小已保存")
    }

    func deleteGroup(id: String) {
        guard state.userGroups.count > 1,
            let index = state.userGroups.firstIndex(where: { $0.id == id })
        else { return }
        let previousState = state
        let removed = state.userGroups[index]
        let affected = apps.filter { state.appGroupIDs[$0.id] == id }
        guard
            let fallback = state.userGroups.first(where: {
                $0.id == AppGroup.other.stableID && $0.id != id
            }) ?? state.userGroups.first(where: { $0.id != id })
        else { return }

        state.userGroups.remove(at: index)
        state.groupAppOrder.removeValue(forKey: id)
        if removed.isStarterGroup {
            state.deletedStarterGroupIDs.insert(removed.id)
        }
        for app in affected {
            state.appGroupIDs[app.id] = fallback.id
            state.groupAppOrder[fallback.id, default: []].append(app.id)
        }
        repairSpatialState(affectedGroupIDs: [fallback.id])
        commitStateMutation(
            from: previousState,
            message: "已删除分组，应用已移到“\(fallback.name)”"
        )
    }

}
