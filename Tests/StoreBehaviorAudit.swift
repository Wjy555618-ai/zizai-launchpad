import AppKit
import Foundation

@main
@MainActor
enum StoreBehaviorAudit {
    static func main() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-store-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fakeApps = makeApps()
        let store = LauncherStore(stateDirectory: root, appProvider: { fakeApps })

        testSearch(store)
        testDuplicateAppFamilies(root: root, fakeApps: fakeApps)
        testSameNameDifferentBundleDisambiguation(root: root)
        testLegacyIdentityMigration(root: root, fakeApps: fakeApps)
        testSafeGroupNoOp(store)
        testSafeAppNoOp(root: root, fakeApps: fakeApps)
        testCollisionFreeSwap(store)
        testPersistentUndo(store, root: root, fakeApps: fakeApps)
        testCanvasFitting(store)
        testGeometryUndoExact(root: root, fakeApps: fakeApps)
        testCollisionSafeGroupCommit(root: root, fakeApps: fakeApps)
        testCrossGroupUndo(root: root, fakeApps: fakeApps)
        testStarterGroupDeletion(root: root, fakeApps: fakeApps)
        testHiddenAppLayout(root: root, fakeApps: fakeApps)
        testIncompleteScanPreservesLayout(root: root, fakeApps: fakeApps)

        print("状态闭环验收通过：同 Bundle ID 多实例独立管理、旧布局迁移、即时搜索、安全换序、隐藏应用索引、无重叠交换、无精度漂移撤销、备份恢复、画布适配、分组删除持久化和不完整扫描保护均正常。")
    }

    private static func testSearch(_ store: LauncherStore) {
        store.searchText = "信"
        let ids = Set(store.searchResults.map(\.id))
        require(
            ids.contains(appID("com.tencent.xinWeChat", "/Applications/WeChat.app")),
            "中文单字没有搜索到微信"
        )
        require(
            ids.contains(appID("com.apple.MobileSMS", "/System/Applications/Messages.app")),
            "中文单字没有搜索到信息"
        )

        store.searchText = "fig"
        require(
            store.searchResults.count == 2
                && store.searchResults.allSatisfy {
                    $0.bundleIdentifier == "com.figma.Desktop"
                },
            "强名称命中时仍混入技术字段的模糊噪声"
        )
        store.searchText = "fga"
        require(
            store.searchResults.filter { $0.bundleIdentifier == "com.figma.Desktop" }.count == 2,
            "没有保留用户可见名称的容错搜索"
        )
        store.searchText = "EX"
        require(
            store.searchResults.contains(where: { $0.path.hasSuffix("/Figma+EX.app") }),
            "搜索没有匹配应用包文件名中的版本标识"
        )
        store.clearSearch()
    }

    private static func testDuplicateAppFamilies(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("duplicate-families", isDirectory: true)
        let store = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        let family = store.apps.filter { $0.bundleIdentifier == "com.figma.Desktop" }
        require(family.count == 2, "同 Bundle ID 的应用实例没有全部进入状态层")
        require(Set(family.map(\.id)).count == 2, "同 Bundle ID 的应用实例没有独立标识")

        let first = family[0]
        let second = family[1]
        store.setAlias("客户版 Figma", for: first)
        require(store.displayName(for: second) != "客户版 Figma", "一个实例的别名污染了同系列其他实例")
        store.setHidden(true, for: first)
        require(!store.isHidden(second), "一个实例的隐藏状态污染了同系列其他实例")
        require(store.instanceLabel(for: first) != store.instanceLabel(for: second), "同系列实例没有可见区分标签")
    }

    private static func testSameNameDifferentBundleDisambiguation(root: URL) {
        let directory = root.appendingPathComponent("same-name-different-bundle", isDirectory: true)
        let apps = [
            makeApp(
                bundleIdentifier: "example.figma.stable", name: "Figma", chineseName: "Figma",
                path: "/Applications/Figma.app", purpose: "界面设计", group: .aiCreative
            ),
            makeApp(
                bundleIdentifier: "example.figma.preview", name: "Figma", chineseName: "Figma",
                path: "/Applications/Figma Preview.app", purpose: "界面设计", group: .aiCreative
            ),
        ]
        let store = LauncherStore(stateDirectory: directory, appProvider: { apps })
        let visibleNames = Set(store.apps.map { store.displayName(for: $0) })
        require(visibleNames.count == 2, "不同 Bundle ID 的同名应用仍无法在界面上区分")
        require(
            store.apps.allSatisfy { store.instanceLabel(for: $0) != nil },
            "同名应用没有暴露实例来源"
        )
    }

    private static func testLegacyIdentityMigration(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("identity-migration", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fail("无法创建身份迁移测试目录：\(error.localizedDescription)")
        }

        let legacyID = "com.figma.Desktop"
        var legacy = PersistedState()
        legacy.schemaVersion = 7
        legacy.aliases[legacyID] = "主力 Figma"
        legacy.hiddenAppIDs.insert(legacyID)
        legacy.appGroupIDs[legacyID] = AppGroup.aiCreative.stableID
        legacy.groupAppOrder[AppGroup.aiCreative.stableID] = [legacyID]
        legacy.positions[legacyID] = StoredPoint(x: 120, y: 80)

        do {
            try JSONEncoder().encode(legacy).write(
                to: directory.appendingPathComponent("布局.json"),
                options: .atomic
            )
        } catch {
            fail("无法准备旧身份布局：\(error.localizedDescription)")
        }

        let migrated = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        let family = migrated.apps.filter { $0.bundleIdentifier == legacyID }
        require(family.count == 2, "迁移后同系列应用实例不完整")
        let inherited = family.filter { migrated.displayName(for: $0) == "主力 Figma" }
        require(inherited.count == 1, "旧别名没有且仅有一次迁移到主实例")
        guard let primary = inherited.first else { fail("旧身份没有迁移目标") }
        require(migrated.isHidden(primary), "旧隐藏状态没有迁移")
        require(family.filter { $0.id != primary.id }.allSatisfy { !migrated.isHidden($0) }, "新增实例被错误继承为隐藏")
        require(!migrated.state.appGroupIDs.keys.contains(legacyID), "迁移后仍残留旧 Bundle ID 状态键")
        require(
            migrated.state.groupAppOrder.values.flatMap { $0 }.allSatisfy { $0 != legacyID },
            "迁移后排序仍引用旧 Bundle ID"
        )
        require(migrated.state.schemaVersion == 8, "身份迁移没有更新状态版本")

        let restarted = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        require(
            restarted.apps.filter { $0.bundleIdentifier == legacyID }.count == 2,
            "身份迁移在重启后不稳定"
        )
        require(restarted.displayName(for: primary) == "主力 Figma", "重启后迁移数据丢失")
    }

    private static func testSafeGroupNoOp(_ store: LauncherStore) {
        let before = store.groups.map(\.id)
        guard let first = before.first else { fail("缺少初始分组") }
        store.moveGroup(id: first, toInsertionIndex: 1)
        require(store.groups.map(\.id) == before, "同位置投放导致分组丢失或换位")
    }

    private static func testSafeAppNoOp(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("safe-app-no-op", isDirectory: true)
        let store = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        let groupID = AppGroup.communication.stableID
        let apps = store.apps(in: groupID)
        require(apps.count == 2, "应用安全换序测试数据不完整")

        let before = store.state
        store.move(apps[0], toGroupID: groupID, insertionIndex: 0)
        require(store.state == before, "同位置投放仍然写入状态或污染撤销记录")
        require(!store.canUndo, "同位置投放错误创建了撤销记录")

        guard
            let samePositionPreview = store.resolvedAppMovePreview(
                apps[0],
                to: store.position(for: apps[0])
            )
        else { fail("无法生成同位置摆放预览") }
        store.commitAppMove(apps[0], preview: samePositionPreview)
        require(store.state == before, "空间内同位置摆放仍然写入状态")
        require(!store.canUndo, "空间内同位置摆放错误创建了撤销记录")

        store.setHidden(true, for: apps[1])
        let hiddenState = store.state
        store.move(apps[0], toGroupID: groupID, insertionIndex: 0)
        require(store.state == hiddenState, "隐藏应用干扰了可见应用的同位置投放")
        store.setHidden(false, for: apps[1])
        store.move(apps[1], toGroupID: groupID, insertionIndex: 0)
        require(
            store.apps(in: groupID).map(\.id) == [apps[1].id, apps[0].id],
            "隐藏应用恢复后，可见插入索引发生偏移"
        )
    }

    private static func testCollisionFreeSwap(_ store: LauncherStore) {
        let apps = store.apps(in: AppGroup.communication.stableID)
        require(apps.count >= 2, "沟通分组缺少交换测试应用")
        let first = apps[0]
        let second = apps[1]
        let firstPoint = store.position(for: first)
        let secondPoint = store.position(for: second)
        guard let preview = store.resolvedAppMovePreview(first, to: secondPoint) else {
            fail("无法生成应用交换预览")
        }
        store.commitAppMove(first, preview: preview)
        require(
            store.position(for: first) == secondPoint,
            "拖动应用没有落到目标空位：实际 \(store.position(for: first))，预期 \(secondPoint)"
        )
        require(
            store.position(for: second) == firstPoint,
            "被占应用没有交换到原位置：实际 \(store.position(for: second))，预期 \(firstPoint)"
        )
        require(
            abs(store.position(for: first).x - store.position(for: second).x) >= InteractionGeometry.appCellWidth
                || abs(store.position(for: first).y - store.position(for: second).y)
                    >= InteractionGeometry.appCellHeight,
            "应用交换后仍然重叠"
        )
    }

    private static func testPersistentUndo(
        _ store: LauncherStore,
        root: URL,
        fakeApps: [AppInfo]
    ) {
        guard let app = fakeApps.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }) else {
            fail("缺少撤销测试应用")
        }
        store.setAlias("团队微信", for: app)
        store.dismissToast()
        require(store.canUndo, "提示消失后撤销能力被错误清空")
        store.undoLastAction()
        require(store.displayName(for: app) == app.chineseName, "命令撤销没有恢复应用名称")

        store.setAlias("工作微信", for: app)
        store.setHidden(true, for: app)
        let primary = root.appendingPathComponent("布局.json")
        let backup = root.appendingPathComponent("布局.backup.json")
        require(FileManager.default.fileExists(atPath: backup.path), "连续保存没有生成布局备份")
        do {
            try Data("not-json".utf8).write(to: primary, options: .atomic)
        } catch {
            fail("无法准备恢复测试：\(error.localizedDescription)")
        }

        let recovered = LauncherStore(stateDirectory: root, appProvider: { fakeApps })
        require(recovered.displayName(for: app) == "工作微信", "主文件损坏后没有从备份恢复别名")
    }

    private static func testCanvasFitting(_ store: LauncherStore) {
        let viewport = CGSize(width: 1_200, height: 720)
        store.fitAllGroups(in: viewport)
        require(
            store.canvasScale >= CanvasViewportMetrics.minimumScale
                && store.canvasScale <= CanvasViewportMetrics.overviewMaximumScale,
            "适合全部内容产生非法缩放"
        )
        guard let group = store.groups.first else { fail("缺少画布测试分组") }
        store.focus(on: group.id, in: viewport)
        require(
            store.canvasScale >= CanvasViewportMetrics.focusedMinimumScale
                && store.canvasScale <= CanvasViewportMetrics.focusedMaximumScale,
            "分组定位产生非法缩放"
        )
    }

    private static func testGeometryUndoExact(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("geometry-undo", isDirectory: true)
        let store = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        let groupID = AppGroup.aiCreative.stableID
        guard let group = store.group(withID: groupID) else { fail("缺少几何撤销测试分组") }

        let beforeMove = store.state
        let members = store.assignedApps(in: groupID, includeHidden: false)
        let originalPositions = Dictionary(uniqueKeysWithValues: members.map { ($0.id, store.position(for: $0)) })
        store.commitGroupMove(
            id: groupID,
            originalCenter: group.center.point,
            originalAppPositions: originalPositions,
            delta: CGSize(width: 24.125, height: -16.375)
        )
        require(store.state != beforeMove, "容器移动测试没有产生状态变化")
        store.undoLastAction()
        require(store.state == beforeMove, "容器移动撤销产生精度漂移")

        let beforeResize = store.state
        store.adjustGroupSize(id: groupID, by: 40)
        require(store.state != beforeResize, "容器缩放测试没有产生状态变化")
        store.undoLastAction()
        require(store.state == beforeResize, "容器缩放撤销产生精度漂移")
    }

    private static func testCollisionSafeGroupCommit(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("collision-safe-group-move", isDirectory: true)
        let store = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        let movingID = AppGroup.communication.stableID
        let obstacleID = AppGroup.aiCreative.stableID
        guard let moving = store.group(withID: movingID),
            let obstacle = store.group(withID: obstacleID)
        else {
            fail("缺少容器避碰测试分组")
        }
        let members = store.assignedApps(in: movingID, includeHidden: false)
        let originalPositions = Dictionary(
            uniqueKeysWithValues:
                members.map { ($0.id, store.position(for: $0)) }
        )
        store.commitGroupMove(
            id: movingID,
            originalCenter: moving.center.point,
            originalAppPositions: originalPositions,
            delta: CGSize(
                width: obstacle.center.x - moving.center.x,
                height: obstacle.center.y - moving.center.y
            )
        )
        guard let committed = store.group(withID: movingID) else {
            fail("容器移动提交后分组丢失")
        }
        let committedFrame = CGRect(
            x: committed.center.x - committed.size.width / 2,
            y: committed.center.y - committed.size.height / 2,
            width: committed.size.width,
            height: committed.size.height
        )
        let protectedFrame = CGRect(
            x: obstacle.center.x - obstacle.size.width / 2,
            y: obstacle.center.y - obstacle.size.height / 2,
            width: obstacle.size.width,
            height: obstacle.size.height
        ).insetBy(dx: -42, dy: -42)
        require(!committedFrame.intersects(protectedFrame), "容器仅在预览时避碰，提交时仍发生重叠")

        let actualDelta = CGSize(
            width: committed.center.x - moving.center.x,
            height: committed.center.y - moving.center.y
        )
        for member in members {
            let original = originalPositions[member.id] ?? .zero
            let current = store.position(for: member)
            require(
                abs(current.x - original.x - actualDelta.width) < 0.001
                    && abs(current.y - original.y - actualDelta.height) < 0.001,
                "容器落点纠正后内部应用没有作为整体同步移动"
            )
        }
    }

    private static func testCrossGroupUndo(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("cross-group", isDirectory: true)
        let store = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        guard let app = fakeApps.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }) else {
            fail("缺少跨分组测试应用")
        }
        let before = store.state
        store.move(app, toGroupID: AppGroup.aiCreative.stableID, insertionIndex: 0)
        require(store.group(for: app)?.id == AppGroup.aiCreative.stableID, "跨分组移动没有生效")
        store.undoLastAction()
        require(store.state == before, "跨分组移动撤销没有完整恢复容器和应用布局")
    }

    private static func testStarterGroupDeletion(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("delete-group", isDirectory: true)
        let store = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        let before = store.state
        store.deleteGroup(id: AppGroup.communication.stableID)
        require(
            !store.groups.contains(where: { $0.id == AppGroup.communication.stableID }),
            "删除默认分组后仍残留在当前状态"
        )
        require(
            store.state.deletedStarterGroupIDs.contains(AppGroup.communication.stableID),
            "删除默认分组没有记录持久化意图"
        )
        let restarted = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        require(
            !restarted.groups.contains(where: { $0.id == AppGroup.communication.stableID }),
            "删除的默认分组在重启后错误复活"
        )
        require(
            fakeApps
                .filter { $0.group == .communication }
                .allSatisfy { restarted.group(for: $0) != nil },
            "删除分组后的应用没有安全归入仍存在的分组"
        )
        store.undoLastAction()
        require(store.state == before, "删除分组撤销没有完整恢复原布局")
    }

    private static func testHiddenAppLayout(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("hidden-layout", isDirectory: true)
        let store = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        guard let app = fakeApps.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }) else {
            fail("缺少隐藏布局测试应用")
        }
        let before = store.state
        store.setHidden(true, for: app)
        require(
            store.appCount(in: AppGroup.communication.stableID) == 1,
            "隐藏应用仍被计入空间卡片数量"
        )
        store.setHidden(false, for: app)
        require(
            store.appCount(in: AppGroup.communication.stableID) == 2,
            "恢复显示后空间卡片数量没有更新"
        )
        let visible = store.assignedApps(
            in: AppGroup.communication.stableID,
            includeHidden: false
        )
        require(visible.count == 2, "恢复显示后应用没有回到可见布局")
        require(
            abs(store.position(for: visible[0]).x - store.position(for: visible[1]).x)
                >= InteractionGeometry.appCellWidth
                || abs(store.position(for: visible[0]).y - store.position(for: visible[1]).y)
                    >= InteractionGeometry.appCellHeight,
            "恢复显示后应用发生重叠"
        )
        store.undoLastAction()
        store.undoLastAction()
        require(store.state == before, "隐藏与恢复显示的连续撤销没有回到初始布局")
    }

    private static func testIncompleteScanPreservesLayout(root: URL, fakeApps: [AppInfo]) {
        let directory = root.appendingPathComponent("incomplete-scan", isDirectory: true)
        guard let protectedApp = fakeApps.last else {
            fail("测试数据缺少需要保护的应用")
        }
        let completeStore = LauncherStore(stateDirectory: directory, appProvider: { fakeApps })
        completeStore.setAlias("保留的用户应用", for: protectedApp)

        let partialApps = Array(fakeApps.dropLast())
        let incompleteStore = LauncherStore(
            stateDirectory: directory,
            appProvider: { partialApps },
            isAppScanComplete: { false }
        )
        require(
            incompleteStore.state.aliases[protectedApp.id] == "保留的用户应用",
            "用户文件夹未授权时破坏了缺席应用的布局数据"
        )

        let confirmedCompleteStore = LauncherStore(
            stateDirectory: directory,
            appProvider: { partialApps }
        )
        require(
            confirmedCompleteStore.state.aliases[protectedApp.id] == nil,
            "完整扫描后没有清理已确认移除的应用数据"
        )
    }

    private static func makeApps() -> [AppInfo] {
        [
            makeApp(
                bundleIdentifier: "com.tencent.xinWeChat", name: "WeChat", chineseName: "微信",
                path: "/Applications/WeChat.app", purpose: "微信", group: .communication
            ),
            makeApp(
                bundleIdentifier: "com.apple.MobileSMS", name: "Messages", chineseName: "信息",
                path: "/System/Applications/Messages.app", purpose: "即时沟通", group: .communication
            ),
            makeApp(
                bundleIdentifier: "com.openai.codex", name: "Codex", chineseName: "Codex",
                path: "/Applications/Codex.app", purpose: "代码助手", group: .aiCreative
            ),
            makeApp(
                bundleIdentifier: "com.figma.Desktop", name: "Figma", chineseName: "Figma",
                path: "/Applications/Figma.app", purpose: "界面设计", group: .aiCreative
            ),
            makeApp(
                bundleIdentifier: "com.figma.Desktop", name: "Figma", chineseName: "Figma",
                path: "/Applications/Figma+EX.app", purpose: "界面设计", group: .aiCreative
            ),
        ]
    }

    private static func makeApp(
        bundleIdentifier: String,
        name: String,
        chineseName: String,
        path: String,
        purpose: String,
        group: AppGroup
    ) -> AppInfo {
        AppInfo(
            id: appID(bundleIdentifier, path),
            bundleIdentifier: bundleIdentifier,
            name: name,
            chineseName: chineseName,
            path: path,
            purpose: purpose,
            group: group
        )
    }

    private static func appID(_ bundleIdentifier: String, _ path: String) -> String {
        AppScanner.instanceIdentifier(bundleIdentifier: bundleIdentifier, path: path)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("状态闭环验收失败：\(message)\n".utf8))
        exit(1)
    }
}
