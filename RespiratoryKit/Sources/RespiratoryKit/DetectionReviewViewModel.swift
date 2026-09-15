import Foundation
import Observation

@MainActor @Observable
public final class DetectionReviewViewModel {
    public static let historyLimit = 500
    public private(set) var snapshots: [DetectionSnapshot] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var isShowingAllHistory = false
    public var canLoadAllHistory: Bool { !isShowingAllHistory && snapshots.count >= Self.historyLimit }
    private let store: any DetectionStoring

    public init(store: any DetectionStoring) { self.store = store }

    public func load(allHistory: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let includeAll = allHistory || isShowingAllHistory
            let fetched = try await store.fetchSnapshots(limit: includeAll ? nil : Self.historyLimit, newestFirst: true)
            try Task.checkCancellation()
            snapshots = fetched
            isShowingAllHistory = includeAll
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    public func toggleFalsePositive(_ snapshot: DetectionSnapshot) async {
        guard !isLoading, let current = snapshots.first(where: { $0.id == snapshot.id }) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await store.setFalsePositive(current.id, isFalsePositive: !current.isFalsePositive)
            // A committed annotation updates the existing row; no full-history refetch.
            snapshots = snapshots.map {
                guard $0.id == current.id else { return $0 }
                return DetectionSnapshot(id: $0.id, timestamp: $0.timestamp, label: $0.label,
                                         confidence: $0.confidence, isFalsePositive: !current.isFalsePositive)
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }
}
