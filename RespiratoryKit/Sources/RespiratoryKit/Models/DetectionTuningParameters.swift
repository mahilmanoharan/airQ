import Foundation

/// The interpretation knobs applied at read time, never baked into stored
/// data. Retuning any of these recomputes counts/bouts over the exact same
/// raw history — no migration, nothing to go stale.
public struct DetectionTuningParameters: Sendable, Equatable, Codable {
    public var confidenceThreshold: Double
    public var minInterEventGap: TimeInterval
    public var boutGapThreshold: TimeInterval

    public init(
        confidenceThreshold: Double = 0.5,
        // Must exceed the classifier's window hop (3 s windows at 50% overlap start 1.5 s apart),
        // or one sound spanning two overlapping windows counts twice.
        minInterEventGap: TimeInterval = 2.0,
        boutGapThreshold: TimeInterval = 10.0
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.minInterEventGap = minInterEventGap
        self.boutGapThreshold = boutGapThreshold
    }
}
