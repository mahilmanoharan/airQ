import Foundation
import SwiftData

/// A single raw classifier observation. Every field is either exactly what
/// the classifier said (label, confidence — unthresholded) or the config
/// that produced it. Nothing here is a derived interpretation: no
/// precomputed "is this a real cough" boolean, no bout membership. Those
/// are always computed live by `DetectionAnalysis` over whatever tunable
/// parameters are currently set — see that file for why.
@Model
public final class DetectionEvent {
    public var id: UUID = UUID()
    public var sessionID: UUID = UUID()
    public var timestamp: Date = Date()
    public var label: String = ""
    public var confidence: Double = 0
    public var windowDuration: TimeInterval = 0
    public var overlapFactor: Double = 0
    public var classifierIdentifier: String = ""
    public var appVersion: String = ""
    public var isFalsePositive: Bool = false

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        label: String,
        confidence: Double,
        config: DetectionConfig,
        isFalsePositive: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.label = label
        self.confidence = confidence
        self.windowDuration = config.windowDuration
        self.overlapFactor = config.overlapFactor
        self.classifierIdentifier = config.classifierIdentifier
        self.appVersion = config.appVersion
        self.isFalsePositive = isFalsePositive
    }
}
