import AppKit
import SwiftUI

struct LibraryAppDragSession: Equatable {
    let appID: String
    let sourceGroupID: String
    let sourceIndex: Int
}

struct LibraryGroupDragSession: Equatable {
    let groupID: String
    let sourceIndex: Int
}

/// Geometry is observational input, not view state. Keeping the live frames in
/// a reference cache prevents measurement from invalidating the same layout
/// pass that produced it. A drag freezes this cache into value snapshots once,
/// so every hit test uses one coherent layout revision.
final class LibraryGeometrySnapshot {
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
