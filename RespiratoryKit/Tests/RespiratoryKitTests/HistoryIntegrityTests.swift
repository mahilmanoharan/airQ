import Foundation
import Testing
@testable import RespiratoryKit

@Suite("History integrity")
struct HistoryIntegrityTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private func date(_ value: String) throws -> Date { try Date(value, strategy: .iso8601) }

    private func chart(_ environment: EnvironmentSeries, domain: DateInterval,
                       events: [ContextEventSnapshot] = []) -> ChartData {
        ChartSeries.make(domain: domain, timeZone: zone, records: [], environment: environment,
                         detections: [], sessions: [], checkIns: [], tuning: .init(),
                         detectionLabel: "cough", contextEvents: events)
    }

    @Test("Pollen uses its forecast day even when the request was on the previous local day")
    func pollenForecastDay() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        // UTC September 11, but still September 10 in Los Angeles.
        var attempt = EnvironmentalAttemptRecord(provider: "googlePollen", requestKind: "forecast",
            requestedAt: try date("2026-09-11T02:00:00Z"), timeZoneID: zone.identifier,
            status: .success, parserVersion: 1, appVersion: "t")
        attempt.forecastDate = "2026-09-11"
        attempt.pollenTypes = [.init(code: "GRASS", upi: 3, category: nil, inSeason: nil)]
        try await store.record(attempt)
        let domain = DateInterval(start: try date("2026-09-11T07:00:00Z"), end: try date("2026-09-12T07:00:00Z"))
        let environment = try await store.environmentSeries(in: domain)
        let result = chart(environment, domain: domain)
        #expect(result.pollen.count == 1)
        #expect(result.pollen.first?.day == domain.start)
    }

    @Test("Life-event report dates remain original when the plotted span clips both ends")
    func originalEventDates() throws {
        let domain = DateInterval(start: try date("2026-09-10T07:00:00Z"), end: try date("2026-09-21T07:00:00Z"))
        let event = ContextEventSnapshot(id: UUID(), originalID: UUID(),
            draft: .init(category: "travel", note: "Visit", startDayKey: "2026-09-01", endDayKey: "2026-09-30"),
            firstRecordedAt: .distantPast, lastRecordedAt: .distantPast, revisionCount: 0, isRetracted: false)
        let data = chart(.init(waqi: [], hourly: [], pollen: [], successDayKeys: []), domain: domain, events: [event])
        #expect(data.context.first?.start == domain.start)
        #expect(data.context.first?.end == domain.end)
        let summary = ClinicianSummary.make(from: data, timeZone: zone, tuning: .init())
        #expect(summary.lifeEvents.first?.firstDayKey == "2026-09-01")
        #expect(summary.lifeEvents.first?.lastDayKey == "2026-09-30")
    }

    @Test("Overlapping histories from distant places never become the day's personal air peak")
    func mixedPlaces() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let start = try date("2026-09-10T07:00:00Z")
        for (latitude, value) in [(37.79, 30), (40.71, 200)] {
            var page = EnvironmentalAttemptRecord(provider: "googleAirQuality", requestKind: "history",
                requestedAt: start.addingTimeInterval(86_500), timeZoneID: zone.identifier,
                status: .success, parserVersion: 1, appVersion: "t")
            page.latitude = latitude
            page.longitude = -122.41
            page.hours = (0..<24).map { hour in
                .init(hourStart: start.addingTimeInterval(Double(hour) * 3_600),
                      indexes: [.init(code: "usa_epa", aqi: value, category: nil, dominantPollutant: nil)], pollutants: nil)
            }
            try await store.record(page)
        }
        let domain = DateInterval(start: start, duration: 86_400)
        let environment = try await store.environmentSeries(in: domain)
        #expect(environment.hourly.count == 48)
        let data = chart(environment, domain: domain)
        #expect(data.hourly.isEmpty)
        let summary = ClinicianSummary.make(from: data, timeZone: zone, tuning: .init())
        #expect(summary.air.reported == 0)
        #expect(summary.worstAirDay == nil)
        #expect(summary.text.contains("24 overlapping hours"))
        #expect(summary.text.contains("2 saved areas"))
        // DailyPeaks also protects callers that use the raw, all-place series directly.
        #expect(DailyPeaks.compute(hourly: environment.hourly, timeZone: zone).days.isEmpty)
        #expect(data.airCoverage?.storedHours == 24)
        #expect(data.airCoverage?.ambiguousHours == 24)
        #expect(data.airCoverage?.places.count == 2)
    }

    @Test("Known and unknown places are ambiguous together; nearby and legacy-only hours remain usable")
    func unknownAndNearbyPlaces() throws {
        let start = try date("2026-09-10T07:00:00Z")
        let home = RecordPlace(latitude: 37.79, longitude: -122.41)
        let nearby = RecordPlace(latitude: 37.80, longitude: -122.41)
        let hour1 = start.addingTimeInterval(3_600), hour2 = start.addingTimeInterval(7_200)
        let points: [EnvironmentSeries.AQIPoint] = [
            .init(date: start, value: 30, source: "usa_epa", place: home),
            .init(date: start, value: 190, source: "usa_epa"),
            .init(date: hour1, value: 40, source: "usa_epa", place: home),
            .init(date: hour1, value: 45, source: "usa_epa", place: nearby),
            .init(date: hour2, value: 50, source: "usa_epa"),
        ]
        let data = chart(.init(waqi: [], hourly: points, pollen: [], successDayKeys: []),
                         domain: DateInterval(start: start, duration: 86_400))
        #expect(data.hourly.map(\.value) == [45, 50])
        #expect(data.airCoverage?.storedHours == 3)
        #expect(data.airCoverage?.ambiguousHours == 1)
        #expect(data.airCoverage?.unknownPlaceHours == 2)
        #expect(data.airCoverage?.places.count == 1)
    }

    @Test("Undated pollen uses the local request day; invalid and outside forecast dates are omitted")
    func legacyPollenDates() throws {
        let start = try date("2026-09-10T07:00:00Z")
        let at = start.addingTimeInterval(3_600)
        let environment = EnvironmentSeries(waqi: [], hourly: [], pollen: [
            .init(requestedAt: at, code: "GRASS", upi: 2),
            .init(requestedAt: at, code: "TREE", upi: 4, forecastDate: "2026-09-11"),
            .init(requestedAt: at, code: "WEED", upi: 5, forecastDate: "bad-date"),
        ], successDayKeys: [])
        let data = chart(environment, domain: DateInterval(start: start, duration: 86_400))
        #expect(data.pollen.map(\.code) == ["GRASS"])
        #expect(data.pollen.first?.day == start)
    }

    @Test("An ongoing event retains its original start and has no invented report end date")
    func ongoingEventDates() throws {
        let domain = DateInterval(start: try date("2026-09-10T07:00:00Z"), end: try date("2026-09-21T07:00:00Z"))
        let event = ContextEventSnapshot(id: UUID(), originalID: UUID(),
            draft: .init(category: "illness", note: "", startDayKey: "2026-09-01", endDayKey: nil),
            firstRecordedAt: .distantPast, lastRecordedAt: .distantPast, revisionCount: 0, isRetracted: false)
        let data = chart(.init(waqi: [], hourly: [], pollen: [], successDayKeys: []), domain: domain, events: [event])
        let summary = ClinicianSummary.make(from: data, timeZone: zone, tuning: .init())
        #expect(summary.lifeEvents.first?.firstDayKey == "2026-09-01")
        #expect(summary.lifeEvents.first?.lastDayKey == nil)
        #expect(data.context.first?.isOngoing == true)
    }
}

@Suite("Summary invalidation") @MainActor
struct SummaryInvalidationTests {
    @Test("A period change clears the shareable summary while loading and after failure")
    func failedReload() async throws {
        let records = SummaryReloadRecords()
        let model = ClinicianSummaryViewModel(records: records, detections: nil, tuning: { .init() })
        await model.load(period: .last30)
        #expect(model.summary != nil)
        await records.blockNextRead()
        let reload = Task { await model.load(period: .last90) }
        await records.waitForRead()
        #expect(model.isLoading)
        #expect(model.summary == nil)
        await records.failRead()
        await reload.value
        #expect(model.summary == nil)
        #expect(model.errorMessage != nil)
    }
}

private actor SummaryReloadRecords: ChartRecordReading {
    struct Failure: Error {}
    private var block = false
    private var gate: CheckedContinuation<Void, any Error>?
    private var arrival: CheckedContinuation<Void, Never>?
    func blockNextRead() { block = true }
    func dailyRecords() async throws -> [DailyRecordSnapshot] {
        if block {
            try await withCheckedThrowingContinuation { gate = $0; arrival?.resume(); arrival = nil }
        }
        return []
    }
    func waitForRead() async {
        if gate != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func failRead() { gate?.resume(throwing: Failure()); gate = nil }
    func checkInRows() async throws -> [CheckInRow] { [] }
    func contextEventRows() async throws -> [ContextEventRow] { [] }
    func environmentSeries(in interval: DateInterval, near place: RecordPlace?) async throws -> EnvironmentSeries {
        .init(waqi: [], hourly: [], pollen: [], successDayKeys: [])
    }
}
