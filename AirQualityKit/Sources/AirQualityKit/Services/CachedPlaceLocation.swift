import Foundation

/// The place of the last cached reading, for refreshes that run without the user (background app
/// refresh). It never asks CoreLocation, so a refresh keeps the widgets current for the last place
/// the app knew; opening the app re-locates as usual.
@MainActor
public final class CachedPlaceLocation: LocationProviding {
    public enum Failure: LocalizedError, Equatable {
        case noKnownPlace

        public var errorDescription: String? { "airQ has no known place yet. Open airQ once to set it." }
    }

    private let cache: any SnapshotCaching

    public init(cache: any SnapshotCaching) { self.cache = cache }

    public func currentCoordinate() async throws -> GeoCoordinate {
        guard let coordinate = (try? cache.load())?.coordinate else { throw Failure.noKnownPlace }
        return coordinate
    }

    /// The cached name for that place, so a refresh needs no geocoding request.
    public func cityName(for coordinate: GeoCoordinate) async -> String? {
        guard let snapshot = try? cache.load(), snapshot.coordinate?.isNear(coordinate) == true else { return nil }
        return snapshot.locationName
    }
}
