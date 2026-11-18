import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Settled history hours")
struct SettledHoursTests {
    private let provider = "googleAirQuality"
    /// 2026-09-28 06:00 UTC, an hour boundary.
    private let requestHour = Date(timeIntervalSince1970: 1_790_575_200)

    private func hour(_ offset: Int) -> Date { requestHour.addingTimeInterval(Double(offset) * 3_600) }
    private let sanFrancisco = RecordPlace(latitude: 37.79, longitude: -122.41)
    private let oakland = RecordPlace(latitude: 37.80, longitude: -122.27)  // ~12 km: another area.

    /// Records one successful history page returning `returned` hour offsets (relative to the request hour).
    private func recordPage(_ store: RecordStore, pageIndex: Int, requestedHours: Int, returned: [Int],
                            nextPageToken: String?, at place: RecordPlace? = nil, value: Int? = nil) async throws {
        var attempt = EnvironmentalAttemptRecord(provider: provider, requestKind: "history",
                                                 requestedAt: requestHour.addingTimeInterval(120 + Double(pageIndex)),
                                                 timeZoneID: "UTC", status: .success, parserVersion: 1, appVersion: "t")
        attempt.requestParameters = #"{"hours":\#(requestedHours),"pageSize":168}"#
        attempt.pageIndex = pageIndex
        let where_ = place ?? sanFrancisco
        attempt.latitude = where_.latitude
        attempt.longitude = where_.longitude
        let token = nextPageToken.map { #","nextPageToken":"\#($0)""# } ?? ""
        attempt.rawResponse = Data(#"{"hoursInfo":[]\#(token)}"#.utf8)
        attempt.hours = returned.map {
            .init(hourStart: hour($0),
                  indexes: value.map { [.init(code: RecordStore.chartHourlyIndex, aqi: $0, category: nil, dominantPollutant: nil)] },
                  pollutants: nil)
        }
        try await store.record(attempt)
    }

    private var window: DateInterval { DateInterval(start: hour(-10), end: requestHour) }

    @Test("A gap inside a page's returned span is settled; unreturned hours outside any span are not")
    func interiorGap() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        // Newest-first page covering -5...-1 with -3 missing; more pages were promised but never fetched.
        try await recordPage(store, pageIndex: 0, requestedHours: 10, returned: [-1, -2, -4, -5], nextPageToken: "more")
        let settled = try await store.settledHourStarts(provider: provider, in: window, at: sanFrancisco)
        #expect(settled == Set((-5...(-1)).map(hour)))
        #expect(!settled.contains(hour(-6)))  // The interrupted run's older hours still need fetching.
    }

    @Test("A request's final page settles everything back to the start of its requested range")
    func finalPage() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        try await recordPage(store, pageIndex: 0, requestedHours: 8, returned: [-1, -2, -3], nextPageToken: nil)
        let settled = try await store.settledHourStarts(provider: provider, in: window, at: sanFrancisco)
        #expect(settled == Set((-8...(-1)).map(hour)))
    }

    @Test("A failed page settles nothing")
    func failedPage() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        var attempt = EnvironmentalAttemptRecord(provider: provider, requestKind: "history", requestedAt: requestHour,
                                                 timeZoneID: "UTC", status: .httpError, parserVersion: 1, appVersion: "t")
        attempt.requestParameters = #"{"hours":8,"pageSize":168}"#
        try await store.record(attempt)
        #expect(try await store.settledHourStarts(provider: provider, in: window, at: sanFrancisco).isEmpty)
    }

    @Test("Not-sent attempts don't count as usage or as the latest request")
    func notSentIsNotUsage() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        try await store.record(EnvironmentalAttemptRecord(provider: provider, requestKind: "history", requestedAt: requestHour,
                                                          timeZoneID: "UTC", status: .notSent, parserVersion: 1, appVersion: "t"))
        #expect(try await store.providerRequestCount(provider: provider, since: .distantPast) == 0)
        #expect(try await store.latestRequestAt(provider: provider) == nil)
    }

    @Test("Hours answered for another area don't settle this one; the series filters or separates places")
    func perPlace() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        try await recordPage(store, pageIndex: 0, requestedHours: 3, returned: [-1, -2, -3], nextPageToken: nil, at: oakland)
        #expect(try await store.settledHourStarts(provider: provider, in: window, at: sanFrancisco).isEmpty)
        #expect(try await store.settledHourStarts(provider: provider, in: window, at: oakland).count == 3)
        #expect(sanFrancisco.kilometres(to: oakland) > RecordPlace.sameAreaKilometres)
    }

    @Test("The same hour at two places: filtered by place, or kept once per place without one")
    func seriesPerPlace() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        try await recordPage(store, pageIndex: 0, requestedHours: 1, returned: [-1], nextPageToken: nil, value: 30)
        try await recordPage(store, pageIndex: 0, requestedHours: 1, returned: [-1], nextPageToken: nil, at: oakland, value: 55)
        let here = try await store.environmentSeries(in: window, near: sanFrancisco)
        #expect(here.hourly.map(\.value) == [30])
        let everywhere = try await store.environmentSeries(in: window, near: nil)
        #expect(everywhere.hourly.map(\.value).sorted() == [30, 55])
    }

    @Test("A gap exactly between two pages of one request is settled; a later separate request isn't bridged")
    func gapBetweenPages() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        // Page 0 returns -1...-3, page 1 returns -5...-7: hour -4 falls between them (a provider gap).
        try await recordPage(store, pageIndex: 0, requestedHours: 10, returned: [-1, -2, -3], nextPageToken: "p1")
        try await recordPage(store, pageIndex: 1, requestedHours: 10, returned: [-5, -6, -7], nextPageToken: "p2")
        let settled = try await store.settledHourStarts(provider: provider, in: window, at: sanFrancisco)
        #expect(settled == Set((-7...(-1)).map(hour)))
        #expect(!settled.contains(hour(-8)))  // Page 2 was never fetched.
    }

    @Test("Pages from the same area on either side of a 0.1° line are one place: one value per hour")
    func sameAreaAcrossGridLine() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let north = RecordPlace(latitude: 37.75, longitude: -122.41), south = RecordPlace(latitude: 37.74, longitude: -122.41)
        try await recordPage(store, pageIndex: 0, requestedHours: 1, returned: [-1], nextPageToken: nil, at: north, value: 30)
        try await recordPage(store, pageIndex: 0, requestedHours: 1, returned: [-1], nextPageToken: nil, at: south, value: 31)
        #expect(try await store.environmentSeries(in: window, near: nil).hourly.count == 1)
    }

    @Test("A page without the chart index does not hide a later value for the same hour")
    func overlappingPageWithMissingIndex() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        try await recordPage(store, pageIndex: 0, requestedHours: 1, returned: [-1], nextPageToken: nil)
        try await recordPage(store, pageIndex: 1, requestedHours: 1, returned: [-1], nextPageToken: nil, value: 30)

        let series = try await store.environmentSeries(in: window, near: sanFrancisco)
        #expect(series.hourly.map(\.value) == [30])
    }
}
