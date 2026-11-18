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
        #expect(snapshot.pollenFetchedAt == nil)
        #expect(snapshot.pollenTypes == nil && snapshot.conditions == nil)
    }

    @Test("Station conditions cached before wind gusts existed still decode")
    func legacyConditions() throws {
        let json = #"{"pollutants":[{"code":"pm25","subIndex":42}],"temperatureCelsius":18}"#
        let conditions = try JSONDecoder().decode(StationConditions.self, from: Data(json.utf8))
        #expect(conditions.windGustMetersPerSecond == nil && conditions.temperatureCelsius == 18)
    }

    @Test("Pollen types and station conditions survive a cache round trip")
    func conditionsRoundTrip() throws {
        let snapshot = AQSnapshot(aqi: 42, dominantPollutant: "pm25", pollenIndex: 3, locationName: "Test",
                                  lastUpdated: Date(timeIntervalSince1970: 1_000),
                                  pollenTypes: PollenReading(grassIndex: nil, treeIndex: 3, weedIndex: 0),
                                  conditions: StationConditions(subIndices: ["pm25": 42, "t": 18.5]))
        let decoded = try JSONDecoder().decode(AQSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.pollenTypes?.grassIndex == nil)
        #expect(decoded.pollenTypes?.overallIndex == 3)
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
