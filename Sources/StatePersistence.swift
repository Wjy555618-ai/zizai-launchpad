import Foundation

/// Serializes layout writes away from the main actor while preserving their
/// order. A synchronous flush is reserved for application termination.
final class StatePersistenceWriter: @unchecked Sendable {
    private let stateURL: URL
    private let backupStateURL: URL
    private let queue = DispatchQueue(
        label: "app.zizai.launchpad.persistence",
        qos: .utility
    )
    private var latestRevision = 0

    init(stateURL: URL, backupStateURL: URL) {
        self.stateURL = stateURL
        self.backupStateURL = backupStateURL
    }

    func enqueue(
        snapshot: PersistedState,
        revision: Int,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        // The bundle allows macOS sudden termination while idle. Keep that
        // optimization, but suspend it for the brief interval in which a
        // durable user-layout write is outstanding.
        ProcessInfo.processInfo.disableSuddenTermination()
        queue.async { [self] in
            defer { ProcessInfo.processInfo.enableSuddenTermination() }
            do {
                try persistIfCurrent(snapshot: snapshot, revision: revision)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func flush(snapshot: PersistedState, revision: Int) throws {
        try queue.sync {
            try persistIfCurrent(snapshot: snapshot, revision: revision)
        }
    }

    private func persistIfCurrent(snapshot: PersistedState, revision: Int) throws {
        guard revision > latestRevision else { return }
        try PersistedStateIO.write(snapshot, stateURL: stateURL, backupStateURL: backupStateURL)
        latestRevision = revision
    }
}

enum PersistedStateIO {
    static func write(_ snapshot: PersistedState, stateURL: URL, backupStateURL: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        if let current = try? Data(contentsOf: stateURL),
            (try? JSONDecoder().decode(PersistedState.self, from: current)) != nil
        {
            try current.write(to: backupStateURL, options: .atomic)
        }
        try data.write(to: stateURL, options: .atomic)
    }
}
