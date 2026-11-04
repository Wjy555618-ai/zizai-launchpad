import AppKit
import Darwin
import Foundation

@MainActor
protocol ApplicationManagementPermissionOpening {
    func openAppManagementSettings() -> Bool
}
struct WorkspaceApplicationManagementPermissionOpener: ApplicationManagementPermissionOpening {
    static let settingsURLString =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles"
    func openAppManagementSettings() -> Bool {
        guard let settingsURL = URL(string: Self.settingsURLString) else { return false }
        return NSWorkspace.shared.open(settingsURL)
    }
}
enum ApplicationRemovalFailureClassifier {
    static func requiresAppManagementPermission(
        _ error: Error,
        applicationURL: URL
    ) -> Bool {
        guard applicationURL.pathExtension.lowercased() == "app" else { return false }
        return flattenedErrors(from: error).contains { candidate in
            if candidate.domain == NSCocoaErrorDomain {
                return candidate.code == NSFileReadNoPermissionError
                    || candidate.code == NSFileWriteNoPermissionError
            }
            return candidate.domain == NSPOSIXErrorDomain
                && (candidate.code == Int(EPERM) || candidate.code == Int(EACCES))
        }
    }
    private static func flattenedErrors(from error: Error) -> [NSError] {
        var pending = [error as NSError]
        var result: [NSError] = []
        var visited = Set<ObjectIdentifier>()
        while let candidate = pending.popLast() {
            guard visited.insert(ObjectIdentifier(candidate)).inserted else { continue }
            result.append(candidate)
            if let underlying = candidate.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }
            for key in ["NSDetailedErrors", "NSMultipleUnderlyingErrors"] {
                pending.append(contentsOf: candidate.userInfo[key] as? [NSError] ?? [])
            }
        }
        return result
    }
}
enum ApplicationRemovalFailurePresentation {
    static func dialog(
        for error: Error,
        app: AppInfo,
        applicationURL: URL,
        canOfferAppManagementPermission: Bool
    ) -> ApplicationRemovalDialog {
        if ApplicationRemovalFailureClassifier.requiresAppManagementPermission(
            error,
            applicationURL: applicationURL
        ) {
            return canOfferAppManagementPermission
                ? permissionDialog(for: app) : unavailableDialog(for: app)
        }
        let diagnostic = error as NSError
        return ApplicationRemovalDialog(
            kind: .failure,
            app: app,
            title: "没有移除“\(app.chineseName)”",
            message: "macOS 未能把应用移入废纸篓：\(error.localizedDescription)\n\n"
                + "错误代码：\(diagnostic.domain) \(diagnostic.code)\n原应用没有被自在启动台改动。"
        )
    }

    static func unavailableDialog(for app: AppInfo) -> ApplicationRemovalDialog {
        ApplicationRemovalDialog(
            kind: .appManagementUnavailable,
            app: app,
            title: "暂时无法移除“\(app.chineseName)”",
            message: "macOS 仍拒绝了本次移动。自在启动台不会继续要求授权或重复尝试。\n\n"
                + "原应用没有被改动。你可以在访达中手动处理，或完全退出并重新打开自在启动台后再试。"
        )
    }

    private static func permissionDialog(for app: AppInfo) -> ApplicationRemovalDialog {
        ApplicationRemovalDialog(
            kind: .appManagementPermission,
            app: app,
            title: "需要允许管理其他应用",
            message: "macOS 尚未向当前安装的自在启动台授予有效的“应用管理”权限。\n\n"
                + "如果开关已经打开，请先关闭再重新打开，然后返回。自在启动台只会再尝试一次；如果 macOS 仍然拒绝，将明确标记为当前无法移除，不会循环授权。\n\n原应用尚未被改动。"
        )
    }
}

@MainActor
extension ApplicationRemovalCoordinator {
    func revealInFinder(_ app: AppInfo) {
        dismissDialog()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }
}
