import Foundation

/// Runs async work one item at a time, in the order it was enqueued, and lets a caller wait for
/// everything queued so far. Used to save provider attempts in the order they happened and to make
/// sure a background run doesn't finish (and get suspended) with saves still pending.
@MainActor
public final class OrderedTaskQueue {
    private var tail: Task<Void, Never>?

    public init() {}

    public func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await work()
        }
    }

    /// Returns once every item enqueued before this call has finished.
    public func flush() async { await tail?.value }
}
