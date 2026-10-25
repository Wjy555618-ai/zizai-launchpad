import Foundation

/// Bounded, value-semantic undo history for persisted product state.
///
/// Storing complete validated snapshots makes undo independent from view
/// closures and from the lifetime of scanned `AppInfo` instances. Every
/// library command can therefore restore exactly the same aggregate that was
/// persisted before the command.
struct LauncherStateHistory {
    private(set) var snapshots: [PersistedState] = []
    let capacity: Int

    init(capacity: Int = 20) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var canUndo: Bool { !snapshots.isEmpty }

    mutating func record(previous: PersistedState, current: PersistedState) {
        guard previous != current else { return }
        snapshots.append(previous)
        if snapshots.count > capacity {
            snapshots.removeFirst(snapshots.count - capacity)
        }
    }

    mutating func popLast() -> PersistedState? {
        snapshots.popLast()
    }
}
