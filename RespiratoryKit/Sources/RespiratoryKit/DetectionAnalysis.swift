import Foundation
import SwiftData

/// One physical cough (or other event) after collapsing duplicate reports
/// from overlapping analysis windows.
public struct DebouncedEvent: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let label: String
    public let confidence: Double

    public init(id: UUID, timestamp: Date, label: String, confidence: Double) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.confidence = confidence
    }
}

/// A cluster of debounced events close enough together to count as one
/// clinical episode. Always computed live from stored events + whatever
/// `boutGapThreshold` is currently set — never persisted as its own model,
/// since a bout is an interpretation, not an observation.
public struct CoughBout: Sendable, Equatable {
    public let events: [DebouncedEvent]

    public init(events: [DebouncedEvent]) {
        self.events = events
    }

    public var start: Date { events.first?.timestamp ?? .distantPast }
    public var end: Date { events.last?.timestamp ?? .distantPast }
    public var count: Int { events.count }
}

/// Pure functions over stored data — no I/O, no persistence, nothing
/// actor-isolated. Operates only on `Sendable` value types, never a live
/// `DetectionEvent`, so these are trivially testable and trivially safe to
/// call from any isolation domain (the tuning screen recomputes them live
/// on every slider change).
public enum DetectionAnalysis {

    /// Excludes anything below the current confidence threshold or already
    /// marked a false positive. This is the one place a threshold is ever
    /// applied — never at write time, only here, at read time.
    public static func filterByThreshold(
        _ snapshots: [DetectionSnapshot],
        threshold: Double
    ) -> [DetectionSnapshot] {
        snapshots.filter { $0.confidence >= threshold && !$0.isFalsePositive }
    }

    /// Collapses same-label detections closer together than
    /// `minInterEventGap` into a single event (keeping the higher-confidence
    /// one), since overlapping analysis windows can report the same
    /// physical cough more than once. Different labels are never merged,
    /// even if close in time, to avoid conflating distinct sounds.
    public static func debounce(
        _ snapshots: [DetectionSnapshot],
        minInterEventGap: TimeInterval
    ) -> [DebouncedEvent] {
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        var result: [DebouncedEvent] = []

        for snapshot in sorted {
            if let last = result.last,
               last.label == snapshot.label,
               snapshot.timestamp.timeIntervalSince(last.timestamp) < minInterEventGap {
                if snapshot.confidence > last.confidence {
                    result[result.count - 1] = DebouncedEvent(
                        id: snapshot.id,
                        timestamp: snapshot.timestamp,
                        label: snapshot.label,
                        confidence: snapshot.confidence
                    )
                }
                continue
            }
            result.append(
                DebouncedEvent(
                    id: snapshot.id,
                    timestamp: snapshot.timestamp,
                    label: snapshot.label,
                    confidence: snapshot.confidence
                )
            )
        }

        return result
    }

    /// Clusters debounced events into bouts: consecutive events no more
    /// than `boutGapThreshold` apart. Bout count and raw event count are
    /// clinically different — this is always recomputed, never stored.
    public static func cluster(
        _ events: [DebouncedEvent],
        boutGapThreshold: TimeInterval
    ) -> [CoughBout] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var bouts: [CoughBout] = []
        var current: [DebouncedEvent] = []

        for event in sorted {
            if let last = current.last, event.timestamp.timeIntervalSince(last.timestamp) > boutGapThreshold {
                bouts.append(CoughBout(events: current))
                current = []
            }
            current.append(event)
        }
        if !current.isEmpty {
            bouts.append(CoughBout(events: current))
        }

        return bouts
    }
}
