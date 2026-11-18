import Foundation
import Observation

/// Review of candidate detections for one label above a display threshold. Verdicts are appended
/// as annotations; the observation itself is never changed.
@MainActor @Observable
public final class DetectionReviewViewModel {
    public static let historyLimit = 500
    public private(set) var snapshots: [DetectionSnapshot] = []
    public private(set) var matchingCount = 0
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var isShowingAllMatches = false
    public var canShowAllMatches: Bool { !isShowingAllMatches && matchingCount > snapshots.count }

    public var label = "cough"
    public var threshold = 0.5
    public var range: DetectionRange = .lastWeek

    private let store: any DetectionStoring
    private let appVersion: String
    /// Each load supersedes earlier ones: only the newest query's result is applied.
    private var loadGeneration = 0
    private let now: @Sendable () -> Date

    public init(store: any DetectionStoring, appVersion: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.appVersion = appVersion
        self.now = now
    }

    public func load(showAll: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let fetched = try await store.candidates(label: label, in: range.interval(endingAt: now()), minimumConfidence: threshold)
            guard generation == loadGeneration else { return }
            try Task.checkCancellation()
            let matching = fetched.filter { $0.confidence >= threshold }.reversed()
            matchingCount = matching.count
            isShowingAllMatches = showAll
            snapshots = showAll ? Array(matching) : Array(matching.prefix(Self.historyLimit))
        } catch {
            guard generation == loadGeneration else { return }
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    /// Setting the current verdict again withdraws it.
    public func toggle(_ verdict: AnnotationVerdict, for snapshot: DetectionSnapshot) async {
        guard let current = snapshots.first(where: { $0.id == snapshot.id }) else { return }
        await annotate(current, verdict: current.verdict == verdict ? .cleared : verdict)
    }

    public func annotate(_ snapshot: DetectionSnapshot, verdict: AnnotationVerdict) async {
        errorMessage = nil
        do {
            try await store.annotate(snapshot, verdict: verdict, source: "review", note: nil, at: now(),
                                     appVersion: appVersion)
            let resolved: AnnotationVerdict? = verdict == .cleared ? nil : verdict
            snapshots = snapshots.map { $0.id == snapshot.id ? $0.with(verdict: resolved) : $0 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
