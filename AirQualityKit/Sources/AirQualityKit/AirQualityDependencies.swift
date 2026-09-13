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
        CLLocation(latitude: latitude, longitude: longitude).distance(
            from: CLLocation(latitude: other.latitude, longitude: other.longitude)
        ) <= meters
    }
}

public struct AirQualityReading: Sendable, Equatable {
    public let aqi: Int
    public let dominantPollutant: String?
    public let stationName: String

    public init(aqi: Int, dominantPollutant: String?, stationName: String) {
        self.aqi = aqi
        self.dominantPollutant = dominantPollutant
        self.stationName = stationName
    }
}

public protocol AirQualityFetching: Sendable {
    func airQuality(at coordinate: GeoCoordinate) async throws -> AirQualityReading
    func pollen(at coordinate: GeoCoordinate) async throws -> PollenReading
}

@MainActor
public protocol LocationProviding: AnyObject, Sendable {
    func currentCoordinate() async throws -> GeoCoordinate
    func cityName(for coordinate: GeoCoordinate) async -> String?
}

@MainActor
public protocol SnapshotCaching {
    func load() throws -> AQSnapshot?
    func save(_ snapshot: AQSnapshot) throws
}
