import CoreLocation
import Foundation

/// A value suitable for request identity, cache validation, and actor boundaries.
public struct GeoCoordinate: Codable, Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public func isNear(_ other: GeoCoordinate, within meters: Double = 1_000) -> Bool {
        distance(to: other) <= meters
    }

    /// Great-circle distance in metres.
    public func distance(to other: GeoCoordinate) -> Double {
        CLLocation(latitude: latitude, longitude: longitude).distance(
            from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// Two decimals is roughly 1 km, coarser than any station or pollen grid a provider serves.
    public func rounded(toDecimals decimals: Int) -> GeoCoordinate {
        let scale = pow(10, Double(decimals))
        return GeoCoordinate(latitude: (latitude * scale).rounded() / scale,
                             longitude: (longitude * scale).rounded() / scale)
    }
}

public struct AirQualityReading: Sendable, Equatable {
    public let aqi: Int
    public let dominantPollutant: String?
    public let stationName: String
    /// The station's current `iaqi` values (pollutant sub-indices and weather), keyed by WAQI code.
    public let subIndices: [String: Double]
    /// WAQI's daily forecast, oldest first (it includes a few past days).
    public let forecast: [AirQualityForecastDay]
    /// The station's credited sources, in WAQI's order.
    public let attributions: [DataAttribution]
    /// Station coordinate and observation time, when WAQI reported them.
    public let station: StationInfo?

    public init(aqi: Int, dominantPollutant: String?, stationName: String, subIndices: [String: Double] = [:],
                forecast: [AirQualityForecastDay] = [], attributions: [DataAttribution] = [],
                station: StationInfo? = nil) {
        self.aqi = aqi
        self.dominantPollutant = dominantPollutant
        self.stationName = stationName
        self.subIndices = subIndices
        self.forecast = forecast
        self.attributions = attributions
        self.station = station
    }
}

public struct AirQualityHistoryPage: Sendable, Equatable {
    public let hours: [AirQualityHour]
    public let nextPageToken: String?

    public init(hours: [AirQualityHour], nextPageToken: String?) {
        self.hours = hours
        self.nextPageToken = nextPageToken
    }
}
