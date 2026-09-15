import Foundation

/// The interpretation knobs applied at read time, never baked into stored
/// data. Retuning any of these recomputes counts/bouts over the exact same
/// raw history — no migration, nothing to go stale.
public struct DetectionTuningParameters: Sendable, Equatable {
    public var confidenceThreshold: Double
    public var minInterEventGap: TimeInterval
    public var boutGapThreshold: TimeInterval

    public init(
        confidenceThreshold: Double = 0.5,
        minInterEventGap: TimeInterval = 1.0,
        boutGapThreshold: TimeInterval = 10.0
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.minInterEventGap = minInterEventGap
        self.boutGapThreshold = boutGapThreshold
    }
}
