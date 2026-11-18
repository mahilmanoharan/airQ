import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Records diagnostics") @MainActor
struct RecordsViewModelTests {
    private func utc(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }
    private func losAngeles() throws -> TimeZone { try #require(TimeZone(identifier: "America/Los_Angeles")) }

    private func attempt(_ provider: String, at date: Date, status: EnvironmentalAttemptRecord.Status = .success,
                         hours: [Date] = []) -> EnvironmentalAttemptRecord {
        var record = EnvironmentalAttemptRecord(provider: provider, requestKind: "current", requestedAt: date,
                                                timeZoneID: "America/Los_Angeles", status: status,
                                                parserVersion: 1, appVersion: "test")
        record.hours = hours.map { .init(hourStart: $0, indexes: nil, pollutants: nil) }
        return record
    }

    @Test("Days between the first record and today without a record are listed as not collected")
    func gapDays() throws {
        let zone = try losAngeles()
        let records = ["2026-09-10", "2026-09-12"].compactMap { LocalDay(key: $0, in: zone) }.map {
            DailyRecordSnapshot(dayKey: $0.key, dayStart: $0.interval.start, dayEnd: $0.interval.end,
                                timeZoneID: zone.identifier, firstSeenAt: $0.interval.start)
        }
        let days = RecordCoverage.days(records: records, through: try utc("2026-09-13T19:00:00Z"), in: zone)
        #expect(days.map(\.dayKey) == ["2026-09-13", "2026-09-12", "2026-09-11", "2026-09-10"])
        #expect(days.map(\.isCollected) == [false, true, false, true])
        #expect(RecordCoverage.days(records: [], through: .now, in: zone).isEmpty)
    }

    @Test("Usage counts only attempts inside the rolling window that may have reached the provider")
    func usageWindow() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let now = try utc("2026-09-20T12:00:00Z")
        try await store.record(attempt("googleAirQuality", at: now.addingTimeInterval(-3_600)))
        try await store.record(attempt("googleAirQuality", at: now.addingTimeInterval(-3_600), status: .httpError))
        try await store.record(attempt("googleAirQuality", at: now.addingTimeInterval(-60), status: .skippedBudget))
        try await store.record(attempt("googleAirQuality", at: now.addingTimeInterval(-40 * 86_400)))
        let model = RecordsViewModel(store: store, usageLimits: ["googleAirQuality": 300, "googlePollen": 1_000],
                                     usageWindow: 31 * 86_400, historyProviders: [], timeZone: try losAngeles(),
                                     now: { now })
        await model.load()
        #expect(model.errorMessage == nil)
        #expect(model.usage == [ProviderUsage(provider: "googleAirQuality", used: 2, limit: 300),
                                ProviderUsage(provider: "googlePollen", used: 0, limit: 1_000)])
    }

    @Test("Recent attempts are newest first with hour counts; coverage de-duplicates overlapping hours")
    func attemptsAndCoverage() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let base = try utc("2026-09-20T00:00:00Z")
        let hours = (0..<3).map { base.addingTimeInterval(Double($0) * 3_600) }
        try await store.record(attempt("googleAirQuality", at: base.addingTimeInterval(10_000), hours: hours))
        try await store.record(attempt("googleAirQuality", at: base.addingTimeInterval(20_000), hours: Array(hours.suffix(2))))
        try await store.record(attempt("waqi", at: base.addingTimeInterval(30_000), status: .networkError))

        let model = RecordsViewModel(store: store, usageLimits: [:], usageWindow: 31 * 86_400,
                                     historyProviders: ["googleAirQuality"], timeZone: try losAngeles(),
                                     now: { base.addingTimeInterval(40_000) })
        await model.load()
        #expect(model.attempts.map(\.provider) == ["waqi", "googleAirQuality", "googleAirQuality"])
        #expect(model.attempts.map(\.hourCount) == [0, 2, 3])
        #expect(model.attempts.first?.status == "networkError")
        let coverage = try #require(model.coverage["googleAirQuality"])
        #expect(coverage.rowCount == 5 && coverage.distinctHours == 3)
        #expect(coverage.earliest == hours.first && coverage.latest == hours.last)
        #expect(model.counts?.providerAttempts == 3 && model.counts?.hourlyRows == 5)
        #expect(model.collectedDayCount == 2)  // 17:00 PDT Sep 19 → 01:20 PDT Sep 20
    }

    @Test("A storage failure is surfaced and loading ends")
    func surfacesErrors() async {
        let model = RecordsViewModel(store: FailingRecords(), usageLimits: ["googlePollen": 1], usageWindow: 1,
                                     historyProviders: [])
        await model.load()
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading && !model.hasLoaded)
    }
}

private struct FailingRecords: RecordReading {
    struct Failure: Error {}
    func dailyRecords() async throws -> [DailyRecordSnapshot] { throw Failure() }
    func providerRequestCount(provider: String, since date: Date) async throws -> Int { throw Failure() }
    func recentAttempts(limit: Int) async throws -> [AttemptSummary] { throw Failure() }
    func hourlyCoverage(provider: String) async throws -> HourlyCoverage { throw Failure() }
    func recordCounts() async throws -> RecordCounts { throw Failure() }
}
