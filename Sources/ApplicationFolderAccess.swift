import Combine
import Foundation

/// Owns the one piece of user-granted file access needed by the launcher.
/// System application folders remain readable through the sandbox; an
/// additional folder is scanned only while its persisted security scope is
/// active.
@MainActor
final class ApplicationFolderAccess: ObservableObject {
    typealias Scanner = @Sendable ([URL]) -> [AppInfo]

    @Published private(set) var authorizedFolderPath: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasUsableAuthorization = false

    private let bookmarkURL: URL
    private let scanner: Scanner

    init(
        storageDirectory: URL? = nil,
        scanner: @escaping Scanner = { AppScanner.scan(additionalApplicationRoots: $0) }
    ) {
        let support =
            storageDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("自在启动台", isDirectory: true)
        bookmarkURL = support.appendingPathComponent("应用文件夹授权.bookmark")
        self.scanner = scanner
        refreshAuthorizationStatus()
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

        let didStartAccess = folder.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            errorMessage = "未能获得该文件夹的只读访问权限，请重新选择。"
            return false
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        do {
            try writeBookmark(for: folder)
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

    /// Resolves and uses the bookmark only for the duration of the scan. A
    /// missing or invalid grant never prevents the standard system folders
    /// from being scanned.
    func scanApplications() -> [AppInfo] {
        guard let resolved = resolveAuthorizedFolder() else {
            hasUsableAuthorization = false
            return scanner([])
        }

        let didStartAccess = resolved.url.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            hasUsableAuthorization = false
            errorMessage = "用户应用文件夹授权已失效，请在设置中重新选择。"
            return scanner([])
        }
        defer { resolved.url.stopAccessingSecurityScopedResource() }

        do {
            if resolved.isStale {
                try writeBookmark(for: resolved.url)
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

        let didStartAccess = resolved.url.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            hasUsableAuthorization = false
            errorMessage = "用户应用文件夹授权已失效，请在设置中重新选择。"
            return await scanInBackground(additionalRoots: [])
        }
        defer { resolved.url.stopAccessingSecurityScopedResource() }

        do {
            if resolved.isStale {
                try writeBookmark(for: resolved.url)
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

    private func resolveAuthorizedFolder() -> (url: URL, isStale: Bool)? {
        guard let data = try? Data(contentsOf: bookmarkURL) else {
            authorizedFolderPath = nil
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            try? FileManager.default.removeItem(at: bookmarkURL)
            authorizedFolderPath = nil
            hasUsableAuthorization = false
            errorMessage = "用户应用文件夹授权已失效，请重新选择。"
            return nil
        }
    }

    private func writeBookmark(for folder: URL) throws {
        try FileManager.default.createDirectory(
            at: bookmarkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try folder.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try data.write(to: bookmarkURL, options: .atomic)
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
