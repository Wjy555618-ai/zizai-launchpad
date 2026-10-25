import Foundation

#if canImport(自在启动台)
    @testable import 自在启动台
#endif

struct TestApplicationFolderAuthorizationService:
    ApplicationFolderAuthorizationServicing
{
    func makeBookmark(for folder: URL) throws -> Data {
        Data(folder.standardizedFileURL.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedApplicationFolderAuthorization {
        guard
            let path = String(data: data, encoding: .utf8),
            path.hasPrefix("/")
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return ResolvedApplicationFolderAuthorization(
            url: URL(fileURLWithPath: path, isDirectory: true),
            isStale: false
        )
    }

    func startAccessing(_ folder: URL) -> Bool { true }

    func stopAccessing(_ folder: URL) {}
}
