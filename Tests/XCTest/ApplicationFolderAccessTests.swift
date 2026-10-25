import Foundation
import XCTest

@testable import 自在启动台

@MainActor
final class ApplicationFolderAccessTests: XCTestCase {
    func testMissingAuthorizationFallsBackToSystemRoots() async throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-no-folder-authorization")
        defer { fixture.remove() }
        let scannedRoots = LockedTestValue<[URL]>([])
        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: TestApplicationFolderAuthorizationService()
        ) { roots in
            scannedRoots.set(roots)
            return []
        }

        XCTAssertFalse(manager.hasStoredAuthorization)
        XCTAssertFalse(manager.hasUsableAuthorization)
        XCTAssertNil(manager.authorizedFolderPath)
        XCTAssertTrue(manager.scanApplications().isEmpty)
        XCTAssertTrue(scannedRoots.value.isEmpty)

        scannedRoots.set([fixture.root])
        let asyncResults = await manager.scanApplicationsAsync()
        XCTAssertTrue(asyncResults.isEmpty)
        XCTAssertTrue(scannedRoots.value.isEmpty)
    }

    func testFolderAuthorizationPersistsScansAndRevokes() async throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-folder-authorization")
        defer { fixture.remove() }
        let selectedFolder = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(
            at: selectedFolder,
            withIntermediateDirectories: true
        )

        let firstRoots = LockedTestValue<[URL]>([])
        let authorizationService = TestApplicationFolderAuthorizationService()
        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: authorizationService
        ) { roots in
            firstRoots.set(roots)
            return []
        }

        XCTAssertTrue(manager.authorize(folder: selectedFolder))
        XCTAssertTrue(manager.hasStoredAuthorization)
        XCTAssertTrue(manager.hasUsableAuthorization)
        XCTAssertEqual(manager.authorizedFolderPath, selectedFolder.standardizedFileURL.path)
        XCTAssertTrue(manager.scanApplications().isEmpty)
        XCTAssertEqual(standardizedPaths(firstRoots.value), [selectedFolder.standardizedFileURL.path])

        let restoredRoots = LockedTestValue<[URL]>([])
        let restored = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: authorizationService
        ) { roots in
            restoredRoots.set(roots)
            return []
        }
        XCTAssertEqual(restored.authorizedFolderPath, selectedFolder.standardizedFileURL.path)
        let restoredResults = await restored.scanApplicationsAsync()
        XCTAssertTrue(restoredResults.isEmpty)
        XCTAssertTrue(restored.hasUsableAuthorization)
        XCTAssertEqual(
            standardizedPaths(restoredRoots.value),
            [selectedFolder.standardizedFileURL.path]
        )

        restored.revokeAuthorization()
        XCTAssertFalse(restored.hasStoredAuthorization)
        XCTAssertFalse(restored.hasUsableAuthorization)
        XCTAssertNil(restored.authorizedFolderPath)
        XCTAssertNil(restored.errorMessage)

        restoredRoots.set([selectedFolder])
        XCTAssertTrue(restored.scanApplications().isEmpty)
        XCTAssertTrue(restoredRoots.value.isEmpty)
    }

    func testInvalidSelectionsAndSelectionErrorsAreActionable() throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-invalid-folder-selection")
        defer { fixture.remove() }
        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: TestApplicationFolderAuthorizationService()
        ) { _ in [] }
        let missingFolder = fixture.root.appendingPathComponent("Missing", isDirectory: true)

        XCTAssertFalse(manager.authorize(folder: missingFolder))
        XCTAssertEqual(manager.errorMessage, "所选位置不是可用的文件夹。")
        XCTAssertFalse(manager.hasStoredAuthorization)

        manager.reportSelectionError(TestSelectionError.cancelled)
        XCTAssertTrue(manager.errorMessage?.contains("无法选择应用文件夹") == true)
        XCTAssertTrue(manager.errorMessage?.contains("模拟文件选择失败") == true)
    }

    func testCorruptBookmarkIsRemovedAndDoesNotExpandScanScope() throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-corrupt-bookmark")
        defer { fixture.remove() }
        let bookmarkURL = fixture.root.appendingPathComponent("应用文件夹授权.bookmark")
        try Data("not-a-bookmark".utf8).write(to: bookmarkURL, options: .atomic)
        let scannedRoots = LockedTestValue<[URL]>([fixture.root])

        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: TestApplicationFolderAuthorizationService()
        ) { roots in
            scannedRoots.set(roots)
            return []
        }

        XCTAssertFalse(manager.hasStoredAuthorization)
        XCTAssertFalse(manager.hasUsableAuthorization)
        XCTAssertNil(manager.authorizedFolderPath)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(manager.scanApplications().isEmpty)
        XCTAssertTrue(scannedRoots.value.isEmpty)
    }

    private func standardizedPaths(_ urls: [URL]) -> [String] {
        urls.map(\.standardizedFileURL.path)
    }
}

private enum TestSelectionError: LocalizedError {
    case cancelled

    var errorDescription: String? { "模拟文件选择失败" }
}

private struct TemporaryFolderFixture {
    let root: URL

    init(prefix: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LockedTestValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}
