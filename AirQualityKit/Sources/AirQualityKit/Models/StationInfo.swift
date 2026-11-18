import Foundation

/// Where and when WAQI's reading was measured. The station can be kilometres from the device and
/// its latest value can be hours old, so both are shown next to the reading.
public struct StationInfo: Codable, Sendable, Equatable {
    public let name: String
    public let coordinate: GeoCoordinate?
    /// The station's own observation time (WAQI `time.iso`), nil when it didn't parse.
    public let observedAt: Date?

    public init(name: String, coordinate: GeoCoordinate?, observedAt: Date?) {
        self.name = name
        self.coordinate = coordinate
        self.observedAt = observedAt
    }

    /// Beyond this, the reading is flagged as an older observation.
    public static var staleObservationAge: TimeInterval { AQSnapshot.staleAfter }

    /// Metres from `point` to the station, or nil without a station coordinate.
    public func distance(from point: GeoCoordinate?) -> Double? {
        guard let point, let coordinate else { return nil }
        return point.distance(to: coordinate)
    }

    /// How old the observation was when it was fetched; nil if unknown or dated in the future.
    public func observationAge(at fetchedAt: Date) -> TimeInterval? {
        guard let observedAt else { return nil }
        let age = fetchedAt.timeIntervalSince(observedAt)
        return age >= 0 ? age : nil
    }
}
