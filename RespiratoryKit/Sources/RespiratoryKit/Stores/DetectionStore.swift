import Foundation
import SwiftData

/// Background-safe SwiftData access for detections. Capture is persisted on this actor's executor,
/// never the main actor, and only value snapshots cross its boundary.
@ModelActor
public actor DetectionStore: DetectionStoring {
    public static let saveEveryWindows = 50
    public static let saveEverySeconds: TimeInterval = 5
    private var writesPaused = false

    public func setWritesPaused(_ paused: Bool) { writesPaused = paused }

    /// `@concurrent` keeps ModelActor construction off the caller's actor, so its ModelContext is
    /// never bound to the UI executor regardless of the caller's isolation. Share one container
    /// (from `RespiratoryStore.openContainer()`) across store actors.
    @concurrent
    public static func open(container: ModelContainer) async -> DetectionStore {
        DetectionStore(modelContainer: container)
    }

    // MARK: Capture

    /// Starts persisting a session in a task owned by this actor. The task inherits the actor's
    /// isolation but not the caller's cancellation, so a cancelled view never cuts the drain short:
    /// every window the pipeline delivers before its stream ends is saved.
    public func beginIngest(_ info: CaptureSessionInfo, appVersion: String,
                            events: AsyncThrowingStream<CaptureEvent, any Error>,
                            stopRequest: ListeningStopRequest,
                            stopCapture: @escaping @Sendable () async -> Void) -> Task<IngestOutcome, Never> {
        Task { await self.ingest(info, appVersion: appVersion, events: events, stopRequest: stopRequest,
                                 stopCapture: stopCapture) }
    }

    private func ingest(_ info: CaptureSessionInfo, appVersion: String,
                        events: AsyncThrowingStream<CaptureEvent, any Error>, stopRequest: ListeningStopRequest,
                        stopCapture: @Sendable () async -> Void) async -> IngestOutcome {
        if writesPaused {
            await stopCapture()
            return IngestOutcome(windowCount: 0, endReason: .storageFailed,
                                 failure: RecordStoreError.eraseInProgress.localizedDescription)
        }
        let session = ListeningSession(
            id: info.id, startedAt: info.requestedAt, timeZoneID: info.timeZoneID, sampleRate: info.sampleRate,
            channelCount: info.channelCount, tapBufferSize: info.tapBufferSize, inputPortType: info.inputPortType,
            inputPortName: info.inputPortName, classifierIdentifier: info.classifierIdentifier,
            windowDuration: info.windowDuration, overlapFactor: info.overlapFactor, scoredLabels: info.scoredLabels,
            topK: info.topK, captureSemanticsVersion: info.captureSemanticsVersion, appVersion: appVersion,
            osVersion: info.osVersion, deviceModel: info.deviceModel)
        modelContext.insert(session)
        var windowCount = 0
        var pending = 0
        var lastSave = Date()
        var streamReason: ListeningEndReason?
        var failure: String?
        var storageError: (any Error)?

        do { try save() } catch { storageError = error }
        if storageError == nil {
            do {
                for try await event in events {
                    switch event {
                    case .started(let date):
                        session.startedAt = date
                    case .window(let window):
                        modelContext.insert(ClassifierWindow(
                            id: window.id, sessionID: info.id, windowIndex: window.windowIndex,
                            startFrame: window.startFrame, durationFrames: window.durationFrames,
                            deliveredAt: window.deliveredAt, scores: window.scores, topLabels: window.topLabels,
                            topScores: window.topScores, rms: window.rms, peak: window.peak))
                        windowCount += 1
                        pending += 1
                    }
                    if pending >= Self.saveEveryWindows || Date().timeIntervalSince(lastSave) >= Self.saveEverySeconds {
                        do { try save() } catch { storageError = error; break }
                        pending = 0
                        lastSave = Date()
                    }
                }
            } catch {
                streamReason = ListeningEndReason(error)
                failure = error.localizedDescription
            }
        }
        if storageError == nil {
            do { try save() } catch { storageError = error }
        }
        if let storageError {
            // Stop capturing so nothing more is silently lost, let the pipeline finish, and say so.
            await stopCapture()
            do { for try await _ in events {} } catch {}
            return IngestOutcome(windowCount: windowCount - pending, endReason: .storageFailed,
                                 failure: "Detections could not be saved: \(storageError.localizedDescription)")
        }
        let reason = streamReason ?? stopRequest.reason ?? .userStopped
        session.endedAt = Date()
        session.endReason = reason.rawValue
        do { try save() }
        catch { failure = failure ?? "The session's end could not be saved: \(error.localizedDescription)" }
        return IngestOutcome(windowCount: windowCount, endReason: reason, failure: failure)
    }

    // MARK: Reading

    /// Every candidate for `label` in `interval` (all history when nil), oldest first, with verdicts
    /// resolved. V2 windows yield the label's score at any rank; V1 rows exist only where the label
    /// ranked first. Thresholds are the caller's read-time choice. `minimumConfidence` only keeps a wide
    /// range from materialising every window: a caller that will threshold anyway passes its threshold
    /// (nothing is stored differently, and 0 returns everything).
    public func candidates(label: String, in interval: DateInterval?, minimumConfidence: Double = 0) throws -> [DetectionSnapshot] {
        let lower = interval?.start ?? .distantPast
        let upper = interval?.end ?? .distantFuture
        var result: [DetectionSnapshot] = []

        let sessions = try modelContext.fetch(FetchDescriptor<ListeningSession>(
            predicate: #Predicate { $0.startedAt < upper }))
            .filter { ($0.endedAt ?? .distantFuture) >= lower }
        for session in sessions {
            let sessionID = session.id
            let rate = session.sampleRate > 0 ? session.sampleRate : 1
            // Only this session's windows whose start falls in the range (clamped to the session).
            let firstFrame = Int64(max(0, (lower.timeIntervalSince(session.startedAt) * rate).rounded(.down)))
            let endFrame = Int64(min(Double(Int64.max / 2), (upper.timeIntervalSince(session.startedAt) * rate).rounded(.up)))
            guard endFrame >= 0 else { continue }
            let windows = try modelContext.fetch(FetchDescriptor<ClassifierWindow>(
                predicate: #Predicate { $0.sessionID == sessionID && $0.startFrame >= firstFrame && $0.startFrame <= endFrame },
                sortBy: [SortDescriptor(\.startFrame)]))
            for window in windows {
                let time = session.startedAt.addingTimeInterval(Double(window.startFrame) / rate)
                guard time >= lower, time < upper else { continue }
                let observation = WindowObservation(
                    id: window.id, windowIndex: window.windowIndex, startFrame: window.startFrame,
                    durationFrames: window.durationFrames, deliveredAt: window.deliveredAt, scores: window.scores,
                    topLabels: window.topLabels, topScores: window.topScores, rms: window.rms, peak: window.peak)
                guard let score = observation.score(for: label, in: session.scoredLabels),
                      Double(score) >= minimumConfidence else { continue }
                result.append(DetectionSnapshot(
                    id: window.id, source: .window, sessionID: sessionID, timestamp: time, label: label,
                    confidence: Double(score), rank: window.topLabels.firstIndex(of: label).map { $0 + 1 },
                    captureSemanticsVersion: session.captureSemanticsVersion,
                    topLabel: window.topLabels.first, topScore: window.topScores.first.map(Double.init)))
            }
        }

        let legacy = try modelContext.fetch(FetchDescriptor<DetectionEvent>(
            predicate: #Predicate { $0.label == label && $0.timestamp >= lower && $0.timestamp < upper }))
        let legacyBase = Dictionary(legacy.map { ($0.id, $0.isFalsePositive) }, uniquingKeysWith: { $0 || $1 })
        result += legacy.filter { $0.confidence >= minimumConfidence }.map {
            DetectionSnapshot(id: $0.id, source: .legacy, sessionID: $0.sessionID, timestamp: $0.timestamp,
                              label: $0.label, confidence: $0.confidence, rank: 1, captureSemanticsVersion: 1,
                              topLabel: $0.label, topScore: $0.confidence)
        }

        let verdicts = AnnotationResolution.latest(try annotationRows(label: label), legacyFalsePositives: legacyBase)
        return result
            .map { $0.with(verdict: verdicts[$0.id]) }
            .sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
    }

    public func sessions(in interval: DateInterval?) throws -> [ListeningSessionSnapshot] {
        let upper = interval?.end ?? .distantFuture
        let lower = interval?.start ?? .distantPast
        let sessions = try modelContext.fetch(FetchDescriptor<ListeningSession>(
            predicate: #Predicate { $0.startedAt < upper }, sortBy: [SortDescriptor(\.startedAt)]))
        return try sessions.compactMap { session in
            let sessionID = session.id
            var last = FetchDescriptor<ClassifierWindow>(predicate: #Predicate { $0.sessionID == sessionID },
                                                         sortBy: [SortDescriptor(\.startFrame, order: .reverse)])
            last.fetchLimit = 1
            let count = try modelContext.fetchCount(FetchDescriptor<ClassifierWindow>(
                predicate: #Predicate { $0.sessionID == sessionID }))
            let rate = session.sampleRate > 0 ? session.sampleRate : 1
            let lastEnd = try modelContext.fetch(last).first.map {
                session.startedAt.addingTimeInterval(Double($0.startFrame + $0.durationFrames) / rate)
            }
            let snapshot = ListeningSessionSnapshot(
                id: session.id, startedAt: session.startedAt, endedAt: session.endedAt, endReason: session.endReason,
                windowCount: count, lastWindowEnd: lastEnd, captureSemanticsVersion: session.captureSemanticsVersion,
                inputPortType: session.inputPortType)
            return snapshot.knownEnd >= lower ? snapshot : nil
        }
    }

    // MARK: Annotations

    /// Appends a verdict; earlier verdicts are kept and the latest wins at read time.
    public func annotate(_ target: DetectionSnapshot, verdict: AnnotationVerdict, source: String,
                         note: String?, at date: Date, appVersion: String) throws {
        guard !writesPaused else { throw RecordStoreError.eraseInProgress }
        let row = DetectionAnnotation(
            targetWindowID: target.source == .window ? target.id : nil,
            targetLegacyEventID: target.source == .legacy ? target.id : nil,
            label: target.label, verdict: verdict.rawValue, createdAt: date, source: source, note: note,
            appVersion: appVersion)
        modelContext.insert(row)
        try save(undoing: row)
    }

    private func annotationRows(label: String) throws -> [AnnotationRow] {
        try modelContext.fetch(FetchDescriptor<DetectionAnnotation>(predicate: #Predicate { $0.label == label })).compactMap {
            guard let target = $0.targetWindowID ?? $0.targetLegacyEventID else { return nil }
            return AnnotationRow(targetID: target, verdict: $0.verdict, createdAt: $0.createdAt, id: $0.id)
        }
    }

    // MARK: Legacy (capture semantics 1)

    /// Writes a V1 row. Build 3+ no longer captures this way; kept for fixtures and migration tests.
    func recordLegacy(sessionID: UUID, label: String, confidence: Double, timestamp: Date,
                      config: DetectionConfig, isFalsePositive: Bool = false) throws {
        let row = DetectionEvent(sessionID: sessionID, timestamp: timestamp, label: label,
                                 confidence: confidence, config: config, isFalsePositive: isFalsePositive)
        modelContext.insert(row)
        try save(undoing: row)
    }

    /// The context is shared with a running ingest, whose unsaved windows a `rollback()` would silently
    /// discard. A caller's own insert is withdrawn by itself instead; ingest (which ends the session on
    /// a failed save) is the only caller that rolls back.
    private func save(undoing inserted: (any PersistentModel)? = nil) throws {
        do { try modelContext.save() }
        catch {
            if let inserted { modelContext.delete(inserted) } else { modelContext.rollback() }
            throw error
        }
    }
}

struct AnnotationRow: Sendable, Equatable {
    let targetID: UUID
    let verdict: String
    let createdAt: Date
    let id: UUID
}

enum AnnotationResolution {
    /// Latest annotation per target (the caller filters by label) wins; `cleared` and unknown future
    /// verdicts withdraw. A legacy `isFalsePositive` flag is the baseline before any annotation.
    static func latest(_ rows: [AnnotationRow], legacyFalsePositives: [UUID: Bool]) -> [UUID: AnnotationVerdict] {
        var result: [UUID: AnnotationVerdict] = [:]
        for (id, flagged) in legacyFalsePositives where flagged { result[id] = .falsePositive }
        let latest = Dictionary(grouping: rows, by: \.targetID).compactMapValues { group in
            group.max { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        }
        for (target, row) in latest {
            switch AnnotationVerdict(rawValue: row.verdict) {
            case .cleared, nil: result[target] = nil
            case let verdict?: result[target] = verdict
            }
        }
        return result
    }
}
