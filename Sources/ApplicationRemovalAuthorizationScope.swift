import Foundation

/// Defines the one folder grant used to manage an application.
///
/// Applications installed anywhere below the system or per-user Applications
/// directory share that directory's grant. Other locations stay least-privilege
/// and request only the application's direct parent. Every authorization,
/// persistence check, retry message, and system panel consumes this same model.
enum ApplicationRemovalAuthorizationScope {
    static func folder(
        containing applicationURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let application = canonical(applicationURL)
        let systemApplications = canonical(URL(fileURLWithPath: "/Applications", isDirectory: true))
        if contains(systemApplications, application: application) {
            return systemApplications
        }

        let userApplications = canonical(
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        )
        if contains(userApplications, application: application) {
            return userApplications
        }

        return application.deletingLastPathComponent()
    }

    static func matches(
        selectedFolder: URL,
        applicationURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        canonical(selectedFolder).path
            == folder(containing: applicationURL, homeDirectory: homeDirectory).path
    }

    static func contains(_ folder: URL, application: URL) -> Bool {
        let folderPath = canonical(folder).path
        let applicationPath = canonical(application).path
        guard applicationPath != folderPath else { return false }
        let prefix = folderPath == "/" ? "/" : folderPath + "/"
        return applicationPath.hasPrefix(prefix)
    }

    static func displayName(for folder: URL) -> String {
        let canonicalFolder = canonical(folder)
        if canonicalFolder.path == "/Applications" { return "应用程序" }
        return canonicalFolder.lastPathComponent.isEmpty
            ? canonicalFolder.path
            : canonicalFolder.lastPathComponent
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
