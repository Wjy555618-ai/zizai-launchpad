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

    func testRemovalAuthorizationIsSeparateScopedAndRevocable() throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-removal-authorization")
        defer { fixture.remove() }
        let scanFolder = fixture.root.appendingPathComponent("UserApplications", isDirectory: true)
        let managedFolder = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        let applicationURL = managedFolder.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: scanFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)

        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: TestApplicationFolderAuthorizationService()
        ) { _ in [] }

        XCTAssertTrue(manager.authorize(folder: scanFolder))
        XCTAssertTrue(manager.authorizeRemoval(folder: managedFolder, containing: applicationURL))
        XCTAssertTrue(manager.hasStoredAuthorization)
        XCTAssertTrue(manager.hasStoredRemovalAuthorization)
        XCTAssertTrue(manager.hasRemovalAuthorization(for: applicationURL))
        XCTAssertEqual(manager.removalAuthorizationPath, managedFolder.standardizedFileURL.path)

        let activeFolder = try XCTUnwrap(manager.beginRemovalAccess(for: applicationURL))
        XCTAssertEqual(activeFolder.standardizedFileURL.path, managedFolder.standardizedFileURL.path)
        manager.endRemovalAccess(activeFolder)

        manager.revokeRemovalAuthorization()
        XCTAssertFalse(manager.hasStoredRemovalAuthorization)
        XCTAssertFalse(manager.hasRemovalAuthorization(for: applicationURL))
        XCTAssertTrue(manager.hasStoredAuthorization)
        XCTAssertEqual(manager.authorizedFolderPath, scanFolder.standardizedFileURL.path)
    }

    func testRemovalAuthorizationRejectsUnrelatedFolder() throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-removal-scope")
        defer { fixture.remove() }
        let selectedFolder = fixture.root.appendingPathComponent("Selected", isDirectory: true)
        let otherApplication = fixture.root
            .appendingPathComponent("Other", isDirectory: true)
            .appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherApplication, withIntermediateDirectories: true)

        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: TestApplicationFolderAuthorizationService()
        ) { _ in [] }

        XCTAssertFalse(manager.authorizeRemoval(folder: selectedFolder, containing: otherApplication))
        XCTAssertFalse(manager.hasStoredRemovalAuthorization)
        XCTAssertTrue(manager.removalErrorMessage?.contains("但需要授权") == true)
    }

    func testRemovalAuthorizationRejectsBroaderAncestorFolder() throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-removal-least-privilege")
        defer { fixture.remove() }
        let directFolder = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        let applicationURL = directFolder.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)

        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: TestApplicationFolderAuthorizationService()
        ) { _ in [] }

        XCTAssertFalse(manager.authorizeRemoval(folder: fixture.root, containing: applicationURL))
        XCTAssertFalse(manager.hasStoredRemovalAuthorization)
        XCTAssertTrue(manager.removalErrorMessage?.contains("但需要授权") == true)
    }

    func testSystemApplicationsGrantIsReusedAcrossAppsAndRestart() throws {
        let fixture = try TemporaryFolderFixture(prefix: "zizai-removal-shared-scope")
        defer { fixture.remove() }
        let service = TestApplicationFolderAuthorizationService()
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let first = applications.appendingPathComponent(
            "Suite/First.app",
            isDirectory: true
        )
        let second = applications.appendingPathComponent("Second.app", isDirectory: true)
        let manager = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: service
        ) { _ in [] }

        XCTAssertEqual(
            ApplicationRemovalAuthorizationScope.folder(containing: first).path,
            applications.path
        )
        XCTAssertTrue(manager.authorizeRemoval(folder: applications, containing: first))
        XCTAssertTrue(manager.hasRemovalAuthorization(for: first))
        XCTAssertTrue(manager.hasRemovalAuthorization(for: second))

        let restored = ApplicationFolderAccess(
            storageDirectory: fixture.root,
            authorizationService: service
        ) { _ in [] }
        XCTAssertEqual(restored.removalAuthorizationPath, applications.path)
        XCTAssertTrue(restored.hasRemovalAuthorization(for: first))
        XCTAssertTrue(restored.hasRemovalAuthorization(for: second))
    }

    func testAuthorizationScopeUsesUserApplicationsAndExternalDirectParent() throws {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let userApplication = home.appendingPathComponent(
            "Applications/Example.app",
            isDirectory: true
        )
        XCTAssertEqual(
            ApplicationRemovalAuthorizationScope.folder(
                containing: userApplication,
                homeDirectory: home
            ).path,
            "/Users/example/Applications"
        )

        let externalApplication = URL(
            fileURLWithPath: "/Volumes/Portable/Tools/Example.app",
            isDirectory: true
        )
        XCTAssertEqual(
            ApplicationRemovalAuthorizationScope.folder(
                containing: externalApplication,
                homeDirectory: home
            ).path,
            "/Volumes/Portable/Tools"
        )
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
