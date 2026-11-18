import Foundation

/// A reviewer's verdict about one label on one detection target. Stored as the raw value.
public enum AnnotationVerdict: String, Sendable, CaseIterable {
    case falsePositive, confirmed, unsure
    /// Withdraws an earlier verdict (including a legacy false-positive flag).
    case cleared
}

/// A `Sendable` candidate detection: one label's score on one V2 window, or one V1 top-ranked
/// event. `@Model` instances never leave the store actor; this value type crosses instead.
///
/// Keyed by the row's own `UUID`, not `PersistentIdentifier` (which has no public initializer and
/// so can't be built as test fixture data).
public struct DetectionSnapshot: Sendable, Identifiable, Equatable {
    public enum Source: String, Sendable { case window, legacy }

    public let id: UUID
    public let source: Source
    public let sessionID: UUID?
    public let timestamp: Date
    public let label: String
    public let confidence: Double
    /// 1-based rank of `label` in the window's top-K, nil when it ranked lower.
    public let rank: Int?
    /// 1 = legacy top-1 allowlisted rows; 2 = per-window scores.
    public let captureSemanticsVersion: Int
    /// The latest verdict for (target, label), resolved at read time; nil means none.
    public let verdict: AnnotationVerdict?
    /// The window's top-ranked sound and score, for context when reviewing (a legacy row's own label).
    public let topLabel: String?
    public let topScore: Double?

    public var isFalsePositive: Bool { verdict == .falsePositive }

    public init(id: UUID, source: Source = .legacy, sessionID: UUID? = nil, timestamp: Date, label: String,
                confidence: Double, rank: Int? = 1, captureSemanticsVersion: Int = 1, verdict: AnnotationVerdict? = nil,
                topLabel: String? = nil, topScore: Double? = nil) {
        self.id = id
        self.source = source
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.label = label
        self.confidence = confidence
        self.rank = rank
        self.captureSemanticsVersion = captureSemanticsVersion
        self.verdict = verdict
        self.topLabel = topLabel
        self.topScore = topScore
    }

    /// Legacy convenience used by fixtures.
    public init(id: UUID, timestamp: Date, label: String, confidence: Double, isFalsePositive: Bool) {
        self.init(id: id, timestamp: timestamp, label: label, confidence: confidence,
                  verdict: isFalsePositive ? .falsePositive : nil)
    }

    public func with(verdict: AnnotationVerdict?) -> DetectionSnapshot {
        DetectionSnapshot(id: id, source: source, sessionID: sessionID, timestamp: timestamp, label: label,
                          confidence: confidence, rank: rank, captureSemanticsVersion: captureSemanticsVersion,
                          verdict: verdict, topLabel: topLabel, topScore: topScore)
    }
}

/// One listening session as stored, with read-time derived bounds.
public struct ListeningSessionSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let endReason: String?
    public let windowCount: Int
    /// End of the last stored window: a lower bound on listening time when `endedAt` is nil.
    public let lastWindowEnd: Date?
    public let captureSemanticsVersion: Int
    public let inputPortType: String?

    public init(id: UUID, startedAt: Date, endedAt: Date?, endReason: String?, windowCount: Int,
                lastWindowEnd: Date?, captureSemanticsVersion: Int, inputPortType: String?) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.windowCount = windowCount
        self.lastWindowEnd = lastWindowEnd
        self.captureSemanticsVersion = captureSemanticsVersion
        self.inputPortType = inputPortType
    }

    /// Listening time known to have happened: to `endedAt`, else to the last window.
    public var knownEnd: Date { endedAt ?? lastWindowEnd ?? startedAt }
    public var knownDuration: TimeInterval { max(0, knownEnd.timeIntervalSince(startedAt)) }
}
