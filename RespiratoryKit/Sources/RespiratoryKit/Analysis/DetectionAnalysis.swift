import Foundation

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

    /// At most `maximumPoints` snapshots for drawing: the input is split into equal time buckets and each
    /// keeps its most confident snapshot, so a spike is never lost and a bucket holds a value at or
    /// above a threshold whenever any of its snapshots does. Display only: counts and events are
    /// always computed from the full list. Input is returned unchanged when it already fits.
    public static func peaks(_ snapshots: [DetectionSnapshot], maximumPoints: Int) -> [DetectionSnapshot] {
        guard maximumPoints > 0, snapshots.count > maximumPoints,
              let first = snapshots.map(\.timestamp).min(), let last = snapshots.map(\.timestamp).max(), last > first
        else { return maximumPoints > 0 ? snapshots : [] }
        let width = last.timeIntervalSince(first) / Double(maximumPoints)
        var best: [Int: DetectionSnapshot] = [:]
        for snapshot in snapshots {
            let bucket = min(Int(snapshot.timestamp.timeIntervalSince(first) / width), maximumPoints - 1)
            if let current = best[bucket], current.confidence >= snapshot.confidence { continue }
            best[bucket] = snapshot
        }
        return best.keys.sorted().compactMap { best[$0] }
    }

    /// Version of these interpretation rules, for anything exported alongside derived values.
    /// 2: debounce chains by the gap from the previous raw detection (was: from the kept event).
    public static let rulesVersion = 2

    /// Collapses same-label detections that chain together (each within `minInterEventGap` of the
    /// previous raw detection) into one event, since overlapping analysis windows report the same
    /// physical sound more than once. The event takes the first detection's time and the most
    /// confident detection's id and confidence, so grouping never depends on confidence order.
    /// Different labels are never merged.
    public static func debounce(
        _ snapshots: [DetectionSnapshot],
        minInterEventGap: TimeInterval
    ) -> [DebouncedEvent] {
        var result: [DebouncedEvent] = []
        for (_, group) in Dictionary(grouping: snapshots, by: \.label) {
            let sorted = group.sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
            var chain: [DetectionSnapshot] = []
            func flush() {
                guard let first = chain.first,
                      let best = chain.max(by: { $0.confidence < $1.confidence }) else { return }
                result.append(DebouncedEvent(id: best.id, timestamp: first.timestamp, label: first.label,
                                             confidence: best.confidence))
                chain = []
            }
            for snapshot in sorted {
                if let previous = chain.last, snapshot.timestamp.timeIntervalSince(previous.timestamp) >= minInterEventGap {
                    flush()
                }
                chain.append(snapshot)
            }
            flush()
        }
        return result.sorted { ($0.timestamp, $0.label) < ($1.timestamp, $1.label) }
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
