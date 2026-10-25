import CoreGraphics
import Foundation

/// Reconciles a fresh application scan with durable user state.
///
/// This policy is intentionally independent from `ObservableObject`, AppKit,
/// persistence, and user feedback. `LauncherStore` remains responsible for
/// transaction ordering; this type owns the deterministic state merge rules.
enum LauncherStateReconciler {
    static let applicationIdentitySchemaVersion = 8

    static func migrateApplicationIdentityIfNeeded(
        state: inout PersistedState,
        apps: [AppInfo]
    ) -> Bool {
        guard state.schemaVersion < applicationIdentitySchemaVersion else {
            return false
        }
        ApplicationCatalogLogic.migrateLegacyIdentity(state: &state, apps: apps)
        return true
    }

    static func ensureStarterGroups(
        state: inout PersistedState,
        apps: [AppInfo]
    ) {
        let existingIDs = Set(state.userGroups.map(\.id))
        let tints: [GroupTint] = [.indigo, .mint, .blue, .pink, .slate, .orange]
        let sizes = AppGroup.allCases.map { category in
            InteractionGeometry.fittedGroupSize(
                for: apps.count(where: { $0.group == category })
            )
        }
        let firstHeight = sizes.prefix(3).map(\.height).max() ?? 620
        let secondHeight = sizes.suffix(3).map(\.height).max() ?? 620
        let secondY = firstHeight / 2 + 180 + secondHeight / 2
        let centers = [
            CGPoint(x: 0, y: 0), CGPoint(x: 900, y: 0), CGPoint(x: 1_800, y: 0),
            CGPoint(x: 0, y: secondY), CGPoint(x: 900, y: secondY),
            CGPoint(x: 1_800, y: secondY),
        ]

        for (index, category) in AppGroup.allCases.enumerated()
        where !existingIDs.contains(category.stableID)
            && !state.deletedStarterGroupIDs.contains(category.stableID)
        {
            state.userGroups.append(
                UserGroup(
                    id: category.stableID,
                    name: category.rawValue,
                    subtitle: category.subtitle,
                    tint: tints[index],
                    center: StoredPoint(centers[index]),
                    size: StoredSize(sizes[index]),
                    isStarterGroup: true
                )
            )
        }

        guard state.userGroups.isEmpty,
            let index = AppGroup.allCases.firstIndex(of: .other)
        else { return }
        let category = AppGroup.other
        state.deletedStarterGroupIDs.remove(category.stableID)
        state.userGroups.append(
            UserGroup(
                id: category.stableID,
                name: category.rawValue,
                subtitle: category.subtitle,
                tint: tints[index],
                center: StoredPoint(centers[index]),
                size: StoredSize(sizes[index]),
                isStarterGroup: true
            )
        )
    }

    static func seedMissingAssignments(
        state: inout PersistedState,
        apps: [AppInfo]
    ) {
        let existingGroupIDs = Set(state.userGroups.map(\.id))
        let fallbackID =
            state.userGroups.first(where: { $0.id == AppGroup.other.stableID })?.id
            ?? state.userGroups.first?.id

        for app in apps {
            if let assignedID = state.appGroupIDs[app.id],
                existingGroupIDs.contains(assignedID)
            {
                continue
            }
            if existingGroupIDs.contains(app.group.stableID) {
                state.appGroupIDs[app.id] = app.group.stableID
            } else if let fallbackID {
                state.appGroupIDs[app.id] = fallbackID
            }
        }
    }

    static func ensureAppOrder(
        state: inout PersistedState,
        apps: [AppInfo],
        displayNamesByID: [String: String]
    ) {
        let existingIDs = Set(apps.map(\.id))
        for group in state.userGroups {
            let assigned =
                apps
                .filter { (state.appGroupIDs[$0.id] ?? $0.group.stableID) == group.id }
                .sorted { lhs, rhs in
                    let left = displayNamesByID[lhs.id] ?? lhs.name
                    let right = displayNamesByID[rhs.id] ?? rhs.name
                    return left.localizedStandardCompare(right) == .orderedAscending
                }
                .map(\.id)
            let assignedSet = Set(assigned)
            let preserved = (state.groupAppOrder[group.id] ?? [])
                .filter { existingIDs.contains($0) && assignedSet.contains($0) }
            let preservedSet = Set(preserved)
            let missing = assigned.filter { !preservedSet.contains($0) }
            state.groupAppOrder[group.id] = preserved + missing
        }
    }

    /// Seeds only applications that have never had a position. Existing user
    /// placement is preserved; new items inherit the same deterministic grid
    /// used by repair and migration.
    static func seedMissingPositions(
        state: inout PersistedState,
        apps: [AppInfo],
        displayNamesByID: [String: String]
    ) {
        for group in state.userGroups {
            let members = orderedApps(
                in: group.id,
                includeHidden: true,
                state: state,
                apps: apps,
                displayNamesByID: displayNamesByID
            )
            let positions = SpatialLayoutEngine.gridPositions(
                for: members.map(\.id),
                inside: InteractionGeometry.contentRect(
                    for: SpatialLayoutEngine.frame(for: group)
                )
            )
            for app in members where state.positions[app.id] == nil {
                if let position = positions[app.id] {
                    state.positions[app.id] = StoredPoint(position)
                }
            }
        }
    }

    /// Upgrades layouts created before collision-safe geometry became the
    /// canonical representation. Migration is deterministic and idempotent.
    static func migrateUnsafeLayoutIfNeeded(
        state: inout PersistedState,
        apps: [AppInfo],
        displayNamesByID: [String: String],
        schemaVersion: Int
    ) {
        guard state.schemaVersion < schemaVersion else { return }
        for index in state.userGroups.indices {
            let groupID = state.userGroups[index].id
            state.userGroups[index].size = StoredSize(
                InteractionGeometry.fittedGroupSize(
                    for: assignedApps(
                        in: groupID,
                        includeHidden: false,
                        state: state,
                        apps: apps
                    ).count
                )
            )
        }
        repairGroupSeparation(state: &state, apps: apps)
        for group in state.userGroups {
            arrangeApps(
                in: group.id,
                state: &state,
                apps: apps,
                displayNamesByID: displayNamesByID
            )
        }
        state.schemaVersion = schemaVersion
    }

    /// Restores all spatial invariants as one policy operation. Callers may
    /// limit app-grid repair to affected groups; group separation remains
    /// global because moving one group can affect every neighboring frame.
    static func repairSpatialIntegrity(
        state: inout PersistedState,
        apps: [AppInfo],
        displayNamesByID: [String: String],
        affectedGroupIDs: Set<String>? = nil
    ) {
        let groupIDs = state.userGroups.map(\.id)
        let repairedGroupIDs = affectedGroupIDs ?? Set(groupIDs)
        for groupID in repairedGroupIDs {
            ensureGroupCapacity(groupID, state: &state, apps: apps)
        }
        repairGroupSeparation(state: &state, apps: apps)
        for groupID in repairedGroupIDs {
            repairApps(
                in: groupID,
                state: &state,
                apps: apps,
                displayNamesByID: displayNamesByID
            )
        }
    }

    static func prepareGroupForPlacement(
        _ groupID: String,
        state: inout PersistedState,
        apps: [AppInfo]
    ) {
        ensureGroupCapacity(groupID, state: &state, apps: apps)
        repairGroupSeparation(state: &state, apps: apps)
    }

    static func pruneMissingApps(
        state: inout PersistedState,
        existingAppIDs: Set<String>
    ) {
        state.hiddenAppIDs.formIntersection(existingAppIDs)
        state.positions = state.positions.filter { existingAppIDs.contains($0.key) }
        state.aliases = state.aliases.filter { existingAppIDs.contains($0.key) }
        state.appGroupIDs = state.appGroupIDs.filter { existingAppIDs.contains($0.key) }
        state.groupAppOrder = state.groupAppOrder.mapValues {
            $0.filter(existingAppIDs.contains)
        }
    }

    private static func assignedApps(
        in groupID: String,
        includeHidden: Bool,
        state: PersistedState,
        apps: [AppInfo]
    ) -> [AppInfo] {
        apps
            .filter { includeHidden || !state.hiddenAppIDs.contains($0.id) }
            .filter { (state.appGroupIDs[$0.id] ?? $0.group.stableID) == groupID }
    }

    private static func orderedApps(
        in groupID: String,
        includeHidden: Bool,
        state: PersistedState,
        apps: [AppInfo],
        displayNamesByID: [String: String]
    ) -> [AppInfo] {
        let order = state.groupAppOrder[groupID] ?? []
        let rank = Dictionary(
            uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) }
        )
        return assignedApps(
            in: groupID,
            includeHidden: includeHidden,
            state: state,
            apps: apps
        ).sorted { lhs, rhs in
            let leftRank = rank[lhs.id] ?? .max
            let rightRank = rank[rhs.id] ?? .max
            if leftRank != rightRank { return leftRank < rightRank }
            let leftName = displayNamesByID[lhs.id] ?? lhs.name
            let rightName = displayNamesByID[rhs.id] ?? rhs.name
            return leftName.localizedStandardCompare(rightName) == .orderedAscending
        }
    }

    private static func ensureGroupCapacity(
        _ groupID: String,
        state: inout PersistedState,
        apps: [AppInfo]
    ) {
        guard let index = state.userGroups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        let count = assignedApps(
            in: groupID,
            includeHidden: false,
            state: state,
            apps: apps
        ).count
        var size = state.userGroups[index].size.size
        if InteractionGeometry.capacity(of: CGRect(origin: .zero, size: size)) < count {
            let fitted = InteractionGeometry.fittedGroupSize(for: count)
            size.width = max(size.width, fitted.width)
            size.height = max(size.height, fitted.height)
        }
        state.userGroups[index].size = StoredSize(size)
    }

    private static func repairGroupSeparation(
        state: inout PersistedState,
        apps: [AppInfo]
    ) {
        for _ in 0..<12 {
            var changed = false
            for groupID in state.userGroups.map(\.id) {
                guard let index = state.userGroups.firstIndex(where: { $0.id == groupID }) else {
                    continue
                }
                let original = state.userGroups[index].center.point
                let constrained = SpatialLayoutEngine.constrainedCenter(
                    for: groupID,
                    proposed: original,
                    in: state.userGroups
                )
                guard hypot(constrained.x - original.x, constrained.y - original.y) > 0.5 else {
                    continue
                }

                let delta = CGSize(
                    width: constrained.x - original.x,
                    height: constrained.y - original.y
                )
                state.userGroups[index].center = StoredPoint(constrained)
                for app in assignedApps(
                    in: groupID,
                    includeHidden: true,
                    state: state,
                    apps: apps
                ) {
                    let point = state.positions[app.id]?.point ?? .zero
                    state.positions[app.id] = StoredPoint(
                        CGPoint(x: point.x + delta.width, y: point.y + delta.height)
                    )
                }
                changed = true
            }
            if !changed { break }
        }
    }

    private static func repairApps(
        in groupID: String,
        state: inout PersistedState,
        apps: [AppInfo],
        displayNamesByID: [String: String]
    ) {
        guard let group = state.userGroups.first(where: { $0.id == groupID }) else {
            return
        }
        let members = orderedApps(
            in: groupID,
            includeHidden: false,
            state: state,
            apps: apps,
            displayNamesByID: displayNamesByID
        )
        let frame = SpatialLayoutEngine.frame(for: group)
        let current = Dictionary(
            uniqueKeysWithValues: members.map {
                ($0.id, state.positions[$0.id]?.point ?? .zero)
            }
        )
        guard
            SpatialLayoutEngine.needsRepair(
                current,
                inside: SpatialLayoutEngine.appCenterRect(for: frame)
            )
        else { return }
        arrangeApps(
            in: groupID,
            state: &state,
            apps: apps,
            displayNamesByID: displayNamesByID
        )
    }

    private static func arrangeApps(
        in groupID: String,
        state: inout PersistedState,
        apps: [AppInfo],
        displayNamesByID: [String: String]
    ) {
        guard let group = state.userGroups.first(where: { $0.id == groupID }) else {
            return
        }
        let members = orderedApps(
            in: groupID,
            includeHidden: false,
            state: state,
            apps: apps,
            displayNamesByID: displayNamesByID
        )
        let positions = SpatialLayoutEngine.gridPositions(
            for: members.map(\.id),
            inside: InteractionGeometry.contentRect(
                for: SpatialLayoutEngine.frame(for: group)
            )
        )
        for (appID, point) in positions {
            state.positions[appID] = StoredPoint(point)
        }
    }
}
