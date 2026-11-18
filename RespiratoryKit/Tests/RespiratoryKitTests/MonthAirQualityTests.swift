import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Month air quality") @MainActor
struct MonthAirQualityTests {
    private let la = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private func point(_ iso: String, _ value: Int) throws -> EnvironmentSeries.AQIPoint {
        .init(date: try Date(iso, strategy: .iso8601), value: value, source: "usa_epa")
    }
    /// `count` consecutive hours starting at local midnight of `day` (Sep `day`, 2026, PDT).
    private func hours(day: Int, count: Int, peakAt: Int = 3, peak: Int = 80, base: Int = 30) throws -> [EnvironmentSeries.AQIPoint] {
        let start = try Date("2026-09-\(String(format: "%02d", day))T07:00:00Z", strategy: .iso8601)  // 00:00 PDT
        return (0..<count).map { .init(date: start.addingTimeInterval(Double($0) * 3_600), value: $0 == peakAt ? peak : base, source: "usa_epa") }
    }

    @Test("Each full day reports its highest hour; a day with too few hours is counted, not shown")
    func peaksAndPartialDays() throws {
        let series = try hours(day: 10, count: 24, peak: 120) + hours(day: 11, count: 18, peak: 70) + hours(day: 12, count: 5, peak: 200)
        let result = DailyPeaks.compute(hourly: series, timeZone: la)
        #expect(result.days.map(\.dayKey) == ["2026-09-10", "2026-09-11"])
        #expect(result.days.map(\.peak) == [120, 70])
        #expect(result.days.map(\.hours) == [24, 18])
        #expect(result.partialDays == 1)  // the 5-hour day with a 200 peak is not reported
    }

    @Test("Days follow the local calendar, so late-evening hours belong to that local day")
    func localDays() throws {
        // 23:00 PDT on Sep 10 is 06:00 UTC on Sep 11; it must count toward Sep 10, not Sep 11.
        let series = try hours(day: 10, count: 24, peak: 50) + [try point("2026-09-11T06:30:00Z", 300)]
        let result = DailyPeaks.compute(hourly: series, timeZone: la)
        #expect(result.days.count == 1 && result.days[0].dayKey == "2026-09-10" && result.days[0].peak == 300)
    }

    @Test("A repeated hour is counted once, keeping the higher value")
    func duplicateHours() throws {
        var series = try hours(day: 10, count: 18)
        series.append(series[0])
        series.append(try point("2026-09-10T07:00:00Z", 150))
        let result = DailyPeaks.compute(hourly: series, timeZone: la)
        #expect(result.days.first?.hours == 18 && result.days.first?.peak == 150)
    }

    @Test("The view model loads the last 30 local days and reports storage errors")
    func viewModel() async throws {
        let now = try Date("2026-09-28T19:00:00Z", strategy: .iso8601)
        let stub = MonthStub(series: EnvironmentSeries(waqi: [], hourly: try hours(day: 20, count: 24), pollen: [], successDayKeys: []))
        let model = MonthAirQualityViewModel(records: stub, place: nil, timeZone: la, now: { now })
        await model.load()
        #expect(model.hasLoaded && model.days.count == 1 && model.errorMessage == nil)
        let requested = try #require(await stub.requested.first)
        #expect(la.identifier == "America/Los_Angeles")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = la
        let parts = calendar.dateComponents([.month, .day, .hour], from: requested.start)
        #expect(parts.month == 8 && parts.day == 29 && parts.hour == 0)  // 30 whole days before today (Sep 28)
        let endParts = calendar.dateComponents([.month, .day, .hour], from: requested.end)
        #expect(endParts.month == 9 && endParts.day == 28 && endParts.hour == 0, "today is excluded")

        let failing = MonthAirQualityViewModel(records: MonthStub(fails: true), place: nil, timeZone: la, now: { now })
        await failing.load()
        #expect(failing.errorMessage != nil && !failing.hasLoaded)
    }
}

private actor MonthStub: EnvironmentSeriesReading {
    struct Failure: Error {}
    let series: EnvironmentSeries
    let fails: Bool
    var requested: [DateInterval] = []
    init(series: EnvironmentSeries = .init(waqi: [], hourly: [], pollen: [], successDayKeys: []), fails: Bool = false) {
        self.series = series
        self.fails = fails
    }
    func environmentSeries(in interval: DateInterval, near place: RecordPlace?) async throws -> EnvironmentSeries {
        requested.append(interval)
        if fails { throw Failure() }
        return series
    }
}
