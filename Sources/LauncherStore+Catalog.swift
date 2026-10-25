import AppKit
import Foundation

// Catalog queries and commands form one explicit domain boundary. The store
// remains the single observable aggregate; this extension contains no parallel
// state and delegates matching/reconciliation to pure domain services.
extension LauncherStore {
    // MARK: - Derived application collections

    var groups: [UserGroup] { state.userGroups }

    var visibleApps: [AppInfo] {
        sortedApps(includeHidden: false)
    }

    var allFilteredApps: [AppInfo] {
        sortedApps(includeHidden: true)
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var searchResults: [AppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let matches = apps.compactMap { app -> (value: AppInfo, match: ApplicationSearchMatch)? in
            guard
                let match = ApplicationSearchPolicy.match(
                    query: query,
                    document: searchDocument(for: app)
                )
            else { return nil }
            return (app, match)
        }
        return ApplicationSearchPolicy.preferredMatches(matches)
            .sorted { lhs, rhs in
                if lhs.match != rhs.match { return lhs.match < rhs.match }
                return displayName(for: lhs.value)
                    .localizedStandardCompare(displayName(for: rhs.value)) == .orderedAscending
            }
            .map(\.value)
    }

    var canvasOffset: CGSize {
        CGSize(width: state.canvasOffsetX, height: state.canvasOffsetY)
    }

    var canvasScale: CGFloat { CGFloat(state.canvasScale) }

    // MARK: - Application discovery and identity

    func reloadApps(announce: Bool = false, persist: Bool = true) {
        guard let asyncAppProvider else {
            applyScannedApps(appProvider(), announce: announce, persist: persist)
            return
        }

        reloadTask?.cancel()
        reloadGeneration += 1
        let generation = reloadGeneration
        isReloadingApps = true
        reloadTask = Task { @MainActor [weak self] in
            let scannedApps = await asyncAppProvider()
            guard let self,
                !Task.isCancelled,
                generation == self.reloadGeneration
            else { return }

            await self.appPreparer(scannedApps)
            guard !Task.isCancelled,
                generation == self.reloadGeneration
            else { return }

            self.applyScannedApps(scannedApps, announce: announce, persist: persist)
            self.isReloadingApps = false
            self.reloadTask = nil
        }
    }

    private func applyScannedApps(_ scannedApps: [AppInfo], announce: Bool, persist: Bool) {
        apps = scannedApps
        bundleInstanceCounts = Dictionary(grouping: apps, by: \.bundleIdentifier)
            .mapValues(\.count)
        let needsIdentityVersionBump = LauncherStateReconciler.migrateApplicationIdentityIfNeeded(
            state: &state,
            apps: apps
        )
        rebuildDisplayNameCounts()
        LauncherStateReconciler.ensureStarterGroups(state: &state, apps: apps)
        LauncherStateReconciler.seedMissingAssignments(state: &state, apps: apps)
        let displayNamesByID = Dictionary(
            uniqueKeysWithValues: apps.map { ($0.id, displayName(for: $0)) }
        )
        LauncherStateReconciler.ensureAppOrder(
            state: &state,
            apps: apps,
            displayNamesByID: displayNamesByID
        )
        LauncherStateReconciler.seedMissingPositions(
            state: &state,
            apps: apps,
            displayNamesByID: displayNamesByID
        )
        LauncherStateReconciler.migrateUnsafeLayoutIfNeeded(
            state: &state,
            apps: apps,
            displayNamesByID: displayNamesByID,
            schemaVersion: layoutSafetySchemaVersion
        )
        if needsIdentityVersionBump {
            state.schemaVersion = LauncherStateReconciler.applicationIdentitySchemaVersion
        }
        LauncherStateReconciler.repairSpatialIntegrity(
            state: &state,
            apps: apps,
            displayNamesByID: displayNamesByID
        )
        // A missing user-folder grant makes this scan intentionally partial.
        // Keep persisted aliases, placements and assignments until the user
        // restores access; otherwise a permission transition would silently
        // destroy layout data for apps that still exist.
        if isAppScanComplete() {
            LauncherStateReconciler.pruneMissingApps(
                state: &state,
                existingAppIDs: Set(apps.map(\.id))
            )
        }
        if persist { save() }
        if announce {
            presentToast("已重新扫描，共找到 \(apps.count) 个应用")
        }
    }

    func displayName(for app: AppInfo) -> String {
        let base = editableDisplayName(for: app)
        guard displayNameCounts[displayNameKey(base), default: 0] > 1 else { return base }
        return "\(base) · \(instanceSourceLabel(for: app))"
    }

    func editableDisplayName(for app: AppInfo) -> String {
        state.aliases[app.id]?.zizaiVisibleNonEmpty
            ?? app.chineseName.zizaiVisibleNonEmpty
            ?? app.name.zizaiVisibleNonEmpty
            ?? URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent.zizaiVisibleNonEmpty
            ?? "未命名应用"
    }

    func instanceLabel(for app: AppInfo) -> String? {
        let hasBundleCollision = bundleInstanceCounts[app.bundleIdentifier, default: 0] > 1
        let hasNameCollision = displayNameCounts[displayNameKey(editableDisplayName(for: app)), default: 0] > 1
        guard hasBundleCollision || hasNameCollision else { return nil }
        return instanceSourceLabel(for: app)
    }

    func setAlias(_ alias: String, for app: AppInfo) {
        let previousState = state
        let trimmed = alias.zizaiVisibleTrimmed
        if trimmed.isEmpty || trimmed == app.chineseName {
            state.aliases.removeValue(forKey: app.id)
        } else {
            state.aliases[app.id] = trimmed
        }
        commitStateMutation(
            from: previousState,
            message: "名称已更新",
            rebuildCatalogIndex: true
        )
    }

    func rebuildDisplayNameCounts() {
        displayNameCounts = Dictionary(grouping: apps, by: { displayNameKey(editableDisplayName(for: $0)) })
            .mapValues(\.count)
    }

    private func displayNameKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .zizaiVisibleTrimmed
    }

    private func instanceSourceLabel(for app: AppInfo) -> String {
        URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
    }

    func isHidden(_ app: AppInfo) -> Bool {
        state.hiddenAppIDs.contains(app.id)
    }

    func setHidden(_ hidden: Bool, for app: AppInfo) {
        guard isHidden(app) != hidden else { return }
        let previousState = state
        let groupID = state.appGroupIDs[app.id] ?? app.group.stableID
        if hidden {
            state.hiddenAppIDs.insert(app.id)
        } else {
            state.hiddenAppIDs.remove(app.id)
        }
        repairSpatialState(affectedGroupIDs: [groupID])
        commitStateMutation(
            from: previousState,
            message: hidden ? "已从“空间”和“分组”中隐藏" : "已恢复显示"
        )
    }

    func position(for app: AppInfo) -> CGPoint {
        state.positions[app.id]?.point ?? .zero
    }

    func updatePosition(_ point: CGPoint, for app: AppInfo, persist: Bool) {
        state.positions[app.id] = StoredPoint(point)
        objectWillChange.send()
        if persist { save() }
    }

    func updatePositions(_ positions: [String: CGPoint], persist: Bool) {
        for (id, point) in positions {
            state.positions[id] = StoredPoint(point)
        }
        objectWillChange.send()
        if persist { save() }
    }

    // MARK: - Group membership and ordering

    func group(for app: AppInfo) -> UserGroup? {
        let groupID = state.appGroupIDs[app.id] ?? app.group.stableID
        return group(withID: groupID)
    }

    func group(withID id: String) -> UserGroup? {
        state.userGroups.first(where: { $0.id == id })
    }

    func apps(in groupID: String, includeHidden: Bool = false) -> [AppInfo] {
        let candidates =
            apps
            .filter { includeHidden || !state.hiddenAppIDs.contains($0.id) }
            .filter { (state.appGroupIDs[$0.id] ?? $0.group.stableID) == groupID }
        let order = state.groupAppOrder[groupID] ?? []
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return candidates.sorted { lhs, rhs in
            let left = rank[lhs.id] ?? .max
            let right = rank[rhs.id] ?? .max
            if left != right { return left < right }
            return displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    func orderedAssignedApps(
        in groupID: String,
        includeHidden: Bool = true
    ) -> [AppInfo] {
        let candidates =
            apps
            .filter { includeHidden || !state.hiddenAppIDs.contains($0.id) }
            .filter { (state.appGroupIDs[$0.id] ?? $0.group.stableID) == groupID }
        let order = state.groupAppOrder[groupID] ?? []
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return candidates.sorted { lhs, rhs in
            let left = rank[lhs.id] ?? .max
            let right = rank[rhs.id] ?? .max
            if left != right { return left < right }
            return displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    func assignedApps(in groupID: String, includeHidden: Bool = true) -> [AppInfo] {
        apps
            .filter { includeHidden || !state.hiddenAppIDs.contains($0.id) }
            .filter { (state.appGroupIDs[$0.id] ?? $0.group.stableID) == groupID }
    }

    func appCount(in groupID: String) -> Int {
        assignedApps(in: groupID, includeHidden: false).count
    }

    // MARK: - System actions, search, and undo

    func launch(_ app: AppInfo) {
        let succeeded = NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
        if !succeeded {
            errorMessage = "无法打开“\(displayName(for: app))”。应用可能已被移动或删除。"
        } else {
            errorMessage = nil
        }
    }

    func revealInFinder(_ app: AppInfo) {
        NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
    }

    func completeWelcome() {
        state.hasSeenWelcome = true
        objectWillChange.send()
        save()
    }

    func requestFocusSearch() {
        focusSearchToken = UUID()
    }

    func requestNewGroup() {
        newGroupToken = UUID()
    }

    func refreshSearchSelection() {
        let resultIDs = searchResults.map(\.id)
        guard !resultIDs.isEmpty else {
            if currentSearchResultID != nil { currentSearchResultID = nil }
            return
        }
        if let currentSearchResultID, resultIDs.contains(currentSearchResultID) { return }
        currentSearchResultID = resultIDs[0]
    }

    func advanceSearchResult() {
        let resultIDs = searchResults.map(\.id)
        guard !resultIDs.isEmpty else {
            currentSearchResultID = nil
            return
        }
        guard let currentSearchResultID,
            let index = resultIDs.firstIndex(of: currentSearchResultID)
        else {
            self.currentSearchResultID = resultIDs[0]
            return
        }
        self.currentSearchResultID = resultIDs[(index + 1) % resultIDs.count]
    }

    func clearSearch() {
        searchText = ""
        currentSearchResultID = nil
    }

    private func sortedApps(includeHidden: Bool) -> [AppInfo] {
        return
            apps
            .filter { includeHidden || !state.hiddenAppIDs.contains($0.id) }
            .sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending }
    }

    private func searchDocument(for app: AppInfo) -> ApplicationSearchDocument {
        ApplicationCatalogLogic.searchDocument(
            for: app,
            displayName: displayName(for: app),
            groupName: group(for: app)?.name ?? ""
        )
    }
}
