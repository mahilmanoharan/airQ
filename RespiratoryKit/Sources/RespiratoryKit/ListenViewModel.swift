import Foundation
import Observation

@MainActor @Observable
public final class ListenViewModel {
    public enum Phase: Sendable { case idle, starting, listening, stopping }
    public private(set) var phase: Phase = .idle
    public private(set) var detections: [RawDetection] = []
    public private(set) var errorMessage: String?

    private let controller: any AudioAnalyzing
    private let store: any DetectionStoring
    private let appVersion: String
    private let displayLimit: Int

    public init(controller: any AudioAnalyzing, store: any DetectionStoring, appVersion: String, displayLimit: Int = 200) {
        self.controller = controller
        self.store = store
        self.appVersion = appVersion
        self.displayLimit = max(1, displayLimit)
    }

    /// The caller owns this operation's lifetime (SwiftUI `.task` in the app).
    /// Cancellation drains cleanup before another session may start.
    public func listen() async {
        guard phase == .idle, !Task.isCancelled else { return }
        phase = .starting
        errorMessage = nil
        do {
            let session = try await controller.start()
            try Task.checkCancellation()
            phase = .listening
            let config = DetectionConfig(windowDuration: session.config.windowDuration,
                                         overlapFactor: session.config.overlapFactor,
                                         classifierIdentifier: session.config.classifierIdentifier,
                                         appVersion: appVersion)
            for try await detection in session.stream {
                try Task.checkCancellation()
                detections.insert(detection, at: 0)
                if detections.count > displayLimit { detections.removeLast(detections.count - displayLimit) }
                guard RespiratoryLabels.allowlist.contains(detection.label) else { continue }
                // No confidence threshold here: interpretations belong to read time.
                try await store.record(sessionID: session.sessionID, label: detection.label,
                                       confidence: detection.confidence, timestamp: detection.timestamp, config: config)
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
        phase = .stopping
        await controller.stop()
        phase = .idle
    }
}
