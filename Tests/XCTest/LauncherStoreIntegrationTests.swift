import Foundation
import XCTest

@testable import 自在启动台

@MainActor
final class LauncherStoreIntegrationTests: XCTestCase {
    func testSearchReturnsEveryInstalledInstanceAndSupportsLocalizedTerms() {
        withStore { store, _ in
            store.searchText = "fig"
            XCTAssertEqual(store.searchResults.count, 2)
            XCTAssertTrue(
                store.searchResults.allSatisfy { $0.bundleIdentifier == "com.figma.Desktop" }
            )

            store.searchText = "fga"
            XCTAssertEqual(
                store.searchResults.filter { $0.bundleIdentifier == "com.figma.Desktop" }.count,
                2
            )

            store.searchText = "信"
            let identifiers = Set(store.searchResults.map(\.bundleIdentifier))
            XCTAssertTrue(identifiers.contains("com.tencent.xinWeChat"))
            XCTAssertTrue(identifiers.contains("com.apple.MobileSMS"))
        }
    }

    func testAliasesAndVisibilityRemainScopedToOneInstalledInstance() {
        withStore { store, applications in
            let family = applications.filter { $0.bundleIdentifier == "com.figma.Desktop" }
            XCTAssertEqual(family.count, 2)
            guard let first = family.first, let second = family.last else {
                return XCTFail("Missing duplicate application fixtures")
            }

            store.setAlias("客户版 Figma", for: first)
            store.setHidden(true, for: first)

            XCTAssertEqual(store.displayName(for: first), "客户版 Figma")
            XCTAssertNotEqual(store.displayName(for: second), "客户版 Figma")
            XCTAssertTrue(store.isHidden(first))
            XCTAssertFalse(store.isHidden(second))
            XCTAssertNotEqual(store.instanceLabel(for: first), store.instanceLabel(for: second))
        }
    }

    func testCrossGroupMoveAndUndoRestoreTheExactPersistedState() {
        withStore { store, applications in
            guard let app = applications.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" })
            else { return XCTFail("Missing cross-group application fixture") }
            let before = store.state

            store.move(app, toGroupID: AppGroup.aiCreative.stableID, insertionIndex: 0)
            XCTAssertEqual(store.group(for: app)?.id, AppGroup.aiCreative.stableID)

            store.undoLastAction()
            XCTAssertEqual(store.state, before)
        }
    }

    func testDeletingAStarterGroupPersistsAndUndoRestoresIt() {
        withStore { store, applications, directory in
            let before = store.state
            store.deleteGroup(id: AppGroup.communication.stableID)

            XCTAssertFalse(
                store.groups.contains { $0.id == AppGroup.communication.stableID }
            )
            XCTAssertTrue(
                store.state.deletedStarterGroupIDs.contains(AppGroup.communication.stableID)
            )

            let restarted = LauncherStore(stateDirectory: directory, appProvider: { applications })
            XCTAssertFalse(
                restarted.groups.contains { $0.id == AppGroup.communication.stableID }
            )
            XCTAssertTrue(
                applications
                    .filter { $0.group == .communication }
                    .allSatisfy { restarted.group(for: $0) != nil }
            )

            store.undoLastAction()
            XCTAssertEqual(store.state, before)
        }
    }

    func testIncompleteScanPreservesStateForTemporarilyUnavailableApplications() {
        withTemporaryDirectory { directory in
            let applications = makeApplications()
            guard let protectedApplication = applications.last else {
                return XCTFail("Missing protected application fixture")
            }

            let completeStore = LauncherStore(
                stateDirectory: directory,
                appProvider: { applications }
            )
            completeStore.setAlias("保留的用户应用", for: protectedApplication)

            let partialApplications = Array(applications.dropLast())
            let incompleteStore = LauncherStore(
                stateDirectory: directory,
                appProvider: { partialApplications },
                isAppScanComplete: { false }
            )
            XCTAssertEqual(
                incompleteStore.state.aliases[protectedApplication.id],
                "保留的用户应用"
            )

            let confirmedCompleteStore = LauncherStore(
                stateDirectory: directory,
                appProvider: { partialApplications }
            )
            XCTAssertNil(confirmedCompleteStore.state.aliases[protectedApplication.id])
        }
    }

    func testGroupGeometryOperationsUndoWithoutPrecisionDrift() {
        withStore { store, _ in
            let groupID = AppGroup.aiCreative.stableID
            guard let group = store.group(withID: groupID) else {
                return XCTFail("Missing group fixture")
            }
            let beforeMove = store.state
            let members = store.assignedApps(in: groupID, includeHidden: false)
            let originalPositions = Dictionary(
                uniqueKeysWithValues: members.map { ($0.id, store.position(for: $0)) }
            )

            store.commitGroupMove(
                id: groupID,
                originalCenter: group.center.point,
                originalAppPositions: originalPositions,
                delta: CGSize(width: 24.125, height: -16.375)
            )
            XCTAssertNotEqual(store.state, beforeMove)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforeMove)

            let beforeResize = store.state
            store.adjustGroupSize(id: groupID, by: 40)
            XCTAssertNotEqual(store.state, beforeResize)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforeResize)
        }
    }

    func testAccessibleGroupNudgeMovesEveryMemberAndUndoRestoresExactState() {
        withStore { store, _ in
            let groupID = AppGroup.aiCreative.stableID
            guard let group = store.group(withID: groupID) else {
                return XCTFail("Missing group fixture")
            }
            let members = store.assignedApps(in: groupID)
            let originalPositions = Dictionary(
                uniqueKeysWithValues: members.map { ($0.id, store.position(for: $0)) }
            )
            let before = store.state

            store.nudgeGroup(id: groupID, direction: .left)

            guard let moved = store.group(withID: groupID) else {
                return XCTFail("Missing moved group")
            }
            XCTAssertEqual(moved.center.x, group.center.x - 24, accuracy: 0.001)
            XCTAssertEqual(moved.center.y, group.center.y, accuracy: 0.001)
            for member in members {
                guard let original = originalPositions[member.id] else {
                    return XCTFail("Missing original position")
                }
                let updated = store.position(for: member)
                XCTAssertEqual(updated.x, original.x - 24, accuracy: 0.001)
                XCTAssertEqual(updated.y, original.y, accuracy: 0.001)
            }

            store.undoLastAction()
            XCTAssertEqual(store.state, before)
        }
    }

    func testAccessibleAdjacentGroupMoveUsesNormalTransactionAndUndo() {
        withStore { store, applications in
            guard
                let app = applications.first(where: {
                    $0.bundleIdentifier == "com.tencent.xinWeChat"
                })
            else { return XCTFail("Missing adjacent-group application fixture") }
            let before = store.state

            store.moveAppToAdjacentGroup(app, offset: 1)

            XCTAssertEqual(store.group(for: app)?.id, AppGroup.productivity.stableID)
            store.undoLastAction()
            XCTAssertEqual(store.state, before)
        }
    }

    func testHiddenApplicationsLeaveAndReenterVisibleLayoutWithoutOverlap() {
        withStore { store, applications in
            guard let app = applications.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" })
            else { return XCTFail("Missing hidden-layout application fixture") }

            store.setHidden(true, for: app)
            XCTAssertEqual(store.appCount(in: AppGroup.communication.stableID), 1)
            store.setHidden(false, for: app)
            XCTAssertEqual(store.appCount(in: AppGroup.communication.stableID), 2)

            let visible = store.assignedApps(
                in: AppGroup.communication.stableID,
                includeHidden: false
            )
            XCTAssertEqual(visible.count, 2)
            guard visible.count == 2 else { return }
            let first = store.position(for: visible[0])
            let second = store.position(for: visible[1])
            XCTAssertTrue(
                abs(first.x - second.x) >= InteractionGeometry.appCellWidth
                    || abs(first.y - second.y) >= InteractionGeometry.appCellHeight
            )
        }
    }

    func testGroupLifecycleUsesOneTransactionalUndoChain() {
        withStore { store, _ in
            let initialIDs = store.groups.map(\.id)

            store.createGroup(
                name: "  客户项目  ",
                tint: .orange,
                center: CGPoint(x: 4_000, y: 2_000)
            )
            guard let created = store.groups.first(where: { !initialIDs.contains($0.id) }) else {
                return XCTFail("Custom group was not created")
            }
            XCTAssertEqual(created.name, "客户项目")

            store.updateGroup(id: created.id, name: "交付项目", tint: .mint)
            XCTAssertEqual(store.group(withID: created.id)?.name, "交付项目")
            XCTAssertEqual(store.group(withID: created.id)?.tint, .mint)

            store.undoLastAction()
            XCTAssertEqual(store.group(withID: created.id)?.name, "客户项目")
            XCTAssertEqual(store.group(withID: created.id)?.tint, .orange)

            store.undoLastAction()
            XCTAssertEqual(store.groups.map(\.id), initialIDs)
        }
    }

    func testGroupAndApplicationOrderingPreserveIdentityAndUndo() {
        withStore { store, _ in
            let originalGroups = store.groups.map(\.id)
            guard let firstGroup = originalGroups.first else {
                return XCTFail("Missing group fixture")
            }
            store.moveGroup(id: firstGroup, by: 1)
            XCTAssertEqual(store.groups.dropFirst().first?.id, firstGroup)
            store.undoLastAction()
            XCTAssertEqual(store.groups.map(\.id), originalGroups)

            let groupID = AppGroup.communication.stableID
            let originalApps = store.apps(in: groupID)
            guard originalApps.count >= 2 else {
                return XCTFail("Missing reorder fixtures")
            }
            store.moveApp(originalApps[0], inGroupID: groupID, by: 1)
            XCTAssertEqual(store.apps(in: groupID).map(\.id), [originalApps[1].id, originalApps[0].id])
            store.undoLastAction()
            XCTAssertEqual(store.apps(in: groupID).map(\.id), originalApps.map(\.id))
        }
    }

    func testSpatialMoveSwapAndUndoRestoreExactState() {
        withStore { store, _ in
            let groupID = AppGroup.communication.stableID
            let members = store.apps(in: groupID)
            guard members.count >= 2 else {
                return XCTFail("Missing spatial move fixtures")
            }
            let moving = members[0]
            let displaced = members[1]
            let before = store.state
            let movingPosition = store.position(for: moving)
            let displacedPosition = store.position(for: displaced)

            guard let preview = store.resolvedAppMovePreview(moving, to: displacedPosition) else {
                return XCTFail("Move preview was not resolved")
            }
            XCTAssertEqual(preview.displacedAppID, displaced.id)
            store.commitAppMove(moving, preview: preview)
            XCTAssertEqual(store.position(for: moving), displacedPosition)
            XCTAssertEqual(store.position(for: displaced), movingPosition)

            store.undoLastAction()
            XCTAssertEqual(store.state, before)
        }
    }

    func testArrangeAndFitGroupRemainUndoableTransactions() {
        withStore { store, applications in
            let groupID = AppGroup.communication.stableID
            guard let app = applications.first(where: { $0.group == .communication }) else {
                return XCTFail("Missing layout fixture")
            }
            store.updatePosition(CGPoint(x: -50_000, y: -50_000), for: app, persist: false)
            let beforeArrange = store.state

            store.arrangeApps(in: groupID)
            XCTAssertNotEqual(store.state, beforeArrange)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforeArrange)

            guard
                let group = store.group(withID: groupID),
                let groupIndex = store.groups.firstIndex(where: { $0.id == groupID })
            else {
                return XCTFail("Missing group fixture")
            }
            store.state.userGroups[groupIndex].size =
                StoredSize(width: group.size.width + 300, height: group.size.height + 300)
            let beforeFit = store.state
            store.fitGroupToContent(id: groupID)
            XCTAssertNotEqual(store.state, beforeFit)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforeFit)
        }
    }

    func testCanvasNavigationClampsPersistsAndRestores() {
        withStore { store, applications, directory in
            let viewport = CGSize(width: 1_100, height: 720)
            store.updateCanvas(offset: CGSize(width: 70, height: -40), scale: 9, persist: true)
            XCTAssertEqual(store.canvasScale, 1.45)
            store.adjustCanvasZoom(
                by: -0.25,
                around: CGPoint(x: 900, y: 120),
                in: viewport
            )
            XCTAssertEqual(store.canvasScale, 1.2, accuracy: 0.0001)

            let focusID = AppGroup.aiCreative.stableID
            store.focus(on: focusID, in: viewport)
            XCTAssertGreaterThanOrEqual(store.canvasScale, CanvasViewportMetrics.focusedMinimumScale)
            XCTAssertLessThanOrEqual(store.canvasScale, CanvasViewportMetrics.focusedMaximumScale)
            store.fitAllGroups(in: viewport)
            XCTAssertGreaterThanOrEqual(store.canvasScale, CanvasViewportMetrics.minimumScale)
            XCTAssertLessThanOrEqual(store.canvasScale, CanvasViewportMetrics.overviewMaximumScale)
            store.flushPendingPersistence()

            let restarted = LauncherStore(stateDirectory: directory, appProvider: { applications })
            XCTAssertEqual(restarted.canvasScale, store.canvasScale, accuracy: 0.0001)
            XCTAssertEqual(restarted.canvasOffset.width, store.canvasOffset.width, accuracy: 0.0001)
            XCTAssertEqual(restarted.canvasOffset.height, store.canvasOffset.height, accuracy: 0.0001)
        }
    }

    func testSearchSelectionAndLayoutModePersistenceFollowCurrentResults() {
        withStore { store, applications, directory in
            store.searchText = "figma"
            store.refreshSearchSelection()
            let first = store.currentSearchResultID
            XCTAssertNotNil(first)
            store.advanceSearchResult()
            XCTAssertNotEqual(store.currentSearchResultID, first)
            store.clearSearch()
            XCTAssertNil(store.currentSearchResultID)

            store.stageLayoutModePersistence(.space)
            store.flushPendingPersistence()
            let restarted = LauncherStore(stateDirectory: directory, appProvider: { applications })
            XCTAssertEqual(restarted.layoutMode, .space)
        }
    }

    func testStateReconcilerRestoresAUsableFallbackAndPrunesOnlyMissingApps() {
        let applications = makeApplications()
        var state = PersistedState()
        state.deletedStarterGroupIDs = Set(AppGroup.allCases.map(\.stableID))

        LauncherStateReconciler.ensureStarterGroups(state: &state, apps: applications)

        XCTAssertEqual(state.userGroups.map(\.id), [AppGroup.other.stableID])
        XCTAssertFalse(state.deletedStarterGroupIDs.contains(AppGroup.other.stableID))

        LauncherStateReconciler.seedMissingAssignments(state: &state, apps: applications)
        LauncherStateReconciler.ensureAppOrder(
            state: &state,
            apps: applications,
            displayNamesByID: Dictionary(
                uniqueKeysWithValues: applications.map { ($0.id, $0.chineseName) }
            )
        )
        LauncherStateReconciler.seedMissingPositions(
            state: &state,
            apps: applications,
            displayNamesByID: Dictionary(
                uniqueKeysWithValues: applications.map { ($0.id, $0.chineseName) }
            )
        )

        XCTAssertEqual(Set(state.appGroupIDs.values), [AppGroup.other.stableID])
        XCTAssertEqual(state.groupAppOrder[AppGroup.other.stableID]?.count, applications.count)
        XCTAssertEqual(state.positions.count, applications.count)

        guard let retained = applications.first else {
            return XCTFail("Missing reconciliation fixture")
        }
        let missingID = "missing-application"
        state.aliases[retained.id] = "保留别名"
        state.aliases[missingID] = "过期别名"
        state.hiddenAppIDs.formUnion([retained.id, missingID])
        state.positions[missingID] = StoredPoint(x: 10, y: 10)
        state.appGroupIDs[missingID] = AppGroup.other.stableID
        state.groupAppOrder[AppGroup.other.stableID, default: []].append(missingID)

        LauncherStateReconciler.pruneMissingApps(
            state: &state,
            existingAppIDs: [retained.id]
        )

        XCTAssertEqual(state.aliases, [retained.id: "保留别名"])
        XCTAssertEqual(state.hiddenAppIDs, [retained.id])
        XCTAssertEqual(Set(state.positions.keys), [retained.id])
        XCTAssertEqual(Set(state.appGroupIDs.keys), [retained.id])
        XCTAssertEqual(state.groupAppOrder[AppGroup.other.stableID], [retained.id])
    }

    func testStateReconcilerMigratesCapacitySeparationAndApplicationGeometryTogether() throws {
        let applications = makeApplications()
        let firstID = "first"
        let secondID = "second"
        var state = PersistedState()
        state.schemaVersion = 7
        state.userGroups = [
            UserGroup(
                id: firstID,
                name: "第一组",
                subtitle: "",
                tint: .indigo,
                center: StoredPoint(x: 0, y: 0),
                size: StoredSize(width: 220, height: 180),
                isStarterGroup: false
            ),
            UserGroup(
                id: secondID,
                name: "第二组",
                subtitle: "",
                tint: .mint,
                center: StoredPoint(x: 0, y: 0),
                size: StoredSize(width: 220, height: 180),
                isStarterGroup: false
            ),
        ]
        for (index, app) in applications.enumerated() {
            state.appGroupIDs[app.id] = index == applications.count - 1 ? secondID : firstID
            state.positions[app.id] = StoredPoint(x: -50_000, y: -50_000)
        }
        let names = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.id, $0.chineseName) }
        )

        LauncherStateReconciler.migrateUnsafeLayoutIfNeeded(
            state: &state,
            apps: applications,
            displayNamesByID: names,
            schemaVersion: 9
        )

        XCTAssertEqual(state.schemaVersion, 9)
        let first = try XCTUnwrap(state.userGroups.first(where: { $0.id == firstID }))
        let second = try XCTUnwrap(state.userGroups.first(where: { $0.id == secondID }))
        XCTAssertGreaterThanOrEqual(
            InteractionGeometry.capacity(of: CGRect(origin: .zero, size: first.size.size)),
            applications.count - 1
        )
        XCTAssertFalse(
            SpatialLayoutEngine.frame(for: first)
                .intersects(
                    SpatialLayoutEngine.frame(for: second)
                        .insetBy(
                            dx: -SpatialLayoutEngine.groupGap,
                            dy: -SpatialLayoutEngine.groupGap
                        )
                )
        )
        for group in state.userGroups {
            let members = applications.filter { state.appGroupIDs[$0.id] == group.id }
            let positions = Dictionary(
                uniqueKeysWithValues: members.compactMap { app in
                    state.positions[app.id].map { (app.id, $0.point) }
                }
            )
            XCTAssertFalse(
                SpatialLayoutEngine.needsRepair(
                    positions,
                    inside: SpatialLayoutEngine.appCenterRect(
                        for: SpatialLayoutEngine.frame(for: group)
                    )
                )
            )
        }

        let migratedState = state
        LauncherStateReconciler.migrateUnsafeLayoutIfNeeded(
            state: &state,
            apps: applications,
            displayNamesByID: names,
            schemaVersion: 9
        )
        XCTAssertEqual(state, migratedState)
    }

    func testIdentityMigrationAndPlacementPreparationAreIdempotent() {
        let applications = makeApplications()
        guard let application = applications.first else {
            return XCTFail("Missing identity migration fixture")
        }
        var state = PersistedState()
        state.schemaVersion = 7
        state.aliases[application.bundleIdentifier] = "旧身份别名"

        XCTAssertTrue(
            LauncherStateReconciler.migrateApplicationIdentityIfNeeded(
                state: &state,
                apps: applications
            )
        )
        XCTAssertEqual(state.aliases[application.id], "旧身份别名")
        state.schemaVersion = LauncherStateReconciler.applicationIdentitySchemaVersion
        XCTAssertFalse(
            LauncherStateReconciler.migrateApplicationIdentityIfNeeded(
                state: &state,
                apps: applications
            )
        )

        LauncherStateReconciler.ensureStarterGroups(state: &state, apps: applications)
        LauncherStateReconciler.seedMissingAssignments(state: &state, apps: applications)
        let groupID = application.group.stableID
        LauncherStateReconciler.prepareGroupForPlacement(
            groupID,
            state: &state,
            apps: applications
        )
        XCTAssertNotNil(state.userGroups.first(where: { $0.id == groupID }))

        let prepared = state
        LauncherStateReconciler.prepareGroupForPlacement(
            "missing-group",
            state: &state,
            apps: applications
        )
        XCTAssertEqual(state, prepared)
    }

    func testStateHistoryIsBoundedAndRestoresRevisionsInLIFOOrder() {
        var history = LauncherStateHistory(capacity: 2)
        let first = PersistedState()
        var second = first
        var third = first
        var fourth = first
        second.hasSeenWelcome = true
        third.layoutMode = .space
        fourth.layoutMode = .allApps

        history.record(previous: first, current: second)
        history.record(previous: second, current: third)
        history.record(previous: third, current: fourth)

        XCTAssertEqual(history.snapshots.count, 2)
        XCTAssertEqual(history.popLast(), third)
        XCTAssertEqual(history.popLast(), second)
        XCTAssertNil(history.popLast())
        XCTAssertFalse(history.canUndo)
        history.record(previous: fourth, current: fourth)
        XCTAssertFalse(history.canUndo)
    }

    func testUndoRemainsAvailableAfterToastIsDismissed() {
        withStore { store, applications in
            guard let application = applications.first else {
                return XCTFail("Missing undo fixture")
            }
            let before = store.state

            store.setAlias("可撤销名称", for: application)
            XCTAssertTrue(store.canUndo)
            store.dismissToast()
            XCTAssertNil(store.toast)

            store.undoLastAction()
            XCTAssertEqual(store.state, before)
            XCTAssertFalse(store.canUndo)
        }
    }

    func testPointerPlacementAndOrderingCommandsShareAtomicUndoHistory() {
        withStore { store, applications in
            guard
                let application = applications.first(where: {
                    $0.bundleIdentifier == "com.tencent.xinWeChat"
                }),
                let destination = store.group(withID: AppGroup.aiCreative.stableID),
                let reference = store.apps(in: destination.id).first
            else { return XCTFail("Missing placement fixtures") }

            let beforePlacement = store.state
            let preview = store.interactiveAppMovePreview(
                application,
                to: destination.center.point
            )
            XCTAssertEqual(preview?.targetGroupID, destination.id)
            store.updateDropTarget(destination.id)
            XCTAssertEqual(store.dropTargetGroupID, destination.id)
            store.finishMoving(application, to: destination.center.point)
            XCTAssertEqual(store.group(for: application)?.id, destination.id)
            XCTAssertNil(store.dropTargetGroupID)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforePlacement)

            let beforeRelativeMove = store.state
            store.move(
                application,
                toGroupID: destination.id,
                relativeToAppID: reference.id,
                placeAfter: true
            )
            XCTAssertEqual(store.group(for: application)?.id, destination.id)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforeRelativeMove)

            let firstID = store.groups[0].id
            let secondID = store.groups[1].id
            let beforeRelativeGroupMove = store.state
            store.moveGroup(id: firstID, relativeTo: secondID, placeAfter: true)
            XCTAssertEqual(store.groups[1].id, firstID)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforeRelativeGroupMove)

            let beforeIndexedGroupMove = store.state
            store.moveGroup(id: firstID, toInsertionIndex: store.groups.count)
            XCTAssertEqual(store.groups.last?.id, firstID)
            store.undoLastAction()
            XCTAssertEqual(store.state, beforeIndexedGroupMove)
        }
    }

    private func withStore(
        _ body: (LauncherStore, [AppInfo]) -> Void
    ) {
        withTemporaryDirectory { directory in
            let applications = makeApplications()
            body(
                LauncherStore(stateDirectory: directory, appProvider: { applications }),
                applications
            )
        }
    }

    private func withStore(
        _ body: (LauncherStore, [AppInfo], URL) -> Void
    ) {
        withTemporaryDirectory { directory in
            let applications = makeApplications()
            body(
                LauncherStore(stateDirectory: directory, appProvider: { applications }),
                applications,
                directory
            )
        }
    }

    private func withTemporaryDirectory(_ body: (URL) -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-store-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        body(directory)
    }

    private func makeApplications() -> [AppInfo] {
        [
            makeApplication(
                bundleIdentifier: "com.tencent.xinWeChat",
                name: "WeChat",
                chineseName: "微信",
                path: "/Applications/WeChat.app",
                purpose: "微信",
                group: .communication
            ),
            makeApplication(
                bundleIdentifier: "com.apple.MobileSMS",
                name: "Messages",
                chineseName: "信息",
                path: "/System/Applications/Messages.app",
                purpose: "即时沟通",
                group: .communication
            ),
            makeApplication(
                bundleIdentifier: "com.openai.codex",
                name: "Codex",
                chineseName: "Codex",
                path: "/Applications/Codex.app",
                purpose: "代码助手",
                group: .aiCreative
            ),
            makeApplication(
                bundleIdentifier: "com.figma.Desktop",
                name: "Figma",
                chineseName: "Figma",
                path: "/Applications/Figma.app",
                purpose: "界面设计",
                group: .aiCreative
            ),
            makeApplication(
                bundleIdentifier: "com.figma.Desktop",
                name: "Figma",
                chineseName: "Figma",
                path: "/Applications/Figma+EX.app",
                purpose: "界面设计",
                group: .aiCreative
            ),
        ]
    }

    private func makeApplication(
        bundleIdentifier: String,
        name: String,
        chineseName: String,
        path: String,
        purpose: String,
        group: AppGroup
    ) -> AppInfo {
        AppInfo(
            id: AppScanner.instanceIdentifier(bundleIdentifier: bundleIdentifier, path: path),
            bundleIdentifier: bundleIdentifier,
            name: name,
            chineseName: chineseName,
            path: path,
            purpose: purpose,
            group: group
        )
    }
}
