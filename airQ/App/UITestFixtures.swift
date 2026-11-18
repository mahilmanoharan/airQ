#if DEBUG
import Foundation
import AirQualityKit

/// Deterministic inputs for `-uiTestMode`: a fixed location and a fresh cached reading, so UI
/// tests never depend on the simulator's real data or location, and no provider is contacted
/// (a fresh same-place cache means the dashboard doesn't fetch).
enum UITestFixtures {
    static let coordinate = GeoCoordinate(latitude: 37.79, longitude: -122.41)

    static func snapshot(now: Date = Date()) -> AQSnapshot {
        let defaults = UserDefaults.standard
        let aqi = Int(defaults.string(forKey: "uiTestAQI") ?? "") ?? 42
        let hasPollen = !defaults.bool(forKey: "uiTestNoPollen")
        let updated = defaults.bool(forKey: "uiTestStaleReading") ? now.addingTimeInterval(-7_200) : now
        let today = DayKey.local(now)
        let tomorrow = DayKey.local(now.addingTimeInterval(86_400))
        return AQSnapshot(
            aqi: aqi, dominantPollutant: "pm25", pollenIndex: hasPollen ? 2 : nil, locationName: "San Francisco",
            lastUpdated: updated, coordinate: coordinate, pollenFetchedAt: hasPollen ? now : nil,
            pollenTypes: !hasPollen ? nil : PollenReading(grassIndex: 1, treeIndex: 2, weedIndex: nil,
                                       plants: [PollenPlant(code: "OAK", name: "Oak", index: 2, inSeason: true)],
                                       outlook: [.init(grassIndex: 1, treeIndex: 3, weedIndex: nil)], firstDayKey: today),
            conditions: StationConditions(subIndices: ["pm25": Double(aqi), "o3": 21, "no2": 4, "co": 5, "t": 18, "h": 70, "w": 3, "wg": 8, "p": 1013]),
            forecast: [.init(day: today, pollutants: ["pm25": .init(min: 20, average: 35, max: 51)], uvIndex: .init(min: 0, average: 2, max: 6)),
                       .init(day: tomorrow, pollutants: ["pm25": .init(min: 20, average: 40, max: 68)], uvIndex: nil)],
            attributions: [DataAttribution(name: "Test Station Agency", url: nil)],
            station: StationInfo(name: "Test Station", coordinate: GeoCoordinate(latitude: 37.765, longitude: -122.40),
                                 observedAt: now.addingTimeInterval(-1_800)))
    }
}

@MainActor
final class UITestLocation: LocationProviding {
    /// `-uiTestLocationDenied YES` simulates denied location access.
    func currentCoordinate() async throws -> GeoCoordinate {
        if UserDefaults.standard.bool(forKey: "uiTestLocationDenied") { throw LocationError.denied }
        return UITestFixtures.coordinate
    }
    func cityName(for coordinate: GeoCoordinate) async -> String? { "San Francisco" }
}

@MainActor
final class UITestSnapshotCache: SnapshotCaching {
    private var stored: AQSnapshot? = UserDefaults.standard.bool(forKey: "uiTestNoReading") ? nil : UITestFixtures.snapshot()
    func load() throws -> AQSnapshot? { stored }
    func save(_ snapshot: AQSnapshot) throws { stored = snapshot }
    func clear() { stored = nil }
}
#endif
