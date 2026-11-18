import Foundation
import Testing
@testable import AirQualityKit

@Suite("Air quality alerts")
struct AirQualityAlertTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 14:13 UTC
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
    private let air = AirQualityAlertSettings(airThreshold: 101)
    private let pollen = AirQualityAlertSettings(pollenThreshold: 3)

    private func snapshot(aqi: Int = 34, age: TimeInterval = 60, pollen: Int? = nil,
                          pollenAge: TimeInterval? = 3_600) -> AQSnapshot {
        AQSnapshot(aqi: aqi, dominantPollutant: "o3", pollenIndex: pollen, locationName: "Fresno",
                   lastUpdated: now.addingTimeInterval(-age),
                   pollenFetchedAt: pollenAge.map { now.addingTimeInterval(-$0) })
    }

    private func alerts(_ snapshot: AQSnapshot?, _ settings: AirQualityAlertSettings,
                        last: [AirQualityAlertKind: Date] = [:]) -> [AirQualityAlertContent] {
        AirQualityAlertPolicy.alerts(for: snapshot, settings: settings, lastAlertAt: last, now: now, calendar: utc)
    }

    @Test("Nothing is sent overnight (22:00 to 07:00 on the device's clock); the first run from 07:00 sends it")
    func quietHours() throws {
        var fresno = Calendar(identifier: .gregorian)
        fresno.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        func alerts(at local: DateComponents) throws -> [AirQualityAlertContent] {
            let at = try #require(fresno.date(from: local))
            let reading = AQSnapshot(aqi: 160, dominantPollutant: nil, pollenIndex: 4, locationName: "Fresno",
                                     lastUpdated: at.addingTimeInterval(-60), pollenFetchedAt: at.addingTimeInterval(-60))
            return AirQualityAlertPolicy.alerts(for: reading, settings: .init(airThreshold: 101, pollenThreshold: 3),
                                                lastAlertAt: [:], now: at, calendar: fresno)
        }
        func day(_ hour: Int, _ minute: Int = 0) -> DateComponents {
            DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute)
        }
        #expect(try alerts(at: day(21, 59)).count == 2)
        #expect(try alerts(at: day(22)).isEmpty)
        #expect(try alerts(at: day(2, 30)).isEmpty)
        #expect(try alerts(at: day(6, 59)).isEmpty)
        #expect(try alerts(at: day(7)).count == 2)
    }

    @Test("A current reading at or above the AQI threshold alerts, naming place, category and pollutant")
    func airAlert() throws {
        let content = try #require(alerts(snapshot(aqi: 112), air).first)
        #expect(content.kind == .air)
        #expect(content.body.hasPrefix("AQI 112 in Fresno: Unhealthy for Sensitive Groups. Mainly ozone."))
        #expect(alerts(snapshot(aqi: 101), air).count == 1)
        #expect(alerts(snapshot(aqi: 100), air).isEmpty)
    }

    @Test("Pollen alerts at or above its threshold, only for a forecast requested today")
    func pollenAlert() throws {
        let content = try #require(alerts(snapshot(pollen: 4), pollen).first)
        #expect(content.kind == .pollen)
        #expect(content.body.hasPrefix("Pollen is high in Fresno."))
        #expect(alerts(snapshot(pollen: 3), pollen).count == 1)
        #expect(alerts(snapshot(pollen: 2), pollen).isEmpty)
        // Unavailable is not a level, and yesterday's forecast is not today's.
        #expect(alerts(snapshot(pollen: nil), pollen).isEmpty)
        #expect(alerts(snapshot(pollen: 5, pollenAge: 30 * 3_600), pollen).isEmpty)
        #expect(alerts(snapshot(pollen: 5, pollenAge: nil), pollen).isEmpty)
    }

    @Test("The two kinds are independent and can both fire")
    func both() {
        let both = AirQualityAlertSettings(airThreshold: 51, pollenThreshold: 2)
        #expect(Set(alerts(snapshot(aqi: 80, pollen: 3), both).map(\.kind)) == [.air, .pollen])
        #expect(alerts(snapshot(aqi: 80, pollen: 3), both, last: [.air: now.addingTimeInterval(-60)]).map(\.kind) == [.pollen])
    }

    @Test("Nothing is sent when off, without a reading, or for an old air reading")
    func silent() {
        #expect(alerts(snapshot(aqi: 200, pollen: 5), .init()).isEmpty)
        #expect(alerts(nil, air).isEmpty)
        #expect(alerts(snapshot(aqi: 200, age: 2 * 3_600), air).isEmpty)
    }

    @Test("At most one alert per kind per local day")
    func oncePerDay() {
        #expect(alerts(snapshot(aqi: 150), air, last: [.air: now.addingTimeInterval(-3_600 * 2)]).isEmpty)
        #expect(alerts(snapshot(aqi: 150), air, last: [.air: now.addingTimeInterval(-3_600 * 30)]).count == 1)
    }

    @Test("The once-a-day rule follows the local day, not UTC: same UTC day but a new local day fires again")
    func localDayNotUTC() {
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland") ?? .gmt
        // `morning` is 08:13 on the 22nd in Auckland (UTC+12, outside quiet hours); nine hours earlier is
        // 23:13 on the 21st there, yet the same UTC day, so a UTC calendar would wrongly suppress the alert.
        let morning = now.addingTimeInterval(6 * 3_600)
        let earlier = morning.addingTimeInterval(-9 * 3_600)
        let sameUTCDay = utc.isDate(earlier, inSameDayAs: morning)
        let reading = AQSnapshot(aqi: 150, dominantPollutant: nil, pollenIndex: nil, locationName: "Auckland",
                                 lastUpdated: morning.addingTimeInterval(-60))
        let fired = AirQualityAlertPolicy.alerts(for: reading, settings: air, lastAlertAt: [.air: earlier],
                                                 now: morning, calendar: auckland)
        #expect(sameUTCDay)
        #expect(fired.count == 1)
    }

    @Test("Settings round-trip, start off, and offer known defaults")
    func settings() throws {
        #expect(!AirQualityAlertSettings().isAnyEnabled)
        let data = try JSONEncoder().encode(AirQualityAlertSettings(airThreshold: 151, pollenThreshold: 4))
        let decoded = try JSONDecoder().decode(AirQualityAlertSettings.self, from: data)
        #expect(decoded.airThreshold == 151 && decoded.pollenThreshold == 4 && decoded.isAnyEnabled)
        #expect(AirQualityAlertSettings.airThresholds.contains(AirQualityAlertSettings.defaultAirThreshold))
        #expect(AirQualityAlertSettings.pollenThresholds.contains(AirQualityAlertSettings.defaultPollenThreshold))
    }
}
