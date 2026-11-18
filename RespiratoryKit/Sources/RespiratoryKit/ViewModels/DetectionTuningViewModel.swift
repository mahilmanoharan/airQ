import Foundation
import Observation

@MainActor @Observable
public final class DetectionTuningViewModel {
    public private(set) var snapshots: [DetectionSnapshot] = []
    public private(set) var sessions: [ListeningSessionSnapshot] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var parameters: DetectionTuningParameters { didSet { recompute() } }
    public private(set) var filteredEvents: [DetectionSnapshot] = []
    public private(set) var debouncedEvents: [DebouncedEvent] = []
    public private(set) var bouts: [CoughBout] = []

    /// Changing the query requires `load()`; changing `parameters` recomputes in memory.
    public var label = "cough"
    public var range: DetectionRange = .lastWeek

    private let store: any DetectionStoring
    private let now: @Sendable () -> Date
    /// Each load supersedes earlier ones: only the newest query's result is applied.
    private var loadGeneration = 0

    public init(store: any DetectionStoring, parameters: DetectionTuningParameters = .init(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.parameters = parameters
        self.now = now
    }

    /// Listening time known to have happened in the loaded sessions (clipped to nothing; a session
    /// overlapping the range edge counts in full).
    public var listeningDuration: TimeInterval { sessions.reduce(0) { $0 + $1.knownDuration } }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let interval = range.interval(endingAt: now())
            let fetched = try await store.candidates(label: label, in: interval)
            let sessions = try await store.sessions(in: interval)
            guard generation == loadGeneration else { return }
            try Task.checkCancellation()
            snapshots = fetched
            self.sessions = sessions
            recompute()
        } catch {
            guard generation == loadGeneration else { return }
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
