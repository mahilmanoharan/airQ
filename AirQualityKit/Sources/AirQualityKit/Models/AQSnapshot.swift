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
    /// When Google Pollen last answered (with or without data; `pollenIndex` may be nil). Pollen is a
    /// daily forecast, so the answer is reused for the rest of that local day. Nil means no answer
    /// yet (never asked, network failure or skipped), and in snapshots written before build 3.
    public let pollenFetchedAt: Date?
    /// Per-type pollen behind `pollenIndex`. Absent in older snapshots.
    public let pollenTypes: PollenReading?
    /// The station's pollutant sub-indices and weather. Absent in older snapshots.
    public let conditions: StationConditions?
    /// WAQI's daily forecast as of `lastUpdated`. Absent in older snapshots.
    public let forecast: [AirQualityForecastDay]?
    /// WAQI's credited sources for this reading. Absent in older snapshots.
    public let attributions: [DataAttribution]?
    /// The WAQI station behind `aqi`. Absent in older snapshots.
    public let station: StationInfo?

    public init(aqi: Int, dominantPollutant: String?, pollenIndex: Int?, locationName: String, lastUpdated: Date,
                coordinate: GeoCoordinate? = nil, pollenFetchedAt: Date? = nil,
                pollenTypes: PollenReading? = nil, conditions: StationConditions? = nil,
                forecast: [AirQualityForecastDay]? = nil, attributions: [DataAttribution]? = nil,
                station: StationInfo? = nil) {
        self.aqi = aqi
        self.dominantPollutant = dominantPollutant
        self.pollenIndex = pollenIndex
        self.locationName = locationName
        self.lastUpdated = lastUpdated
        self.coordinate = coordinate
        self.pollenFetchedAt = pollenFetchedAt
        self.pollenTypes = pollenTypes
        self.conditions = conditions
        self.forecast = forecast
        self.attributions = attributions
        self.station = station
    }

    /// A reading at least this old is called out as old (widgets, Siri/Share text, station age).
    /// The app refreshes only when opened, so readings can age a lot.
    /// How long a reading is reused without a new request.
    public static let freshFor: TimeInterval = 60 * 60
    public static let staleAfter: TimeInterval = 3 * 60 * 60

    public func isFresh(asOf date: Date = Date(), within interval: TimeInterval = freshFor) -> Bool {
        let age = date.timeIntervalSince(lastUpdated)
        return age >= 0 && age < interval
    }
}
