import Foundation

/// A running capture. `events` must be persisted without loss (it ends with an error on overload);
/// `display` keeps only the newest windows and is for UI only.
public struct AudioAnalysisSession: Sendable {
    public let info: CaptureSessionInfo
    public let events: AsyncThrowingStream<CaptureEvent, any Error>
    public let display: AsyncStream<WindowObservation>

    public init(info: CaptureSessionInfo, events: AsyncThrowingStream<CaptureEvent, any Error>,
                display: AsyncStream<WindowObservation>) {
        self.info = info
        self.events = events
        self.display = display
    }
}

public protocol AudioAnalyzing: Sendable {
    /// A failed start cleans up any resources it acquired before throwing.
    func start() async throws -> AudioAnalysisSession
    /// Stops the matching session and waits for cleanup, ignoring obsolete session IDs.
    func stop(sessionID: UUID) async
}

public protocol DetectionStoring: Sendable {
    /// Persists a session's events in a store-owned task that the caller's cancellation can't cut
    /// short. `stopCapture` is called if storage fails, so capture never outlives persistence.
    func beginIngest(_ info: CaptureSessionInfo, appVersion: String,
                     events: AsyncThrowingStream<CaptureEvent, any Error>, stopRequest: ListeningStopRequest,
                     stopCapture: @escaping @Sendable () async -> Void) async -> Task<IngestOutcome, Never>
    func candidates(label: String, in interval: DateInterval?, minimumConfidence: Double) async throws -> [DetectionSnapshot]
    func sessions(in interval: DateInterval?) async throws -> [ListeningSessionSnapshot]
    func annotate(_ target: DetectionSnapshot, verdict: AnnotationVerdict, source: String, note: String?,
                  at date: Date, appVersion: String) async throws
}

extension DetectionStoring {
    /// Every candidate in the range, whatever its score (Tuning needs the whole distribution).
    func candidates(label: String, in interval: DateInterval?) async throws -> [DetectionSnapshot] {
        try await candidates(label: label, in: interval, minimumConfidence: 0)
    }
}
