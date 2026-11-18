import Foundation
import Testing
@testable import AirQualityKit

@Suite("WAQI daily forecast")
struct AirQualityForecastTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func reading(_ body: String) throws -> AirQualityReading {
        guard case .reading(let reading, _) = try HTTPAirQualityClient.parseWAQI(Data(body.utf8)) else {
            Issue.record("expected a reading")
            throw CancellationError()
        }
        return reading
    }

    @Test("Per-pollutant arrays are grouped into days with UV alongside")
    func groupsDays() throws {
        let body = #"{"status":"ok","data":{"aqi":34,"forecast":{"daily":{"#
            + #""pm25":[{"avg":36,"day":"2026-09-28","max":51,"min":32},{"avg":33,"day":"2026-09-29","max":68,"min":22}],"#
            + #""pm10":[{"avg":13,"day":"2026-09-28","max":18,"min":12}],"#
            + #""uvi":[{"avg":1,"day":"2026-09-29","max":7,"min":0}],"#
            + #""xyz":[{"avg":1,"day":"2026-09-29","max":2,"min":0}]}}}}"#
        let forecast = try reading(body).forecast
        #expect(forecast.map(\.day) == ["2026-09-28", "2026-09-29"])
        #expect(forecast[0].pollutants["pm25"] == .init(min: 32, average: 36, max: 51))
        #expect(forecast[0].pollutants["pm10"]?.max == 18)
        #expect(forecast[0].uvIndex == nil)
        #expect(forecast[1].uvIndex?.max == 7)
        #expect(forecast[1].pollutants.keys.sorted() == ["pm25"])
        #expect(forecast[1].peak?.code == "pm25" && forecast[1].peak?.subIndex == 68)
    }

    @Test("A malformed forecast is dropped without losing the current reading")
    func malformedForecast() throws {
        let body = #"{"status":"ok","data":{"aqi":34,"forecast":{"daily":"oops"}}}"#
        let current = try reading(body)
        #expect(current.aqi == 34)
        #expect(current.forecast.isEmpty)

        let partial = #"{"status":"ok","data":{"aqi":34,"forecast":{"daily":{"pm25":[{"day":"2026-09-28","max":"-"},{"avg":1,"day":"2026-09-29","max":2,"min":0}]}}}}"#
        #expect(try reading(partial).forecast.map(\.day) == ["2026-09-29"])
    }

    @Test("Attributions are kept in order, deduplicated, with only http(s) links")
    func attributions() throws {
        let body = #"{"status":"ok","data":{"aqi":34,"attributions":["#
            + #"{"url":"http://www.airnow.gov/","name":"Air Now - US EPA"},"#
            + #"{"url":"javascript:alert(1)","name":"Odd"},{"name":"Air Now - US EPA"},{"name":" "},"#
            + #"{"url":"https://waqi.info/","name":"World Air Quality Index Project"}]}}"#
        let credits = try reading(body).attributions
        #expect(credits.map(\.name) == ["Air Now - US EPA", "Odd", "World Air Quality Index Project"])
        #expect(credits[0].url?.absoluteString == "http://www.airnow.gov/")
        #expect(credits[1].url == nil)

        let malformed = #"{"status":"ok","data":{"aqi":34,"attributions":"none"}}"#
        #expect(try reading(malformed).attributions.isEmpty)
    }

    @Test("Upcoming keeps today and later, in order, up to the limit")
    func upcoming() {
        let days = ["2026-09-30", "2026-09-26", "2026-09-28", "2026-09-27", "2026-09-29"].map {
            AirQualityForecastDay(day: $0, pollutants: [:], uvIndex: nil)
        }
        let now = Date(timeIntervalSince1970: 1_790_582_400)  // 2026-09-28 15:00 UTC
        #expect(AirQualityForecastDay.upcoming(days, asOf: now, calendar: utc).map(\.day)
                == ["2026-09-28", "2026-09-29", "2026-09-30"])
        #expect(AirQualityForecastDay.upcoming(days, asOf: now, calendar: utc, limit: 1).map(\.day) == ["2026-09-28"])
    }

    @Test("Day labels are relative to the given date, not the render time")
    func dayLabels() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 1_790_582_400)  // Monday 2026-09-28 15:00 UTC
        let english = Locale(identifier: "en_US")
        #expect(DayKey.label("2026-09-28", relativeTo: now, calendar: utc, locale: english) == "Today")
        #expect(DayKey.label("2026-09-29", relativeTo: now, calendar: utc, locale: english) == "Tomorrow")
        #expect(DayKey.label("2026-09-30", relativeTo: now, calendar: utc, locale: english) == "Wed")
        #expect(DayKey.label("2026-09-28", relativeTo: now.addingTimeInterval(86_400), calendar: utc, locale: english) == "Mon")
        #expect(DayKey.label("bad", relativeTo: now, calendar: utc) == "bad")
    }

    @Test("Peak ties resolve in pollutant display order; a day without pollutants has no peak")
    func peakTies() {
        let day = AirQualityForecastDay(day: "2026-09-28", pollutants: [
            "o3": .init(min: 1, average: 2, max: 40), "pm25": .init(min: 1, average: 2, max: 40),
        ], uvIndex: nil)
        #expect(day.peak?.code == "pm25")
        #expect(AirQualityForecastDay(day: "2026-09-28", pollutants: [:], uvIndex: nil).peak == nil)
        #expect(day.date(in: utc).map { utc.component(.day, from: $0) } == 28)
    }
}
