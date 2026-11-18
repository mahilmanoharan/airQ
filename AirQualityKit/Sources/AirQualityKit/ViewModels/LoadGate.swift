import Foundation

/// Lets several `DashboardViewModel`s that share a cache (the dashboard and the background
/// refresh) fetch one at a time. The waiter re-checks the cache once it gets its turn, so two
/// models that both saw a stale reading make one request between them, not two.
@MainActor
public final class LoadGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    func acquire() async {
        guard isBusy else { isBusy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
    }
}
