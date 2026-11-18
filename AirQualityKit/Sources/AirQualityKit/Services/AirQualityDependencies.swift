import CoreLocation
import Foundation

/// Implementations throw `ProviderFailure` for failed attempts, so every attempt can be recorded.
public protocol AirQualityFetching: Sendable {
    func airQuality(at coordinate: GeoCoordinate) async throws -> Fetched<AirQualityReading>
    func pollen(at coordinate: GeoCoordinate) async throws -> Fetched<PollenReading>
}

public protocol AirQualityHistoryFetching: Sendable {
    /// The most recent `hours` completed hours (1...720), newest first, one page at a time.
    func airQualityHistory(at coordinate: GeoCoordinate, hours: Int,
                           pageToken: String?, pageIndex: Int) async throws -> Fetched<AirQualityHistoryPage>
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
