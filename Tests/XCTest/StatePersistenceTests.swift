import Foundation
import XCTest

@testable import 自在启动台

final class StatePersistenceTests: XCTestCase {
    func testWriterFlushesNewestRevisionAndKeepsPreviousValidBackup() throws {
        try withPersistenceFiles { stateURL, backupURL in
            let writer = StatePersistenceWriter(
                stateURL: stateURL,
                backupStateURL: backupURL
            )
            var first = PersistedState()
            first.hasSeenWelcome = true
            var second = first
            second.layoutMode = .space
            var stale = first
            stale.layoutMode = .allApps

            try writer.flush(snapshot: first, revision: 1)
            try writer.flush(snapshot: second, revision: 2)
            try writer.flush(snapshot: stale, revision: 1)

            let persisted = try decodedState(at: stateURL)
            let backup = try decodedState(at: backupURL)
            XCTAssertEqual(persisted.layoutMode, .space)
            XCTAssertEqual(backup.layoutMode, first.layoutMode)
        }
    }

    func testWriterSerializesAsyncRevisionsAndRejectsStaleSnapshot() throws {
        try withPersistenceFiles { stateURL, backupURL in
            let writer = StatePersistenceWriter(
                stateURL: stateURL,
                backupStateURL: backupURL
            )
            var latest = PersistedState()
            latest.layoutMode = .space
            var stale = latest
            stale.layoutMode = .groups
            let callbacks = expectation(description: "all queued persistence callbacks")
            callbacks.expectedFulfillmentCount = 2
            let errors = SendableErrorRecorder()

            writer.enqueue(snapshot: latest, revision: 2) { error in
                errors.record(error)
                callbacks.fulfill()
            }
            writer.enqueue(snapshot: stale, revision: 1) { error in
                errors.record(error)
                callbacks.fulfill()
            }

            wait(for: [callbacks], timeout: 2)
            XCTAssertTrue(errors.values.isEmpty)
            XCTAssertEqual(try decodedState(at: stateURL).layoutMode, .space)
            XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        }
    }

    func testWriterReportsAsynchronousFilesystemFailure() throws {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-missing-persistence-\(UUID().uuidString)")
        let writer = StatePersistenceWriter(
            stateURL: missingDirectory.appendingPathComponent("布局.json"),
            backupStateURL: missingDirectory.appendingPathComponent("布局.backup.json")
        )
        let callback = expectation(description: "failed persistence callback")
        let errors = SendableErrorRecorder()

        writer.enqueue(snapshot: PersistedState(), revision: 1) { error in
            errors.record(error)
            callback.fulfill()
        }

        wait(for: [callback], timeout: 2)
        XCTAssertEqual(errors.values.count, 1)
    }

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

    private func withPersistenceFiles(
        _ body: (URL, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(
            directory.appendingPathComponent("布局.json"),
            directory.appendingPathComponent("布局.backup.json")
        )
    }

    private func decodedState(at url: URL) throws -> PersistedState {
        try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: url))
    }
}

private final class SendableErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.withLock { storage }
    }

    func record(_ error: Error?) {
        guard let error else { return }
        lock.withLock { storage.append(error) }
    }
}
