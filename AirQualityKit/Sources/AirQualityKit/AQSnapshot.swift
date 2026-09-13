import Foundation

/// The single cached "current reading" shared between the main app and the
/// widget extension via the App Group — also the app's own hourly cache, so
/// a fetch within the last hour reuses this instead of hitting the network.
public struct AQSnapshot: Codable, Sendable, Equatable {
    public let aqi: Int
    public let dominantPollutant: String?
    /// nil means unavailable, which is different from a measured zero.
    public let pollenIndex: Int?
    public let locationName: String
    public let lastUpdated: Date
    /// Absent in legacy snapshots; they remain displayable but cannot satisfy a location-specific cache lookup.
    public let coordinate: GeoCoordinate?

    public init(aqi: Int, dominantPollutant: String?, pollenIndex: Int?, locationName: String, lastUpdated: Date, coordinate: GeoCoordinate? = nil) {
        self.aqi = aqi
        self.dominantPollutant = dominantPollutant
        self.pollenIndex = pollenIndex
        self.locationName = locationName
        self.lastUpdated = lastUpdated
        self.coordinate = coordinate
    }

    public func isFresh(asOf date: Date = Date(), within interval: TimeInterval = 60 * 60) -> Bool {
        let age = date.timeIntervalSince(lastUpdated)
        return age >= 0 && age < interval
    }
}
