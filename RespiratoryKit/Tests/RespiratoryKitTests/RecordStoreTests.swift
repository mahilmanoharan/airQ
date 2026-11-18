import Foundation
import Testing
@testable import RespiratoryKit

@Suite("RecordStore")
struct RecordStoreTests {
    private let losAngeles = "America/Los_Angeles"

    private func makeStore() throws -> RecordStore {
        RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
    }

    private func utc(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }

    private func timeZone() throws -> TimeZone { try #require(TimeZone(identifier: losAngeles)) }

    @Test("A day is recorded once; the first sighting wins")
    func ensureDayIsIdempotent() async throws {
        let store = try makeStore()
        let morning = try utc("2026-09-14T15:00:00Z")
        let evening = try utc("2026-09-15T04:00:00Z")  // 21:00 PDT, same local day
        let first = try await store.ensureDay(containing: morning, in: try timeZone(), appVersion: "1.0 (2)")
        let second = try await store.ensureDay(containing: evening, in: try timeZone(), appVersion: "1.0 (2)")

        let days = try await store.dailyRecords()
        #expect(first == "2026-09-14" && second == "2026-09-14")
        #expect(days.count == 1)
        #expect(days.first?.firstSeenAt == morning)
    }

    @Test("A fall-back day is stored with its 25-hour interval")
    func dstDayInterval() async throws {
        let store = try makeStore()
        try await store.ensureDay(containing: try utc("2026-11-01T20:00:00Z"), in: try timeZone(), appVersion: "1.0 (2)")
        let day = try #require(try await store.dailyRecords().first)
        #expect(day.dayEnd.timeIntervalSince(day.dayStart) == 90_000)
    }

    @Test("A successful attempt round-trips every raw and parsed field, and marks its day")
    func recordsSuccess() async throws {
        let store = try makeStore()
        var attempt = EnvironmentalAttemptRecord(provider: "googleAirQuality", requestKind: "history",
                                                 requestedAt: try utc("2026-09-14T15:00:00Z"), timeZoneID: losAngeles,
                                                 status: .success, parserVersion: 1, appVersion: "1.0 (2)")
        attempt.receivedAt = try utc("2026-09-14T15:00:01Z")
        attempt.httpStatus = 200
        attempt.latitude = 37.77
        attempt.longitude = -122.42
        attempt.coordinateDecimals = 2
        attempt.requestParameters = #"{"pageSize":168}"#
        attempt.pageIndex = 0
        attempt.rawResponse = Data(#"{"hoursInfo":[]}"#.utf8)
        attempt.hours = [
            .init(hourStart: try utc("2026-09-14T13:00:00Z"),
                  indexes: [.init(code: "uaqi", aqi: 80, category: "Excellent", dominantPollutant: "o3")],
                  pollutants: [.init(code: "pm25", value: 4.1, units: "MICROGRAMS_PER_CUBIC_METER")]),
            .init(hourStart: try utc("2026-09-14T14:00:00Z"), indexes: nil, pollutants: nil),
        ]
        try await store.record(attempt)

        #expect(try await store.observations(since: .distantPast) == [attempt])
        #expect(try await store.dailyRecords().map(\.dayKey) == ["2026-09-14"])
        #expect(try await store.latestHourStart(provider: "googleAirQuality") == (try utc("2026-09-14T14:00:00Z")))
    }

    @Test("A failed attempt is stored as an explicit row with its reason and no values")
    func recordsFailure() async throws {
        let store = try makeStore()
        var attempt = EnvironmentalAttemptRecord(provider: "waqi", requestKind: "current",
                                                 requestedAt: try utc("2026-09-14T15:00:00Z"), timeZoneID: losAngeles,
                                                 status: .httpError, parserVersion: 1, appVersion: "1.0 (2)")
        attempt.httpStatus = 503
        attempt.failureDetail = "The air quality service is temporarily unavailable."
        try await store.record(attempt)

        let stored = try #require(try await store.observations(since: .distantPast).first)
        #expect(stored.status == .httpError)
        #expect(stored.httpStatus == 503)
        #expect(stored.aqi == nil)
        #expect(try await store.dailyRecords().count == 1)
    }

    @Test("Usage counts only attempts that may have reached that provider since the given date")
    func providerRequestCount() async throws {
        let store = try makeStore()
        let since = try utc("2026-09-01T00:00:00Z")
        let statuses: [(String, EnvironmentalAttemptRecord.Status, String)] = [
            ("googlePollen", .success, "2026-09-10T00:00:00Z"),
            ("googlePollen", .httpError, "2026-09-10T01:00:00Z"),
            ("googlePollen", .cancelled, "2026-09-10T02:00:00Z"),
            ("googlePollen", .skippedBudget, "2026-09-10T03:00:00Z"),
            ("googlePollen", .locationUnavailable, "2026-09-10T04:00:00Z"),
            ("googlePollen", .success, "2026-08-31T23:00:00Z"),
            ("googleAirQuality", .success, "2026-09-10T05:00:00Z"),
        ]
        for (provider, status, iso) in statuses {
            try await store.record(EnvironmentalAttemptRecord(provider: provider, requestKind: "test",
                                                              requestedAt: try utc(iso), timeZoneID: losAngeles,
                                                              status: status, parserVersion: 1, appVersion: "1.0 (2)"))
        }
        #expect(try await store.providerRequestCount(provider: "googlePollen", since: since) == 3)
        #expect(try await store.providerRequestCount(provider: "googleAirQuality", since: since) == 1)
        #expect(try await store.latestRequestAt(provider: "googlePollen") == (try utc("2026-09-10T02:00:00Z")))
        #expect(try await store.latestRequestAt(provider: "waqi") == nil)
    }

    @Test("An attempt with an unknown time zone is rejected rather than bucketed into a guessed day")
    func unknownTimeZone() async throws {
        let store = try makeStore()
        let attempt = EnvironmentalAttemptRecord(provider: "waqi", requestKind: "current", requestedAt: .now,
                                                 timeZoneID: "Mars/Olympus_Mons", status: .success,
                                                 parserVersion: 1, appVersion: "1.0 (2)")
        await #expect(throws: RecordStoreError.unknownTimeZone("Mars/Olympus_Mons")) { try await store.record(attempt) }
        #expect(try await store.observations(since: .distantPast).isEmpty)
    }
}
