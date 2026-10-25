import Foundation
import XCTest

@testable import 自在启动台

final class StatePersistenceTests: XCTestCase {
    func testWriteCreatesValidatedBackupBeforeReplacingCurrentState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("布局.json")
        let backupURL = directory.appendingPathComponent("布局.backup.json")
        var first = PersistedState()
        first.hasSeenWelcome = true
        var second = first
        second.layoutMode = .space

        try PersistedStateIO.write(first, stateURL: stateURL, backupStateURL: backupURL)
        try PersistedStateIO.write(second, stateURL: stateURL, backupStateURL: backupURL)

        let decoder = JSONDecoder()
        let persisted = try decoder.decode(PersistedState.self, from: Data(contentsOf: stateURL))
        let backup = try decoder.decode(PersistedState.self, from: Data(contentsOf: backupURL))
        XCTAssertEqual(persisted.layoutMode, .space)
        XCTAssertEqual(backup.layoutMode, first.layoutMode)
    }

    func testInvalidCurrentStateIsNeverPromotedToBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-invalid-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("布局.json")
        let backupURL = directory.appendingPathComponent("布局.backup.json")
        try Data("invalid".utf8).write(to: stateURL)

        try PersistedStateIO.write(
            PersistedState(),
            stateURL: stateURL,
            backupStateURL: backupURL
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertNoThrow(
            try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: stateURL))
        )
    }
}
