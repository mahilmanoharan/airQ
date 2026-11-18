import Foundation
import Testing
@testable import AirQualityKit

@Suite("Station conditions")
struct StationConditionsTests {
    @Test("Pollutants are ordered particulates first and weather is split out")
    func splitsPollutantsAndWeather() {
        let conditions = StationConditions(subIndices: [
            "no2": 8.4, "pm10": 20, "pm25": 55.5, "t": 18.5, "h": 60, "p": 1013, "w": 3.2, "dew": 9, "wg": 7,
        ])
        #expect(conditions.pollutants.map(\.code) == ["pm25", "pm10", "no2"])
        #expect(conditions.pollutants.map(\.subIndex) == [56, 20, 8])
        #expect(conditions.pollutants.first?.displayName == "PM2.5")
        #expect(conditions.temperatureCelsius == 18.5)
        #expect(conditions.humidityPercent == 60)
        #expect(conditions.pressureHectopascals == 1013)
        #expect(conditions.windMetersPerSecond == 3.2)
        #expect(conditions.dewPointCelsius == 9)
        #expect(conditions.windGustMetersPerSecond == 7)
        #expect(conditions.hasWeather)
    }

    @Test("Unknown, negative and non-finite pollutant values are dropped")
    func dropsInvalidValues() {
        let conditions = StationConditions(subIndices: ["pm25": -1, "o3": .nan, "xyz": 5])
        #expect(conditions.pollutants.isEmpty)
        #expect(!conditions.hasWeather)
        #expect(conditions.isEmpty)
        #expect(StationConditions(subIndices: ["dew": 9]).hasWeather)
        #expect(StationConditions(subIndices: ["wg": 9]).hasWeather)
    }

    @Test("WAQI's station coordinate and observation time are kept, with distance and age derived")
    func stationInfo() throws {
        let body = #"{"status":"ok","data":{"aqi":34,"city":{"name":"Downtown","geo":[37.78,-122.41]},"time":{"iso":"2026-09-28T08:00:00-07:00"}}}"#
        guard case .reading(let reading, _) = try HTTPAirQualityClient.parseWAQI(Data(body.utf8)) else {
            Issue.record("expected a reading")
            return
        }
        let station = try #require(reading.station)
        #expect(station.name == "Downtown")
        #expect(station.observedAt == Date(timeIntervalSince1970: 1_790_607_600))
        let distance = try #require(station.distance(from: GeoCoordinate(latitude: 37.79, longitude: -122.41)))
        #expect((1_000...1_200).contains(distance))
        #expect(station.distance(from: nil) == nil)
        #expect(station.observationAge(at: Date(timeIntervalSince1970: 1_790_607_600 + 600)) == 600)
        #expect(station.observationAge(at: Date(timeIntervalSince1970: 1_790_607_600 - 600)) == nil)
    }

    @Test("An unparseable observation time and missing geo leave those fields nil")
    func stationInfoMissing() throws {
        let body = #"{"status":"ok","data":{"aqi":34,"city":{"name":"X","geo":[1]},"time":{"iso":"yesterday"}}}"#
        guard case .reading(let reading, _) = try HTTPAirQualityClient.parseWAQI(Data(body.utf8)) else {
            Issue.record("expected a reading")
            return
        }
        #expect(reading.station?.coordinate == nil && reading.station?.observedAt == nil)
    }
}
