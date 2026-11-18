import Foundation

/// A queried location for filtering environmental records (RespiratoryKit doesn't depend on
/// AirQualityKit's coordinate type).
public struct RecordPlace: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    /// Records requested within this distance count as the same place for hourly history and the
    /// dashboard's recent chart: history is per queried location, and 10 km keeps home and work
    /// (usually) together without mixing cities.
    public static let sameAreaKilometres = 10.0

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle (haversine) distance in kilometres.
    public func kilometres(to other: RecordPlace) -> Double {
        let radians = Double.pi / 180
        let dLat = (other.latitude - latitude) * radians
        let dLon = (other.longitude - longitude) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * radians) * cos(other.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Whether a record requested at (`latitude`, `longitude`) belongs to this place. A record
    /// without a coordinate is never matched.
    public func contains(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else { return false }
        return kilometres(to: RecordPlace(latitude: latitude, longitude: longitude)) <= Self.sameAreaKilometres
    }
}
