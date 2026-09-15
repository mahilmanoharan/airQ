import Foundation

/// The capture-time configuration that produced a `DetectionEvent`, so a
/// future parameter change doesn't create an invisible discontinuity in
/// longitudinal data.
public struct DetectionConfig: Sendable, Equatable {
    public let windowDuration: TimeInterval
    public let overlapFactor: Double
    public let classifierIdentifier: String
    public let appVersion: String

    public init(
        windowDuration: TimeInterval,
        overlapFactor: Double,
        classifierIdentifier: String,
        appVersion: String
    ) {
        self.windowDuration = windowDuration
        self.overlapFactor = overlapFactor
        self.classifierIdentifier = classifierIdentifier
        self.appVersion = appVersion
    }
}
