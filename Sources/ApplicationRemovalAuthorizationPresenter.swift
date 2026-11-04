import AppKit
import Foundation

enum ApplicationRemovalAuthorizationSelection {
    case selected(URL)
    case cancelled
    case failed(any Error)
}

@MainActor
protocol ApplicationRemovalAuthorizationPresenting: AnyObject {
    func selectContainer(
        for app: AppInfo,
        completion: @escaping (ApplicationRemovalAuthorizationSelection) -> Void
    )
    func cancelSelection()
}

enum ApplicationRemovalAuthorizationPresentationError: LocalizedError {
    case missingHostWindow

    var errorDescription: String? {
        switch self {
        case .missingHostWindow:
            return "没有可用于显示系统授权窗口的自在启动台窗口。"
        }
    }
}

/// Presents the sandbox Powerbox grant as a native AppKit sheet. The
/// coordinator owns the product state; this type owns only the system panel
/// lifecycle and reports one terminal result back to that state machine.
@MainActor
final class ApplicationRemovalOpenPanelPresenter: ApplicationRemovalAuthorizationPresenting {
    private weak var panel: NSOpenPanel?
    private weak var hostWindow: NSWindow?
    private var sheetEndObserver: NSObjectProtocol?
    private var completion: ((ApplicationRemovalAuthorizationSelection) -> Void)?

    func selectContainer(
        for app: AppInfo,
        completion: @escaping (ApplicationRemovalAuthorizationSelection) -> Void
    ) {
        cancelSelection()
        self.completion = completion

        guard let hostWindow = resolvedHostWindow() else {
            finish(.failed(ApplicationRemovalAuthorizationPresentationError.missingHostWindow))
            return
        }
        self.hostWindow = hostWindow

        // A SwiftUI alert is itself a sheet. Its button action runs while the
        // old sheet is still ending, so presenting another modal in the same
        // event is rejected by AppKit. Move to the next run-loop turn, then
        // wait for the actual did-end-sheet boundary if AppKit still reports
        // the alert as attached. This is an event handoff, not a timing delay.
        DispatchQueue.main.async { [weak self] in
            self?.presentWhenHostIsReady(for: app)
        }
    }

    func cancelSelection() {
        removeSheetObserver()
        if let panel, let sheetParent = panel.sheetParent {
            sheetParent.endSheet(panel, returnCode: .cancel)
        } else {
            panel?.close()
        }
        panel = nil
        hostWindow = nil
        completion = nil
    }

    private func resolvedHostWindow() -> NSWindow? {
        if let mainWindow = NSApp.mainWindow { return mainWindow }
        if let sheetParent = NSApp.keyWindow?.sheetParent { return sheetParent }
        return NSApp.keyWindow
    }

    private func presentWhenHostIsReady(for app: AppInfo) {
        guard let hostWindow else {
            finish(.failed(ApplicationRemovalAuthorizationPresentationError.missingHostWindow))
            return
        }
        guard hostWindow.attachedSheet == nil else {
            removeSheetObserver()
            sheetEndObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndSheetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.hostWindow?.attachedSheet == nil else { return }
                    self.removeSheetObserver()
                    self.presentPanel(for: app)
                }
            }
            return
        }
        presentPanel(for: app)
    }

    private func presentPanel(for app: AppInfo) {
        guard panel == nil, let hostWindow else { return }
        let applicationURL = URL(fileURLWithPath: app.path).standardizedFileURL
        let scopeURL = ApplicationRemovalAuthorizationScope.folder(containing: applicationURL)
        let scopeName = ApplicationRemovalAuthorizationScope.displayName(for: scopeURL)

        let panel = NSOpenPanel()
        panel.title = "授权自在启动台管理“\(app.chineseName)”"
        panel.message =
            "当前已经是“\(scopeName)”文件夹。无需查找、选择或打开“\(applicationURL.lastPathComponent)”；"
            + "直接点击右下角“授权\(scopeName)”。授权后自在启动台才会显示最终移除确认。"
        panel.prompt = "授权\(scopeName)"
        // The folder being granted is the current location. Powerbox treats
        // the current directory as the selected URL when the person presses
        // the prompt, so one system authorization click is sufficient.
        panel.directoryURL = scopeURL
        panel.nameFieldStringValue = ""
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false

        self.panel = panel
        panel.beginSheetModal(for: hostWindow) { [weak self, weak panel] response in
            guard let self else { return }
            guard response == .OK, let selectedURL = panel?.url else {
                self.finish(.cancelled)
                return
            }
            self.finish(.selected(selectedURL))
        }
    }

    private func finish(_ result: ApplicationRemovalAuthorizationSelection) {
        removeSheetObserver()
        let hostWindow = hostWindow
        panel = nil
        self.hostWindow = nil
        let completion = completion
        self.completion = nil
        // Powerbox can return focus to another foreground process when its
        // sheet ends. Restore the existing product window before the state
        // machine continues so cancellation remains retryable and a selected
        // grant can present its confirmation on the same visible window.
        hostWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        completion?(result)
    }

    private func removeSheetObserver() {
        if let sheetEndObserver {
            NotificationCenter.default.removeObserver(sheetEndObserver)
            self.sheetEndObserver = nil
        }
    }
}
