import Foundation

/// The single cached "current reading" shared between the main app and the
/// widget extension via the App Group — also the app's own hourly cache, so
/// a fetch within the last hour reuses this instead of hitting the network.
public struct AQSnapshot: Codable, Sendable, Equatable {
    public let aqi: Int
    public let dominantPollutant: String?
    public let pollenIndex: Int
    public let locationName: String
    public let lastUpdated: Date

    public init(aqi: Int, dominantPollutant: String?, pollenIndex: Int, locationName: String, lastUpdated: Date) {
        self.aqi = aqi
        self.dominantPollutant = dominantPollutant
        self.pollenIndex = pollenIndex
        self.locationName = locationName
        self.lastUpdated = lastUpdated
    }

    public func isFresh(asOf date: Date = Date(), within interval: TimeInterval = 60 * 60) -> Bool {
        date.timeIntervalSince(lastUpdated) < interval
    }
}
