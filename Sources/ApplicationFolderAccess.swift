import Combine
import Foundation

struct ResolvedApplicationFolderAuthorization {
    let url: URL
    let isStale: Bool
}

enum ApplicationFolderBookmarkAccess {
    case readOnly
    case readWrite
}

/// Isolates the operating-system security-scope boundary from authorization
/// state and scanning. Production uses Apple's bookmark APIs; unit tests inject
/// a deterministic implementation instead of depending on an unsigned process
/// being allowed to manufacture a user grant.
protocol ApplicationFolderAuthorizationServicing {
    func makeBookmark(for folder: URL, access: ApplicationFolderBookmarkAccess) throws -> Data
    func resolveBookmark(_ data: Data) throws -> ResolvedApplicationFolderAuthorization
    func startAccessing(_ folder: URL) -> Bool
    func stopAccessing(_ folder: URL)
}

struct SecurityScopedApplicationFolderAuthorizationService:
    ApplicationFolderAuthorizationServicing
{
    func makeBookmark(for folder: URL, access: ApplicationFolderBookmarkAccess) throws -> Data {
        switch access {
        case .readOnly:
            return try folder.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        case .readWrite:
            return try folder.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedApplicationFolderAuthorization {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedApplicationFolderAuthorization(url: url, isStale: isStale)
    }

    func startAccessing(_ folder: URL) -> Bool {
        folder.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ folder: URL) {
        folder.stopAccessingSecurityScopedResource()
    }
}

/// Owns the launcher's user-granted file capabilities. Discovery and removal
/// are deliberately separate: additional folders are always scanned through
/// a read-only bookmark, while a read-write bookmark is activated only around
/// a user-confirmed recycle operation.
@MainActor
final class ApplicationFolderAccess: ObservableObject {
    typealias Scanner = @Sendable ([URL]) -> [AppInfo]

    @Published private(set) var authorizedFolderPath: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasUsableAuthorization = false
    @Published private(set) var removalAuthorizationPath: String?
    @Published private(set) var removalErrorMessage: String?

    private let bookmarkURL: URL
    private let removalBookmarkURL: URL
    private let scanner: Scanner
    private let authorizationService: any ApplicationFolderAuthorizationServicing

    init(
        storageDirectory: URL? = nil,
        authorizationService: any ApplicationFolderAuthorizationServicing =
            SecurityScopedApplicationFolderAuthorizationService(),
        scanner: @escaping Scanner = { AppScanner.scan(additionalApplicationRoots: $0) }
    ) {
        let support =
            storageDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("自在启动台", isDirectory: true)
        bookmarkURL = support.appendingPathComponent("应用文件夹授权.bookmark")
        removalBookmarkURL = support.appendingPathComponent("应用管理授权.bookmark")
        self.authorizationService = authorizationService
        self.scanner = scanner
        refreshAuthorizationStatus()
        refreshRemovalAuthorizationStatus()
    }

    var hasStoredAuthorization: Bool {
        FileManager.default.fileExists(atPath: bookmarkURL.path)
    }

    /// Creates a read-only security-scoped bookmark after a user selects a
    /// folder through the system file importer.
    @discardableResult
    func authorize(folder: URL) -> Bool {
        errorMessage = nil
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            errorMessage = "所选位置不是可用的文件夹。"
            return false
        }

        let didStartAccess = authorizationService.startAccessing(folder)
        guard didStartAccess else {
            errorMessage = "未能获得该文件夹的只读访问权限，请重新选择。"
            return false
        }
        defer { authorizationService.stopAccessing(folder) }

        do {
            try writeScanBookmark(for: folder)
            authorizedFolderPath = folder.standardizedFileURL.path
            hasUsableAuthorization = true
            return true
        } catch {
            errorMessage = "无法保存应用文件夹授权：\(error.localizedDescription)"
            hasUsableAuthorization = false
            return false
        }
    }

    func revokeAuthorization() {
        do {
            if hasStoredAuthorization {
                try FileManager.default.removeItem(at: bookmarkURL)
            }
            authorizedFolderPath = nil
            hasUsableAuthorization = false
            errorMessage = nil
        } catch {
            errorMessage = "无法移除应用文件夹授权：\(error.localizedDescription)"
        }
    }

    var hasStoredRemovalAuthorization: Bool {
        FileManager.default.fileExists(atPath: removalBookmarkURL.path)
    }

    /// Persists a separate read-write grant for application management. Scan
    /// authorization remains read-only even when this capability is enabled.
    /// The system and per-user Applications folders are authorized once and
    /// reused for every application they contain. Other locations remain
    /// scoped to the pending application's direct parent.
    @discardableResult
    func authorizeRemoval(folder: URL, containing applicationURL: URL) -> Bool {
        removalErrorMessage = nil
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            removalErrorMessage = "所选位置不是可用的文件夹。"
            return false
        }
        let expectedFolder = ApplicationRemovalAuthorizationScope.folder(
            containing: applicationURL
        )
        guard
            ApplicationRemovalAuthorizationScope.matches(
                selectedFolder: folder,
                applicationURL: applicationURL
            )
        else {
            let selectedName = ApplicationRemovalAuthorizationScope.displayName(for: folder)
            let expectedName = ApplicationRemovalAuthorizationScope.displayName(
                for: expectedFolder
            )
            removalErrorMessage =
                "已选择“\(selectedName)”，但需要授权“\(expectedName)”文件夹。"
                + "重试时无需选择任何应用，直接点击右下角授权。"
            return false
        }

        guard authorizationService.startAccessing(folder) else {
            removalErrorMessage = "未能获得该文件夹的管理权限，请重新选择。"
            return false
        }
        defer { authorizationService.stopAccessing(folder) }

        do {
            try writeRemovalBookmark(for: folder)
            removalAuthorizationPath = folder.standardizedFileURL.path
            return true
        } catch {
            removalErrorMessage = "无法保存应用管理授权：\(error.localizedDescription)"
            return false
        }
    }

    func hasRemovalAuthorization(for applicationURL: URL) -> Bool {
        guard let resolved = resolveRemovalAuthorization() else { return false }
        return ApplicationRemovalAuthorizationScope.matches(
            selectedFolder: resolved.url,
            applicationURL: applicationURL
        )
    }

    /// Starts the security scope immediately before a recycle operation. The
    /// caller must balance a non-nil result with `endRemovalAccess(_:)` after
    /// the asynchronous system operation has completed.
    func beginRemovalAccess(for applicationURL: URL) -> URL? {
        guard let resolved = resolveRemovalAuthorization(),
            ApplicationRemovalAuthorizationScope.matches(
                selectedFolder: resolved.url,
                applicationURL: applicationURL
            )
        else {
            let expectedFolder = ApplicationRemovalAuthorizationScope.folder(
                containing: applicationURL
            )
            let expectedName = ApplicationRemovalAuthorizationScope.displayName(
                for: expectedFolder
            )
            removalErrorMessage = "“\(expectedName)”授权已失效，请重新授权后再试。"
            return nil
        }
        guard authorizationService.startAccessing(resolved.url) else {
            removalErrorMessage = "应用管理授权已失效，请重新选择应用所在文件夹。"
            return nil
        }

        do {
            if resolved.isStale {
                try writeRemovalBookmark(for: resolved.url)
            }
            removalAuthorizationPath = resolved.url.standardizedFileURL.path
            removalErrorMessage = nil
            return resolved.url
        } catch {
            authorizationService.stopAccessing(resolved.url)
            removalErrorMessage = "无法更新应用管理授权：\(error.localizedDescription)"
            return nil
        }
    }

    func endRemovalAccess(_ folder: URL) {
        authorizationService.stopAccessing(folder)
    }

    func revokeRemovalAuthorization() {
        do {
            if hasStoredRemovalAuthorization {
                try FileManager.default.removeItem(at: removalBookmarkURL)
            }
            removalAuthorizationPath = nil
            removalErrorMessage = nil
        } catch {
            removalErrorMessage = "无法移除应用管理授权：\(error.localizedDescription)"
        }
    }

    func reportRemovalSelectionError(_ error: Error) {
        removalErrorMessage = "无法选择应用所在文件夹：\(error.localizedDescription)"
    }

    /// Resolves and uses the bookmark only for the duration of the scan. A
    /// missing or invalid grant never prevents the standard system folders
    /// from being scanned.
    func scanApplications() -> [AppInfo] {
        guard let resolved = resolveAuthorizedFolder() else {
            hasUsableAuthorization = false
            return scanner([])
        }

        let didStartAccess = authorizationService.startAccessing(resolved.url)
        guard didStartAccess else {
            hasUsableAuthorization = false
            errorMessage = "用户应用文件夹授权已失效，请在设置中重新选择。"
            return scanner([])
        }
        defer { authorizationService.stopAccessing(resolved.url) }

        do {
            if resolved.isStale {
                try writeScanBookmark(for: resolved.url)
            }
            authorizedFolderPath = resolved.url.standardizedFileURL.path
            hasUsableAuthorization = true
            errorMessage = nil
            return scanner([resolved.url])
        } catch {
            hasUsableAuthorization = false
            errorMessage = "无法更新应用文件夹授权：\(error.localizedDescription)"
            return scanner([])
        }
    }

    /// Resolves sandbox authorization on the main actor, then performs the
    /// directory and bundle metadata walk on a cancellable worker task. The
    /// security scope remains active until that worker has finished.
    func scanApplicationsAsync() async -> [AppInfo] {
        guard let resolved = resolveAuthorizedFolder() else {
            hasUsableAuthorization = false
            return await scanInBackground(additionalRoots: [])
        }

        let didStartAccess = authorizationService.startAccessing(resolved.url)
        guard didStartAccess else {
            hasUsableAuthorization = false
            errorMessage = "用户应用文件夹授权已失效，请在设置中重新选择。"
            return await scanInBackground(additionalRoots: [])
        }
        defer { authorizationService.stopAccessing(resolved.url) }

        do {
            if resolved.isStale {
                try writeScanBookmark(for: resolved.url)
            }
            authorizedFolderPath = resolved.url.standardizedFileURL.path
            hasUsableAuthorization = true
            errorMessage = nil
            return await scanInBackground(additionalRoots: [resolved.url])
        } catch {
            hasUsableAuthorization = false
            errorMessage = "无法更新应用文件夹授权：\(error.localizedDescription)"
            return await scanInBackground(additionalRoots: [])
        }
    }

    func reportSelectionError(_ error: Error) {
        errorMessage = "无法选择应用文件夹：\(error.localizedDescription)"
    }

    private func refreshAuthorizationStatus() {
        guard let resolved = resolveAuthorizedFolder() else { return }
        authorizedFolderPath = resolved.url.standardizedFileURL.path
    }

    private func refreshRemovalAuthorizationStatus() {
        guard let resolved = resolveRemovalAuthorization() else { return }
        removalAuthorizationPath = resolved.url.standardizedFileURL.path
    }

    private func resolveAuthorizedFolder() -> ResolvedApplicationFolderAuthorization? {
        guard let data = try? Data(contentsOf: bookmarkURL) else {
            authorizedFolderPath = nil
            return nil
        }

        do {
            return try authorizationService.resolveBookmark(data)
        } catch {
            try? FileManager.default.removeItem(at: bookmarkURL)
            authorizedFolderPath = nil
            hasUsableAuthorization = false
            errorMessage = "用户应用文件夹授权已失效，请重新选择。"
            return nil
        }
    }

    private func resolveRemovalAuthorization() -> ResolvedApplicationFolderAuthorization? {
        guard let data = try? Data(contentsOf: removalBookmarkURL) else {
            removalAuthorizationPath = nil
            return nil
        }

        do {
            return try authorizationService.resolveBookmark(data)
        } catch {
            try? FileManager.default.removeItem(at: removalBookmarkURL)
            removalAuthorizationPath = nil
            removalErrorMessage = "应用管理授权已失效，请重新选择。"
            return nil
        }
    }

    private func writeScanBookmark(for folder: URL) throws {
        try FileManager.default.createDirectory(
            at: bookmarkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try authorizationService.makeBookmark(for: folder, access: .readOnly)
        try data.write(to: bookmarkURL, options: .atomic)
    }

    private func writeRemovalBookmark(for folder: URL) throws {
        try FileManager.default.createDirectory(
            at: removalBookmarkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try authorizationService.makeBookmark(for: folder, access: .readWrite)
        try data.write(to: removalBookmarkURL, options: .atomic)
    }

    private func scanInBackground(additionalRoots: [URL]) async -> [AppInfo] {
        let scanner = scanner
        let worker = Task.detached(priority: .userInitiated) {
            scanner(additionalRoots)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
