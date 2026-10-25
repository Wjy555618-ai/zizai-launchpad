import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configuredWindowNumber: Int?
    private var presentationState = LaunchPresentationState(isLoginItemLaunch: false)
    private var presentationGeneration = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ZizaiLaunchConfiguration.launchMode() != .unitTestHost else {
            NSApplication.shared.setActivationPolicy(.accessory)
            return
        }
        let isLoginItemLaunch = LoginItemLaunchDetector.isLoginItemLaunch()
        presentationState = LaunchPresentationState(isLoginItemLaunch: isLoginItemLaunch)
        // A login item is background preparation, not a visible app launch.
        // Starting as an accessory keeps it out of the Dock and avoids an
        // app-caused activation bounce. A user-requested presentation below
        // promotes the same process back to a regular foreground app.
        NSApplication.shared.setActivationPolicy(isLoginItemLaunch ? .accessory : .regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ZizaiLaunchConfiguration.launchMode() != .unitTestHost else { return }
        perform(presentationState.applicationDidFinishLaunching())
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ZizaiLaunchConfiguration.launchMode() != .unitTestHost else { return }
        perform(presentationState.applicationDidBecomeActive())
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard ZizaiLaunchConfiguration.launchMode() != .unitTestHost else { return false }
        perform(presentationState.userRequestedPresentation())
        return true
    }

    func applicationDidUnhide(_ notification: Notification) {
        guard ZizaiLaunchConfiguration.launchMode() != .unitTestHost else { return }
        guard presentationState.isSilentLoginLaunch else { return }
        perform(presentationState.userRequestedPresentation())
    }

    private func perform(_ action: LaunchPresentationAction) {
        presentationGeneration += 1
        let generation = presentationGeneration
        switch action {
        case .present:
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.unhide(nil)
            presentMainWindow(retriesRemaining: 30, generation: generation)
        case .suppress:
            NSApplication.shared.setActivationPolicy(.accessory)
            suppressMainWindow(retriesRemaining: 30, generation: generation)
        case .none:
            break
        }
    }

    private func presentMainWindow(retriesRemaining: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, generation == self.presentationGeneration else { return }
            guard let window = self.mainWindow else {
                if retriesRemaining > 0 {
                    self.presentMainWindow(
                        retriesRemaining: retriesRemaining - 1,
                        generation: generation
                    )
                }
                return
            }

            self.configure(window)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeFirstResponder(nil)
        }
    }

    private func suppressMainWindow(retriesRemaining: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, generation == self.presentationGeneration else { return }

            if let window = self.mainWindow {
                self.configure(window)
                window.orderOut(nil)
            }
            NSApplication.shared.hide(nil)

            guard retriesRemaining > 0 else {
                self.presentationState.silentSuppressionDidSettle()
                return
            }
            self.suppressMainWindow(
                retriesRemaining: retriesRemaining - 1,
                generation: generation
            )
        }
    }

    private var mainWindow: NSWindow? {
        let candidates = NSApplication.shared.windows.filter { !$0.isKind(of: NSPanel.self) }
        return candidates.first(where: { $0.title == "自在启动台" }) ?? candidates.first
    }

    private func configure(_ window: NSWindow) {
        guard configuredWindowNumber != window.windowNumber else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        RootWindowMaterial.install(in: window)
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert([.fullScreenPrimary, .moveToActiveSpace])
        if ProcessInfo.processInfo.environment[ZizaiLaunchConfiguration.uiTestingEnvironmentKey] == "1" {
            window.setContentSize(CGSize(width: 1_360, height: 860))
        }
        window.center()
        configuredWindowNumber = window.windowNumber
    }

}

@main
struct ZizaiLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: LauncherStore
    @StateObject private var applicationFolderAccess: ApplicationFolderAccess
    @StateObject private var layoutModeController: LayoutModeController
    @StateObject private var loginItemManager = LoginItemManager()

    init() {
        let configuration = ZizaiLaunchConfiguration.current()
        let applicationFolderAccess = ApplicationFolderAccess(
            storageDirectory: configuration.stateDirectory
        )
        let store: LauncherStore
        if let fixtureApplications = configuration.applications {
            store = LauncherStore(
                stateDirectory: configuration.stateDirectory,
                appProvider: { fixtureApplications },
                isAppScanComplete: { true }
            )
        } else {
            store = LauncherStore(
                asyncAppProvider: { await applicationFolderAccess.scanApplicationsAsync() },
                appPreparer: { apps in
                    await IconCache.shared.prewarmCooperatively(paths: apps.map(\.path))
                },
                isAppScanComplete: { applicationFolderAccess.hasUsableAuthorization },
                backgroundPersistenceEnabled: true
            )
        }
        _store = StateObject(wrappedValue: store)
        _applicationFolderAccess = StateObject(wrappedValue: applicationFolderAccess)
        _layoutModeController = StateObject(
            wrappedValue: LayoutModeController(selection: store.layoutMode)
        )
    }

    var body: some Scene {
        WindowGroup("自在启动台") {
            RootView(layoutModeController: layoutModeController)
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { store.undoLastAction() }
                    .keyboardShortcut("z", modifiers: [.command])
                    .disabled(!store.canUndo)
            }
            CommandMenu("视图") {
                Button("分组") { activateLayoutMode(.groups) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("空间") { activateLayoutMode(.space) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("全部应用") { activateLayoutMode(.allApps) }
                    .keyboardShortcut("3", modifiers: [.command])
                Divider()
                Button("搜索") { store.requestFocusSearch() }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("新建分组") { store.requestNewGroup() }
                    .keyboardShortcut("n", modifiers: [.command])
                Divider()
                Button("适合全部内容") { store.fitAllGroups() }
                    .keyboardShortcut("0", modifiers: [.command])
                Button("放大") { store.adjustCanvasZoom(by: 0.1) }
                    .keyboardShortcut("=", modifiers: [.command])
                Button("缩小") { store.adjustCanvasZoom(by: -0.1) }
                    .keyboardShortcut("-", modifiers: [.command])
                Divider()
                Button("重新扫描应用") { store.reloadApps(announce: true) }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            GeneralSettingsView {
                store.reloadApps(announce: true)
            }
            .environmentObject(loginItemManager)
            .environmentObject(applicationFolderAccess)
        }
    }

    private func activateLayoutMode(_ mode: LayoutMode) {
        layoutModeController.selection = mode
        store.stageLayoutModePersistence(mode)
    }
}
