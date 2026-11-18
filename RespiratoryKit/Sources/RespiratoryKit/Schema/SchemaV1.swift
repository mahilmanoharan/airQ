import Foundation
import SwiftData

/// The original schema shipped unversioned in builds 1–2, frozen so an existing store opens as V1.
/// Never edit these models; add a new schema version instead.
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [DetectionEvent.self] }

    /// A single raw classifier observation (capture semantics 1: the top-ranked label of a window,
    /// persisted only when allowlisted, unthresholded). Nothing here is a derived interpretation.
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
}
