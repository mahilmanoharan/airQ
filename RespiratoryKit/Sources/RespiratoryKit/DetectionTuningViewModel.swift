import Foundation
import Observation

@MainActor @Observable
public final class DetectionTuningViewModel {
    public private(set) var snapshots: [DetectionSnapshot] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var parameters = DetectionTuningParameters() { didSet { recompute() } }
    public private(set) var filteredEvents: [DetectionSnapshot] = []
    public private(set) var debouncedEvents: [DebouncedEvent] = []
    public private(set) var bouts: [CoughBout] = []
    private let store: any DetectionStoring

    public init(store: any DetectionStoring) { self.store = store }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await store.fetchSnapshots(limit: nil, newestFirst: false)
            try Task.checkCancellation()
            snapshots = fetched
            recompute()
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    /// One pipeline per input change, not repeated filtering/sorting for every count in body.
    /// These are in-memory interpretations, never persisted.
    private func recompute() {
        filteredEvents = DetectionAnalysis.filterByThreshold(snapshots, threshold: parameters.confidenceThreshold)
        debouncedEvents = DetectionAnalysis.debounce(filteredEvents, minInterEventGap: parameters.minInterEventGap)
        bouts = DetectionAnalysis.cluster(debouncedEvents, boutGapThreshold: parameters.boutGapThreshold)
    }
}
