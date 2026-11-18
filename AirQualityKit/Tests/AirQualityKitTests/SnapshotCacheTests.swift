import Foundation
import Testing
@testable import AirQualityKit

@Suite("Snapshot cache") @MainActor
struct SnapshotCacheTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "airQ.tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private let snapshot = AQSnapshot(aqi: 61, dominantPollutant: "o3", pollenIndex: 2, locationName: "Reno",
                                      lastUpdated: Date(timeIntervalSince1970: 1_000),
                                      coordinate: GeoCoordinate(latitude: 39.5, longitude: -119.8))

    @Test("A saved snapshot loads back unchanged; an empty cache is nil")
    func roundTrip() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = AppGroupSnapshotCache(defaults: defaults)
        #expect(try cache.load() == nil)
        try cache.save(snapshot)
        #expect(try cache.load() == snapshot)
    }

    @Test("Clearing removes the saved reading and its place")
    func clearing() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = AppGroupSnapshotCache(defaults: defaults)
        try cache.save(snapshot)
        cache.clear()
        #expect(try cache.load() == nil)
    }

    @Test("Unreadable data throws on load, and a missing container fails the save visibly")
    func failures() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("not json".utf8), forKey: WidgetDataStore.snapshotKey)
        #expect(throws: (any Error).self) { try AppGroupSnapshotCache(defaults: defaults).load() }
        #expect(throws: (any Error).self) { try AppGroupSnapshotCache(defaults: nil).save(snapshot) }
    }

    @Test("A snapshot with no coordinate (legacy) still round-trips")
    func legacy() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = AQSnapshot(aqi: 10, dominantPollutant: nil, pollenIndex: nil, locationName: "X",
                                lastUpdated: Date(timeIntervalSince1970: 5))
        let cache = AppGroupSnapshotCache(defaults: defaults)
        try cache.save(legacy)
        #expect(try cache.load()?.coordinate == nil)
    }
}
