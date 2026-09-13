import Foundation
import Testing
@testable import AirQualityKit

@Suite("Snapshot freshness")
struct AQSnapshotTests {
    @Test("Existing widget snapshots decode without the new coordinate field")
    func legacySnapshot() throws {
        let data = Data(#"{"aqi":42,"pollenIndex":2,"locationName":"Legacy","lastUpdated":1000}"#.utf8)
        let snapshot = try JSONDecoder().decode(AQSnapshot.self, from: data)
        #expect(snapshot.coordinate == nil)
        #expect(snapshot.pollenIndex == 2)
    }

    @Test("Unavailable pollen survives a cache round trip")
    func unavailablePollenRoundTrip() throws {
        let snapshot = AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: nil,
                                  locationName: "Test", lastUpdated: .now,
                                  coordinate: GeoCoordinate(latitude: 40, longitude: -74))
        let decoded = try JSONDecoder().decode(AQSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test("Future-dated readings must not be reused as fresh")
    func rejectsFutureDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: 2,
                                  locationName: "Test", lastUpdated: now.addingTimeInterval(1))
        #expect(!snapshot.isFresh(asOf: now))
    }

    @Test("An expired reading is stale at the exact boundary")
    func expirationBoundary() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let snapshot = AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: 2,
                                  locationName: "Test", lastUpdated: timestamp)
        #expect(snapshot.isFresh(asOf: timestamp.addingTimeInterval(3_599)))
        #expect(!snapshot.isFresh(asOf: timestamp.addingTimeInterval(3_600)))
    }
}
