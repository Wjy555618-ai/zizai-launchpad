import AppKit
import Combine
import Foundation

enum ApplicationRemovalFlowState: Equatable {
    case idle
    case presenting(ApplicationRemovalDialog)
    case selectingAuthorization(AppInfo)
    case awaitingAppManagementPermission(AppInfo)
    case recycling(AppInfo)
    case completing(AppInfo)
}

@MainActor
final class ApplicationRemovalCoordinator: ObservableObject {
    @Published private(set) var managementPhase: ApplicationManagementPhase = .inactive
    @Published private(set) var appManagementUnavailableAppIDs: Set<String> = []
    @Published var removalFlow: ApplicationRemovalFlowState = .idle {
        didSet { refreshInactivityTimer() }
    }

    var dialog: ApplicationRemovalDialog? {
        guard case .presenting(let dialog) = removalFlow else { return nil }
        return dialog
    }

    var isChoosingAuthorizationFolder: Bool {
        if case .selectingAuthorization = removalFlow { return true }
        return false
    }

    var isAwaitingAppManagementPermission: Bool {
        if case .awaitingAppManagementPermission = removalFlow { return true }
        return false
    }

    var isManaging: Bool {
        managementPhase == .entering || managementPhase == .active
    }
    var isManagementPresented: Bool { managementPhase != .inactive }

    private let authorizer: any ApplicationRemovalAuthorizing
    private let authorizationPresenter: any ApplicationRemovalAuthorizationPresenting
    private let runningDetector: any ApplicationRunningDetecting
    private let recycler: any ApplicationRecycling
    private let appManagementPermissionOpener: any ApplicationManagementPermissionOpening
    let removalFeedbackPlayer: any ApplicationRemovalFeedbackPlaying
    let successfulRemovalFeedbackDuration: TimeInterval
    let onRemovalCompleted: (AppInfo) -> Void
    let managementInactivityNanoseconds: UInt64
    var inactivityTask: Task<Void, Never>?
    var phaseTransitionTask: Task<Void, Never>?
    var removalCompletionTask: Task<Void, Never>?
    var interactionRevision: UInt64 = 0
    var ignoresNextPointerUp = false

    init(
        authorizer: any ApplicationRemovalAuthorizing,
        authorizationPresenter: (any ApplicationRemovalAuthorizationPresenting)? = nil,
        runningDetector: (any ApplicationRunningDetecting)? = nil,
        recycler: (any ApplicationRecycling)? = nil,
        appManagementPermissionOpener: (any ApplicationManagementPermissionOpening)? = nil,
        removalFeedbackPlayer: (any ApplicationRemovalFeedbackPlaying)? = nil,
        successfulRemovalFeedbackDuration: TimeInterval? = nil,
        managementInactivityTimeout: TimeInterval = ApplicationManagementPolicy.inactivityTimeout(),
        onRemovalCompleted: @escaping (AppInfo) -> Void
    ) {
        self.authorizer = authorizer
        self.authorizationPresenter =
            authorizationPresenter ?? ApplicationRemovalOpenPanelPresenter()
        self.runningDetector = runningDetector ?? WorkspaceApplicationRunningDetector()
        self.recycler = recycler ?? FileManagerApplicationRecycler()
        self.appManagementPermissionOpener =
            appManagementPermissionOpener ?? WorkspaceApplicationManagementPermissionOpener()
        self.removalFeedbackPlayer =
            removalFeedbackPlayer ?? BundledApplicationRemovalFeedbackPlayer()
        self.successfulRemovalFeedbackDuration = max(
            0.01,
            successfulRemovalFeedbackDuration
                ?? ApplicationManagementMotion.removalDuration(
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                )
        )
        let timeout = max(0.01, managementInactivityTimeout)
        managementInactivityNanoseconds = UInt64(timeout * 1_000_000_000)
        self.onRemovalCompleted = onRemovalCompleted
    }

    func requestRemoval(of app: AppInfo) {
        beginManagement(trigger: .removalRequest)
        guard case .idle = removalFlow else {
            noteActivity()
            return
        }
        switch removalCapability(for: app) {
        case .temporarilyUnavailable:
            present(ApplicationRemovalFailurePresentation.unavailableDialog(for: app))
            return
        case .protected(let reason):
            present(
                ApplicationRemovalDialog(
                    kind: .blocked,
                    app: app,
                    title: "无法移除“\(app.chineseName)”",
                    message: reason
                )
            )
            return
        case .removable:
            break
        }

        guard !runningDetector.isRunning(app) else {
            present(
                ApplicationRemovalDialog(
                    kind: .running,
                    app: app,
                    title: "请先退出“\(app.chineseName)”",
                    message: "自在启动台不会强制结束正在运行的应用。请正常退出应用后再试。"
                )
            )
            return
        }

        let applicationURL = URL(fileURLWithPath: app.path)
        guard authorizer.hasRemovalAuthorization(for: applicationURL) else {
            beginAuthorizationSelection(for: app)
            return
        }

        presentConfirmation(for: app)
    }

    func beginAuthorizationSelection(for requestedApp: AppInfo? = nil) {
        let app: AppInfo?
        switch removalFlow {
        case .presenting(let dialog) where dialog.kind == .authorization:
            app = dialog.app
        case .idle:
            // SwiftUI clears an Alert binding while dispatching its button
            // action. The dialog carries the app explicitly so that legitimate
            // handoff can start from idle without reopening parallel state.
            app = requestedApp
        case .selectingAuthorization, .awaitingAppManagementPermission, .recycling,
            .completing, .presenting:
            app = nil
        }
        guard let app else { return }

        removalFlow = .selectingAuthorization(app)
        interactionRevision &+= 1
        authorizationPresenter.selectContainer(for: app) { [weak self] selection in
            self?.completeAuthorizationSelection(selection, for: app)
        }
    }

    func cancelAuthorizationSelection() {
        authorizationPresenter.cancelSelection()
        if case .selectingAuthorization = removalFlow {
            removalFlow = .idle
        } else if case .presenting(let dialog) = removalFlow,
            dialog.kind == .authorization
        {
            removalFlow = .idle
        }
    }

    func dismissDialog() {
        guard case .presenting = removalFlow else { return }
        removalFlow = .idle
    }

    func confirmRemoval(of app: AppInfo) {
        guard isRemovingAppID == nil else { return }
        removalFlow = .idle

        performConfirmedRemoval(of: app)
    }

    func openAppManagementSettings(for requestedApp: AppInfo? = nil) {
        let app: AppInfo?
        switch removalFlow {
        case .presenting(let dialog) where dialog.kind == .appManagementPermission:
            app = dialog.app
        case .idle:
            // SwiftUI can clear the Alert binding before dispatching the
            // button action, so the explicit app remains the handoff token.
            app = requestedApp
        case .selectingAuthorization, .awaitingAppManagementPermission, .recycling,
            .completing, .presenting:
            app = nil
        }
        guard let app else { return }

        removalFlow = .awaitingAppManagementPermission(app)
        interactionRevision &+= 1
        guard appManagementPermissionOpener.openAppManagementSettings() else {
            present(
                ApplicationRemovalDialog(
                    kind: .failure,
                    app: app,
                    title: "未能打开“应用管理”设置",
                    message: "请打开系统设置，在“隐私与安全性 > 应用管理”中开启“自在启动台”，然后重新移除应用。\n\n原应用没有被自在启动台改动。"
                )
            )
            return
        }
    }

    func applicationDidBecomeActive() {
        guard case .awaitingAppManagementPermission(let app) = removalFlow else { return }
        removalFlow = .idle
        interactionRevision &+= 1
        // One automatic retry completes the promised handoff. A second
        // permission-shaped error is reported as the real terminal failure;
        // it must never reopen the same settings loop.
        performConfirmedRemoval(of: app, canOfferAppManagementPermission: false)
    }

    private func performConfirmedRemoval(
        of app: AppInfo,
        canOfferAppManagementPermission: Bool = true
    ) {
        switch removalCapability(for: app) {
        case .temporarilyUnavailable:
            present(ApplicationRemovalFailurePresentation.unavailableDialog(for: app))
            return
        case .protected(let reason):
            present(
                ApplicationRemovalDialog(
                    kind: .blocked,
                    app: app,
                    title: "无法移除“\(app.chineseName)”",
                    message: reason
                )
            )
            return
        case .removable:
            break
        }
        guard !runningDetector.isRunning(app) else {
            requestRemoval(of: app)
            return
        }

        let applicationURL = URL(fileURLWithPath: app.path)
        guard let authorizedFolder = authorizer.beginRemovalAccess(for: applicationURL) else {
            presentAuthorizationFailure(for: app)
            return
        }

        removalFlow = .recycling(app)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.authorizer.endRemovalAccess(authorizedFolder)
            }
            do {
                _ = try await self.recycler.recycle(applicationURL)
                self.beginSuccessfulRemovalFeedback(for: app)
            } catch {
                self.presentRecycleFailure(
                    error,
                    for: app,
                    applicationURL: applicationURL,
                    canOfferAppManagementPermission: canOfferAppManagementPermission
                )
            }
        }
    }

    private func presentRecycleFailure(
        _ error: Error,
        for app: AppInfo,
        applicationURL: URL,
        canOfferAppManagementPermission: Bool
    ) {
        let dialog = ApplicationRemovalFailurePresentation.dialog(
            for: error,
            app: app,
            applicationURL: applicationURL,
            canOfferAppManagementPermission: canOfferAppManagementPermission
        )
        if dialog.kind == .appManagementUnavailable {
            appManagementUnavailableAppIDs.insert(app.id)
        }
        present(dialog)
    }

    private func presentConfirmation(for app: AppInfo) {
        present(
            ApplicationRemovalDialog(
                kind: .confirmation,
                app: app,
                title: "将“\(app.chineseName)”移到废纸篓？",
                message: "会移动完整的 .app 应用包。不会清理缓存、设置、文稿、账号、订阅或厂商安装的其他组件。\n\n清空废纸篓前，可以在访达中恢复应用。"
            )
        )
    }

    private func presentAuthorizationFailure(for app: AppInfo) {
        let applicationURL = URL(fileURLWithPath: app.path).standardizedFileURL
        let folderName = Self.authorizationFolderDisplayName(for: applicationURL)
        present(
            ApplicationRemovalDialog(
                kind: .authorization,
                app: app,
                title: "未能授权“\(folderName)”",
                message:
                    "\(authorizer.removalErrorMessage ?? "没有获得可用的文件夹读写授权。")\n\n"
                    + "点击“重新授权”后，无需查找或选择任何应用。"
                    + "原应用没有被自在启动台改动。"
            )
        )
    }

    private func completeAuthorizationSelection(
        _ selection: ApplicationRemovalAuthorizationSelection,
        for app: AppInfo
    ) {
        guard case .selectingAuthorization(let pendingApp) = removalFlow,
            pendingApp.id == app.id
        else { return }

        switch selection {
        case .selected(let folder):
            let applicationURL = URL(fileURLWithPath: app.path)
            guard authorizer.authorizeRemoval(folder: folder, containing: applicationURL) else {
                presentAuthorizationFailure(for: app)
                return
            }
            presentConfirmation(for: app)
        case .cancelled:
            removalFlow = .idle
        case .failed(let error):
            authorizer.reportRemovalSelectionError(error)
            presentAuthorizationFailure(for: app)
        }
    }

    private func present(_ dialog: ApplicationRemovalDialog) {
        removalFlow = .presenting(dialog)
    }

    private static func authorizationFolderDisplayName(for applicationURL: URL) -> String {
        let folder = ApplicationRemovalAuthorizationScope.folder(containing: applicationURL)
        return ApplicationRemovalAuthorizationScope.displayName(for: folder)
    }

    var hasBlockingInteraction: Bool {
        removalFlow != .idle
    }

    func transitionManagementPhase(to phase: ApplicationManagementPhase) {
        managementPhase = phase
    }
}
