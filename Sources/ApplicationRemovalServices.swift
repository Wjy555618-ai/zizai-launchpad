import AppKit
import Foundation

enum ApplicationRemovalEligibility: Equatable {
    case removable
    case protected(reason: String)
}

/// The complete product-facing removal capability for one application.
///
/// Static filesystem protection and a denial learned from macOS are different
/// states, but every UI entry point must consume the same combined answer. This
/// prevents the badge, context menu, VoiceOver actions and coordinator from
/// advertising conflicting capabilities.
enum ApplicationRemovalCapability: Equatable {
    case removable
    case protected(reason: String)
    case temporarilyUnavailable

    var presentsManagementBadge: Bool {
        switch self {
        case .removable, .temporarilyUnavailable:
            return true
        case .protected:
            return false
        }
    }

    var isDestructiveAction: Bool {
        self == .removable
    }

    var actionTitle: String {
        switch self {
        case .removable:
            return "移到废纸篓"
        case .protected:
            return "了解为什么无法移除"
        case .temporarilyUnavailable:
            return "了解当前无法移除原因"
        }
    }

    var actionSystemImage: String {
        isDestructiveAction ? "trash" : "lock.fill"
    }
}

enum ApplicationRemovalPolicy {
    private static let protectedRoots = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/private",
    ]

    static func eligibility(
        for app: AppInfo,
        currentApplicationURL: URL = Bundle.main.bundleURL
    ) -> ApplicationRemovalEligibility {
        let applicationURL = URL(fileURLWithPath: app.path).standardizedFileURL
        guard applicationURL.isFileURL,
            applicationURL.pathExtension.lowercased() == "app"
        else {
            return .protected(reason: "这不是可由自在启动台管理的 macOS 应用包。")
        }

        let applicationPath = canonicalPath(applicationURL)
        let currentPath = canonicalPath(currentApplicationURL)
        if applicationPath == currentPath {
            return .protected(reason: "自在启动台不能在运行时移除自己。")
        }

        if protectedRoots.contains(where: { isInside(applicationPath, root: $0) }) {
            return .protected(reason: "这是 macOS 受保护位置中的系统应用，不能由自在启动台移除。")
        }

        return .removable
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isInside(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}

@MainActor
protocol ApplicationRemovalAuthorizing: AnyObject {
    var removalErrorMessage: String? { get }
    func hasRemovalAuthorization(for applicationURL: URL) -> Bool
    func authorizeRemoval(folder: URL, containing applicationURL: URL) -> Bool
    func beginRemovalAccess(for applicationURL: URL) -> URL?
    func endRemovalAccess(_ folder: URL)
    func reportRemovalSelectionError(_ error: Error)
}

extension ApplicationFolderAccess: ApplicationRemovalAuthorizing {}

@MainActor
extension ApplicationRemovalCoordinator {
    func isAppManagementUnavailable(_ app: AppInfo) -> Bool {
        appManagementUnavailableAppIDs.contains(app.id)
    }

    func removalCapability(for app: AppInfo) -> ApplicationRemovalCapability {
        switch ApplicationRemovalPolicy.eligibility(for: app) {
        case .protected(let reason):
            return .protected(reason: reason)
        case .removable where isAppManagementUnavailable(app):
            return .temporarilyUnavailable
        case .removable:
            return .removable
        }
    }
}

@MainActor
protocol ApplicationRunningDetecting {
    func isRunning(_ app: AppInfo) -> Bool
}

struct WorkspaceApplicationRunningDetector: ApplicationRunningDetecting {
    func isRunning(_ app: AppInfo) -> Bool {
        let targetPath = URL(fileURLWithPath: app.path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return NSWorkspace.shared.runningApplications.contains { runningApplication in
            guard let bundleURL = runningApplication.bundleURL else { return false }
            return bundleURL.standardizedFileURL.resolvingSymlinksInPath().path == targetPath
        }
    }
}

@MainActor
protocol ApplicationRecycling {
    func recycle(_ applicationURL: URL) async throws -> URL
}

struct ApplicationRemovalDialog: Identifiable, Equatable {
    enum Kind: Equatable {
        case confirmation
        case authorization
        case appManagementPermission
        case appManagementUnavailable
        case blocked
        case running
        case failure
    }

    let id = UUID()
    let kind: Kind
    let app: AppInfo
    let title: String
    let message: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
