import Foundation
import Testing
@testable import AirQualityKit

@Suite("Air quality history collector")
struct AirQualityHistoryCollectorTests {
    private let here = GeoCoordinate(latitude: 37.77, longitude: -122.42)

    private func utc(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }

    private func makeCollector(client: StubHistoryClient, recorder: AttemptRecorder, allowed: Bool = true,
                               latestHour: Date? = nil, lastRequest: Date? = nil,
                               failLookup: Bool = false, now: Date) -> AirQualityHistoryCollector {
        AirQualityHistoryCollector(
            client: client, budget: FixedBudget(allowed: allowed),
            settledHours: { window, _ in
                if failLookup { throw CocoaError(.fileReadUnknown) }
                // Contiguous coverage from the window start through `latestHour`.
                guard let latestHour else { return [] }
                return Set(stride(from: window.start.timeIntervalSince1970, through: latestHour.timeIntervalSince1970, by: 3_600)
                    .map { Date(timeIntervalSince1970: $0) })
            },
            lastRequestAt: { lastRequest },
            record: { await recorder.append($0) },
            clock: { now })
    }

    @Test("A first run backfills 696 hours, following page tokens until caught up")
    func firstRunBackfills() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: ["t1", "t2", nil])
        let recorder = AttemptRecorder()
        let sent = await makeCollector(client: client, recorder: recorder, now: now).collect(at: here)

        let requests = await client.requests
        #expect(sent == 3)
        #expect(requests.map(\.pageToken) == [nil, "t1", "t2"])
        #expect(requests.allSatisfy { $0.hours == 696 })
        #expect(await recorder.attempts.map(\.pageIndex) == [0, 1, 2])
    }

    @Test("Runs at most once per 24 hours")
    func rateLimited() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: [nil])
        let recorder = AttemptRecorder()
        let sent = await makeCollector(client: client, recorder: recorder,
                                       lastRequest: now.addingTimeInterval(-3_600), now: now).collect(at: here)
        #expect(sent == 0)
        #expect(await client.requests.isEmpty)
        #expect(await recorder.attempts.isEmpty)
    }

    @Test("Gap-fills exactly the completed hours after the latest stored hour")
    func gapFill() async throws {
        let now = try utc("2026-09-14T15:30:00Z")  // Completed hours run through 14:00.
        let client = StubHistoryClient(nextTokens: [nil])
        let recorder = AttemptRecorder()
        await makeCollector(client: client, recorder: recorder, latestHour: try utc("2026-09-13T09:00:00Z"),
                            lastRequest: now.addingTimeInterval(-25 * 3_600), now: now).collect(at: here)
        #expect(await client.requests.first?.hours == 29)  // 2026-09-13 10:00 through 2026-09-14 14:00.
    }

    @Test("Nothing is requested when the last completed hour is already stored")
    func caughtUp() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: [nil])
        let recorder = AttemptRecorder()
        let sent = await makeCollector(client: client, recorder: recorder, latestHour: try utc("2026-09-14T14:00:00Z"),
                                       lastRequest: now.addingTimeInterval(-25 * 3_600), now: now).collect(at: here)
        #expect(sent == 0)
    }

    @Test("A long gap is capped at the provider's lookback")
    func cappedGap() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        #expect(AirQualityHistoryCollector.missingHours(stored: [try utc("2026-06-01T00:00:00Z")], now: now) == 696)
    }

    @Test("An interrupted backfill resumes from its oldest missing hour, not just after the newest")
    func resumesHeadGap() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let window = AirQualityHistoryCollector.lookbackWindow(now: now)
        // Only the newest 168 hours arrived before page 1 failed.
        let newest = Set((1...168).map { window.end.addingTimeInterval(-Double($0) * 3_600) })
        #expect(AirQualityHistoryCollector.missingHours(stored: newest, now: now) == 696)
        // A single interior hole is also refilled.
        var all = Set((1...696).map { window.end.addingTimeInterval(-Double($0) * 3_600) })
        #expect(AirQualityHistoryCollector.missingHours(stored: all, now: now) == nil)
        all.remove(window.end.addingTimeInterval(-10 * 3_600))
        #expect(AirQualityHistoryCollector.missingHours(stored: all, now: now) == 10)
    }

    @Test("An exhausted budget sends nothing and records the skip")
    func budgetStops() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: [nil])
        let recorder = AttemptRecorder()
        let sent = await makeCollector(client: client, recorder: recorder, allowed: false, now: now).collect(at: here)
        #expect(sent == 0)
        #expect(await client.requests.isEmpty)
        #expect(await recorder.attempts.map(\.status) == [.skippedBudget])
    }

    @Test("Repeated runs against an exhausted budget record the skip once a day, not once per refresh")
    func skipRecordedOnce() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let recorder = AttemptRecorder()
        let collector = makeCollector(client: StubHistoryClient(nextTokens: [nil]), recorder: recorder, allowed: false, now: now)
        for _ in 0..<5 { await collector.collect(at: here) }
        #expect(await recorder.attempts.count == 1)
    }

    @Test("A failed page ends the run and is recorded")
    func failureStops() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: ["t1", "t2", nil], failAt: 1)
        let recorder = AttemptRecorder()
        let sent = await makeCollector(client: client, recorder: recorder, now: now).collect(at: here)
        #expect(sent == 2)
        #expect(await recorder.attempts.map(\.status) == [.success, .httpError])
    }

    @Test("Revocation after the first history page prevents the next request")
    func revocationStopsPaging() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: ["next", nil])
        let recorder = AttemptRecorder()
        let collector = AirQualityHistoryCollector(
            client: client, budget: FixedBudget(allowed: true),
            settledHours: { _, _ in [] }, lastRequestAt: { nil },
            record: { await recorder.append($0) }, clock: { now },
            maySendLocation: { await recorder.attempts.isEmpty })
        #expect(await collector.collect(at: here) == 1)
        #expect(await client.requests.map(\.pageIndex) == [0])
    }

    @Test("A run never sends more than the page cap")
    func pageCap() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: Array(repeating: "more", count: 20))
        let recorder = AttemptRecorder()
        let sent = await makeCollector(client: client, recorder: recorder, now: now).collect(at: here)
        #expect(sent == AirQualityHistoryCollector.maximumPagesPerRun)
    }

    @Test("If stored coverage can't be read, nothing is spent")
    func unknownState() async throws {
        let now = try utc("2026-09-14T15:30:00Z")
        let client = StubHistoryClient(nextTokens: [nil])
        let recorder = AttemptRecorder()
        let sent = await makeCollector(client: client, recorder: recorder, failLookup: true, now: now).collect(at: here)
        #expect(sent == 0)
        #expect(await client.requests.isEmpty)
    }
}

private struct HistoryRequestRecord: Sendable, Equatable {
    let hours: Int
    let pageToken: String?
    let pageIndex: Int
}

private actor StubHistoryClient: AirQualityHistoryFetching {
    var requests: [HistoryRequestRecord] = []
    let nextTokens: [String?]
    let failAt: Int?

    init(nextTokens: [String?], failAt: Int? = nil) {
        self.nextTokens = nextTokens
        self.failAt = failAt
    }

    func airQualityHistory(at coordinate: GeoCoordinate, hours: Int,
                           pageToken: String?, pageIndex: Int) async throws -> Fetched<AirQualityHistoryPage> {
        requests.append(HistoryRequestRecord(hours: hours, pageToken: pageToken, pageIndex: pageIndex))
        var attempt = ProviderAttempt(provider: .googleAirQuality, requestKind: "history", requestedAt: .distantPast,
                                      status: .success, parserVersion: 1)
        attempt.pageIndex = pageIndex
        if pageIndex == failAt {
            attempt.status = .httpError
            throw ProviderFailure(attempt: attempt, underlying: AirQualityServiceError.httpStatus(403))
        }
        let next = pageIndex < nextTokens.count ? nextTokens[pageIndex] : nil
        return Fetched(value: AirQualityHistoryPage(hours: [], nextPageToken: next), attempt: attempt)
    }
}

private actor AttemptRecorder {
    var attempts: [ProviderAttempt] = []
    func append(_ attempt: ProviderAttempt) { attempts.append(attempt) }
}

private struct FixedBudget: RequestBudgeting {
    let allowed: Bool
    func permits(_ provider: EnvironmentalProvider, at date: Date) async -> Bool { allowed }
}
