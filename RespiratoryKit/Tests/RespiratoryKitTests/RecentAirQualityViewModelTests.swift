import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Recent air quality") @MainActor
struct RecentAirQualityViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 14:13:20 UTC

    @Test("The window covers whole hours and ends at the start of the next hour")
    func window() {
        let window = RecentAirQualityViewModel.window(endingAt: now, hours: 48)
        #expect(window.end == Date(timeIntervalSince1970: 1_790_002_800))  // 15:00 UTC
        #expect(window.duration == 48 * 3_600)
        #expect(window.contains(now))
    }

    @Test("Loading keeps the hourly and station series apart and reports their range")
    func loads() async {
        let window = RecentAirQualityViewModel.window(endingAt: now, hours: 48)
        let records = StubSeries(series: EnvironmentSeries(
            waqi: [.init(date: now, value: 61, source: "waqi"),
                   // A station observation time outside the window (a stale station) is dropped.
                   .init(date: window.start.addingTimeInterval(-60), value: 99, source: "waqi")],
            hourly: [.init(date: window.start, value: 20, source: "usa_epa"),
                     .init(date: window.start.addingTimeInterval(3_600), value: 35, source: "usa_epa")],
            pollen: [], successDayKeys: []))
        let model = RecentAirQualityViewModel(records: records, place: nil, now: { [now] in now })
        await model.load()
        #expect(model.hourly.map(\.value) == [20, 35])
        #expect(model.station.map(\.value) == [61])
        #expect(model.valueRange == 20...61)
        #expect(model.hasLoaded && !model.isEmpty && model.errorMessage == nil)
        #expect(await records.requested == [window])
    }

    @Test("A touched time picks the nearest hourly point within 30 min and station reading within 90 min")
    func nearestValues() async {
        let window = RecentAirQualityViewModel.window(endingAt: now, hours: 48)
        let hour = window.start.addingTimeInterval(10 * 3_600)
        let records = StubSeries(series: EnvironmentSeries(
            waqi: [.init(date: hour.addingTimeInterval(80 * 60), value: 61, source: "waqi")],
            hourly: [.init(date: hour, value: 20, source: "usa_epa"),
                     .init(date: hour.addingTimeInterval(3_600), value: 35, source: "usa_epa")],
            pollen: [], successDayKeys: []))
        let model = RecentAirQualityViewModel(records: records, place: nil, now: { [now] in now })
        await model.load()
        let near = model.values(near: hour.addingTimeInterval(20 * 60))
        #expect(near.hourly?.value == 20 && near.station?.value == 61)
        let later = model.values(near: hour.addingTimeInterval(40 * 60))
        #expect(later.hourly?.value == 35)
        let far = model.values(near: hour.addingTimeInterval(-3 * 3_600))
        #expect(far.hourly == nil && far.station == nil)
    }

    @Test("Hourly points split into runs at a missing hour")
    func hourlyRuns() async {
        let window = RecentAirQualityViewModel.window(endingAt: now, hours: 48)
        let hours = [0, 1, 2, 5, 6].map { window.start.addingTimeInterval(Double($0) * 3_600) }
        let records = StubSeries(series: EnvironmentSeries(
            waqi: [], hourly: hours.map { .init(date: $0, value: 10, source: "usa_epa") }, pollen: [], successDayKeys: []))
        let model = RecentAirQualityViewModel(records: records, place: nil, now: { [now] in now })
        await model.load()
        #expect(model.hourlyRuns.map(\.count) == [3, 2])
    }

    @Test("Nothing stored is an empty, loaded state; a storage error is shown")
    func emptyAndError() async {
        let empty = RecentAirQualityViewModel(records: StubSeries(), place: nil, now: { [now] in now })
        await empty.load()
        #expect(empty.hasLoaded && empty.isEmpty && empty.valueRange == nil)

        let failing = RecentAirQualityViewModel(records: StubSeries(fails: true), place: nil, now: { [now] in now })
        await failing.load()
        #expect(failing.errorMessage != nil && !failing.hasLoaded)
    }
}

private actor StubSeries: EnvironmentSeriesReading {
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
