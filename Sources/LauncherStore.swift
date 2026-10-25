import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let zizaiLayoutModeRequested = Notification.Name("ZizaiLayoutModeRequested")
}

@MainActor
final class LauncherStore: ObservableObject {
    // MARK: - Published application state

    @Published var apps: [AppInfo] = []
    @Published var state: PersistedState
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var toast: ToastNotice?
    @Published var dropTargetGroupID: String?
    @Published var selectedGroupID: String?
    @Published var currentSearchResultID: String?
    @Published var canUndo = false
    @Published var isReloadingApps = false
    @Published var focusSearchToken = UUID()
    @Published var newGroupToken = UUID()

    private let stateURL: URL
    private let backupStateURL: URL
    let appProvider: () -> [AppInfo]
    let asyncAppProvider: (@MainActor () async -> [AppInfo])?
    let appPreparer: @MainActor ([AppInfo]) async -> Void
    let isAppScanComplete: () -> Bool
    private let backgroundPersistenceEnabled: Bool
    private let persistenceWriter: StatePersistenceWriter
    private var layoutModeSaveTask: Task<Void, Never>?
    var reloadTask: Task<Void, Never>?
    private var pendingLayoutMode: LayoutMode?
    var reloadGeneration = 0
    private var persistenceRevision = 0
    var bundleInstanceCounts: [String: Int] = [:]
    var displayNameCounts: [String: Int] = [:]
    var stateHistory = LauncherStateHistory()
    var canvasViewport = CGSize(width: 1_200, height: 700)
    var lastCanvasZoomAnchor: CGPoint?
    let layoutSafetySchemaVersion = 7

    // MARK: - Lifecycle

    init(
        stateDirectory: URL? = nil,
        appProvider: @escaping () -> [AppInfo] = { AppScanner.scan() },
        asyncAppProvider: (@MainActor () async -> [AppInfo])? = nil,
        appPreparer: @escaping @MainActor ([AppInfo]) async -> Void = { _ in },
        isAppScanComplete: @escaping () -> Bool = { true },
        backgroundPersistenceEnabled: Bool = false
    ) {
        let support =
            stateDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("自在启动台", isDirectory: true)
        self.appProvider = appProvider
        self.asyncAppProvider = asyncAppProvider
        self.appPreparer = appPreparer
        self.isAppScanComplete = isAppScanComplete
        self.backgroundPersistenceEnabled = backgroundPersistenceEnabled
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        } catch {
            errorMessage = "无法创建布局存储目录：\(error.localizedDescription)"
        }
        stateURL = support.appendingPathComponent("布局.json")
        backupStateURL = support.appendingPathComponent("布局.backup.json")
        persistenceWriter = StatePersistenceWriter(
            stateURL: stateURL,
            backupStateURL: backupStateURL
        )

        let primaryData = try? Data(contentsOf: stateURL)
        let primaryState = primaryData.flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        let backupData = try? Data(contentsOf: backupStateURL)
        let backupState = backupData.flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        var recoveryNotice: String?

        if let saved = primaryState {
            state = saved
        } else if let saved = backupState {
            state = saved
            recoveryNotice = "主布局文件异常，已从安全备份恢复"
        } else {
            state = PersistedState()
            if let primaryData {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let corruptURL = support.appendingPathComponent("布局.corrupt-\(formatter.string(from: Date())).json")
                do {
                    try primaryData.write(to: corruptURL, options: .atomic)
                    recoveryNotice = "旧布局文件异常，已保留原文件并创建安全布局"
                } catch {
                    recoveryNotice = "旧布局文件异常；原文件未被覆盖"
                }
            }
        }

        if asyncAppProvider == nil {
            reloadApps(persist: false)
            save()
        } else {
            reloadApps(persist: true)
        }
        if let recoveryNotice {
            presentToast(recoveryNotice)
        }
    }

    // MARK: - Layout mode and persistence cadence

    var layoutMode: LayoutMode {
        get { pendingLayoutMode ?? state.layoutMode }
        set {
            guard layoutMode != newValue else { return }
            pendingLayoutMode = newValue
            objectWillChange.send()
            scheduleLayoutModeSave()
        }
    }

    /// Used by the top switcher after its lightweight presentation state has
    /// already changed. No global publication is emitted here: a tab click
    /// must not invalidate every icon and card merely to persist one enum.
    func stageLayoutModePersistence(_ mode: LayoutMode) {
        guard layoutMode != mode else { return }
        pendingLayoutMode = mode
        scheduleLayoutModeSave()
    }

    /// Secondary navigation actions (menus and contextual commands) use a
    /// focused request instead of broadcasting a full store invalidation.
    func requestLayoutMode(_ mode: LayoutMode) {
        stageLayoutModePersistence(mode)
        NotificationCenter.default.post(name: .zizaiLayoutModeRequested, object: mode)
    }

    /// Tab selection must update on the current frame. Persistence is
    /// intentionally coalesced until the short selection animation is over so
    /// JSON validation and atomic disk writes never run in the click path.
    private func scheduleLayoutModeSave() {
        layoutModeSaveTask?.cancel()
        layoutModeSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.layoutModeSaveTask = nil
            self.persistState()
        }
    }

    func flushPendingPersistence() {
        layoutModeSaveTask?.cancel()
        layoutModeSaveTask = nil
        persistenceRevision += 1
        let snapshot = persistenceSnapshot()
        do {
            if backgroundPersistenceEnabled {
                try persistenceWriter.flush(snapshot: snapshot, revision: persistenceRevision)
            } else {
                try PersistedStateIO.write(
                    snapshot,
                    stateURL: stateURL,
                    backupStateURL: backupStateURL
                )
            }
        } catch {
            reportPersistenceFailure(error)
        }
    }

    // MARK: - Cleanup, feedback, and persistence

    @discardableResult
    func commitStateMutation(
        from previousState: PersistedState,
        message: String,
        rebuildCatalogIndex: Bool = false
    ) -> Bool {
        guard state != previousState else { return false }
        if rebuildCatalogIndex {
            rebuildDisplayNameCounts()
        }
        stateHistory.record(previous: previousState, current: state)
        canUndo = stateHistory.canUndo
        objectWillChange.send()
        save()
        presentToast(message, actionTitle: "撤销")
        return true
    }

    func undoLastAction() {
        guard let previousState = stateHistory.popLast() else { return }
        state = previousState
        rebuildDisplayNameCounts()
        canUndo = stateHistory.canUndo
        toast = nil
        save()
        announce("已撤销上一步操作")
    }

    func dismissToast() {
        toast = nil
    }

    func presentToast(_ message: String, actionTitle: String? = nil) {
        let notice = ToastNotice(message: message, actionTitle: actionTitle)
        toast = notice
        announce(message)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, self.toast?.id == notice.id else { return }
            self.toast = nil
        }
    }

    func save() {
        layoutModeSaveTask?.cancel()
        layoutModeSaveTask = nil
        persistState()
    }

    private func persistState() {
        persistenceRevision += 1
        let revision = persistenceRevision
        let snapshot = persistenceSnapshot()

        if backgroundPersistenceEnabled {
            persistenceWriter.enqueue(snapshot: snapshot, revision: revision) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    self?.reportPersistenceFailure(error)
                }
            }
            return
        }

        do {
            try PersistedStateIO.write(
                snapshot,
                stateURL: stateURL,
                backupStateURL: backupStateURL
            )
        } catch {
            reportPersistenceFailure(error)
        }
    }

    private func persistenceSnapshot() -> PersistedState {
        var snapshot = state
        snapshot.layoutMode = layoutMode
        return snapshot
    }

    private func reportPersistenceFailure(_ error: Error) {
        errorMessage = "布局未能安全保存：\(error.localizedDescription)"
        announce("布局保存失败")
    }

    func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}
