import Foundation
import Observation

@MainActor @Observable
public final class ListenViewModel {
    public enum Phase: Sendable { case idle, starting, listening, stopping }
    public private(set) var phase: Phase = .idle
    /// Newest first, bounded; UI only (every window is persisted by the store regardless).
    public private(set) var windows: [WindowObservation] = []
    public private(set) var scoredLabels: [String] = []
    public private(set) var sessionStartedAt: Date?
    public private(set) var windowCount = 0
    public private(set) var lastOutcome: IngestOutcome?
    public private(set) var errorMessage: String?

    private let controller: any AudioAnalyzing
    private let store: any DetectionStoring
    private let appVersion: String
    private let displayLimit: Int
    private var stopRequest: ListeningStopRequest?

    public init(controller: any AudioAnalyzing, store: any DetectionStoring, appVersion: String, displayLimit: Int = 200) {
        self.controller = controller
        self.store = store
        self.appVersion = appVersion
        self.displayLimit = max(1, displayLimit)
    }

    public var latest: WindowObservation? { windows.first }

    public func score(_ label: String, in window: WindowObservation) -> Float? {
        window.score(for: label, in: scoredLabels)
    }

    /// Records why the owner is about to cancel `listen()`. The first reason given wins; a
    /// cancellation without one is recorded as navigating away.
    public func requestStop(_ reason: ListeningEndReason) {
        stopRequest?.request(reason)
    }

    /// The caller owns this operation's lifetime (SwiftUI `.task` in the app). Cancelling it stops
    /// capture, but the store still drains and saves every analysed window before this returns.
    public func listen() async {
        guard phase == .idle, !Task.isCancelled else { return }
        phase = .starting
        errorMessage = nil
        lastOutcome = nil
        windows = []
        windowCount = 0
        let request = ListeningStopRequest()
        stopRequest = request
        let controller = controller
        do {
            let session = try await controller.start()
            let sessionID = session.info.id
            let stopCapture: @Sendable () async -> Void = { await controller.stop(sessionID: sessionID) }
            scoredLabels = session.info.scoredLabels
            sessionStartedAt = session.info.requestedAt
            phase = .listening
            let ingest = await withTaskCancellationHandler {
                let ingest = await store.beginIngest(session.info, appVersion: appVersion, events: session.events,
                                                     stopRequest: request, stopCapture: stopCapture)
                for await window in session.display { show(window) }
                return ingest
            } onCancel: {
                request.request(.navigatedAway)
                Task { await stopCapture() }
            }
            phase = .stopping
            await stopCapture()
            let outcome = await ingest.value
            lastOutcome = outcome
            if let failure = outcome.failure { errorMessage = failure }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
        stopRequest = nil
        sessionStartedAt = nil
        phase = .idle
    }

    private func show(_ window: WindowObservation) {
        windowCount += 1
        windows.insert(window, at: 0)
        if windows.count > displayLimit { windows.removeLast(windows.count - displayLimit) }
    }
}
