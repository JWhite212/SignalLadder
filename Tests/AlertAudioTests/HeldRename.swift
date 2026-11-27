import Foundation

/// Holds one thread in the middle of a rename, so that a test can look at the sounds folder from another
/// thread while a sound has been set aside and the one that replaces it has not yet been given its name.
///
/// A step that takes a `move` seam is handed `move`, which says it has been reached, waits to be let go,
/// and then renames as the step would have.
final class HeldRename: @unchecked Sendable {
    private let reached = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    /// The longest anything waits, so that a test that goes wrong stops and does not hang.
    static let patience: TimeInterval = 10

    var move: (URL, URL) throws -> Void {
        { [self] from, to in
            reached.signal()
            _ = released.wait(timeout: .now() + Self.patience)
            try FileManager.default.moveItem(at: from, to: to)
        }
    }

    /// True once a rename is being held.
    func waitUntilHeld() -> Bool {
        reached.wait(timeout: .now() + Self.patience) == .success
    }

    func letGo() {
        released.signal()
    }
}

/// A value one thread leaves for another to read once it has been waited for.
final class Slot<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var held: Value?

    var value: Value? {
        get { lock.lock(); defer { lock.unlock() }; return held }
        set { lock.lock(); defer { lock.unlock() }; held = newValue }
    }
}
