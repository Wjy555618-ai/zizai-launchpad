import Foundation

enum ApplicationRecycleError: LocalizedError {
    case trashDirectoryUnavailable
    case sourceStillPresent
    case destinationMissing

    var errorDescription: String? {
        switch self {
        case .trashDirectoryUnavailable:
            return "macOS 没有提供可用的废纸篓位置。"
        case .sourceStillPresent:
            return "系统操作结束后，原应用仍然存在。"
        case .destinationMissing:
            return "系统操作结束后，废纸篓中没有找到该应用。"
        }
    }
}

/// Moves the application directly into the source volume's user Trash while
/// the caller's security-scoped folder grant is active.
///
/// `FileManager.trashItem` is intentionally not used here. For application
/// bundles macOS delegates that API to `CategoriesService.xpc`; App Management
/// then evaluates the system helper instead of this app, so an already granted
/// permission can still fail and trigger an authorization loop. `moveItem`
/// keeps the protected mutation attributed to Zizai Launchpad itself.
struct FileManagerApplicationRecycler: ApplicationRecycling {
    private let trashDirectoryOverride: URL?

    init(trashDirectoryOverride: URL? = nil) {
        self.trashDirectoryOverride = trashDirectoryOverride
    }

    func recycle(_ applicationURL: URL) async throws -> URL {
        let trashDirectoryOverride = trashDirectoryOverride
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let source = applicationURL.standardizedFileURL
            let trashDirectory: URL
            if let trashDirectoryOverride {
                trashDirectory = trashDirectoryOverride.standardizedFileURL
            } else {
                trashDirectory = try fileManager.url(
                    for: .trashDirectory,
                    in: .userDomainMask,
                    appropriateFor: source,
                    create: true
                ).standardizedFileURL
            }

            var isDirectory: ObjCBool = false
            guard
                fileManager.fileExists(
                    atPath: trashDirectory.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue
            else {
                throw ApplicationRecycleError.trashDirectoryUnavailable
            }

            let destination = Self.availableDestination(
                for: source,
                in: trashDirectory,
                fileManager: fileManager
            )
            try fileManager.moveItem(at: source, to: destination)

            guard !fileManager.fileExists(atPath: source.path) else {
                throw ApplicationRecycleError.sourceStillPresent
            }
            guard fileManager.fileExists(atPath: destination.path) else {
                throw ApplicationRecycleError.destinationMissing
            }
            return destination
        }
        .value
    }

    nonisolated private static func availableDestination(
        for source: URL,
        in trashDirectory: URL,
        fileManager: FileManager
    ) -> URL {
        let original = trashDirectory.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let pathExtension = source.pathExtension
        let baseName = source.deletingPathExtension().lastPathComponent
        for suffix in 2...9_999 {
            let candidateName =
                pathExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(pathExtension)"
            let candidate = trashDirectory.appendingPathComponent(
                candidateName,
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let fallbackName =
            pathExtension.isEmpty
            ? "\(baseName) \(UUID().uuidString)"
            : "\(baseName) \(UUID().uuidString).\(pathExtension)"
        return trashDirectory.appendingPathComponent(
            fallbackName,
            isDirectory: true
        )
    }
}
