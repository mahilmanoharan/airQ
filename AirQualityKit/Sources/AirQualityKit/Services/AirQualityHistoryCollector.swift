import Foundation

/// Keeps an hourly Google Air Quality series by requesting back to the oldest completed hour in the
/// lookback window that isn't settled yet (stored, or answered as a gap by an earlier page). Pages arrive newest first, so an interrupted backfill
/// leaves its older hours missing; this resumes it instead of only filling after the newest hour.
/// It runs at most once per `minimumInterval`, pages until caught up (at most `maximumPagesPerRun`),
/// stops at the request budget, and reports every attempt, including skips.
/// Worst case: 6 requests a day, about 186 a month; typically 1 a day after the first backfill.
public struct AirQualityHistoryCollector: Sendable {
    /// Google serves up to 720 hours back; a day's margin stays clear of that limit.
    public static let maximumHours = 696
    public static let minimumInterval: TimeInterval = 24 * 3_600
    public static let maximumPagesPerRun = 6

    private let client: any AirQualityHistoryFetching
    private let budget: any RequestBudgeting
    /// Hours needing no request at a coordinate: stored from, or already answered by, a successful
    /// page requested there (history is per location).
    private let settledHours: @Sendable (DateInterval, GeoCoordinate) async throws -> Set<Date>
    private let lastRequestAt: @Sendable () async throws -> Date?
    private let record: @Sendable (ProviderAttempt) async -> Void
    private let clock: @Sendable () -> Date
    private let maySendLocation: @Sendable () async -> Bool
    private let skips = SkipMemory()

    /// When a budget skip was last written. Skipped attempts don't count as requests, so nothing else
    /// throttles them: without this every dashboard refresh after the budget is spent would append
    /// another permanent row. In memory, so at most one per launch per `minimumInterval`.
    private actor SkipMemory {
        private var last: Date?
        func shouldRecord(at now: Date) -> Bool {
            if let last, now.timeIntervalSince(last) < AirQualityHistoryCollector.minimumInterval { return false }
            last = now
            return true
        }
    }

    public init(client: any AirQualityHistoryFetching, budget: any RequestBudgeting,
                settledHours: @escaping @Sendable (DateInterval, GeoCoordinate) async throws -> Set<Date>,
                lastRequestAt: @escaping @Sendable () async throws -> Date?,
                record: @escaping @Sendable (ProviderAttempt) async -> Void,
                clock: @escaping @Sendable () -> Date = { Date() },
                maySendLocation: @escaping @Sendable () async -> Bool = { true }) {
        self.client = client
        self.budget = budget
        self.settledHours = settledHours
        self.lastRequestAt = lastRequestAt
        self.record = record
        self.clock = clock
        self.maySendLocation = maySendLocation
    }

    /// Returns the number of requests sent.
    @discardableResult
    public func collect(at coordinate: GeoCoordinate) async -> Int {
        guard await maySendLocation(), !Task.isCancelled else { return 0 }
        let now = clock()
        let lastRequest: Date?
        let stored: Set<Date>
        do {
            lastRequest = try await lastRequestAt()
            if let lastRequest, now.timeIntervalSince(lastRequest) < Self.minimumInterval { return 0 }
            stored = try await settledHours(Self.lookbackWindow(now: now), coordinate)
        } catch {
            return 0  // Usage and coverage are unknown, so don't spend.
        }
        guard let hours = Self.missingHours(stored: stored, now: now) else { return 0 }

        var pageToken: String?
        var requests = 0
        for pageIndex in 0..<Self.maximumPagesPerRun {
            guard !Task.isCancelled, await maySendLocation() else { break }
            guard await budget.permits(.googleAirQuality, at: clock()) else {
                if await skips.shouldRecord(at: clock()) {
                    await record(.notSent(.googleAirQuality, requestKind: "history", at: clock(), status: .skippedBudget,
                                          detail: "The app's monthly Google Air Quality request budget has been reached."))
                }
                break
            }
            guard await maySendLocation(), !Task.isCancelled else { break }
            requests += 1
            do {
                let page = try await client.airQualityHistory(at: coordinate, hours: hours,
                                                              pageToken: pageToken, pageIndex: pageIndex)
                await record(page.attempt)
                guard let next = page.value.nextPageToken, !next.isEmpty else { break }
                pageToken = next
            } catch let failure as ProviderFailure {
                await record(failure.attempt)
                break
            } catch {
                break
            }
        }
        return requests
    }

    /// The completed hours Google can still serve: [current hour − `maximumHours`, current hour).
    static func lookbackWindow(now: Date) -> DateInterval {
        let currentHour = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
        return DateInterval(start: currentHour.addingTimeInterval(-Double(maximumHours) * 3_600), end: currentHour)
    }

    /// How many hours back to request so the oldest missing completed hour in the window is
    /// included; nil when every hour in the window is stored.
    static func missingHours(stored: Set<Date>, now: Date) -> Int? {
        let window = lookbackWindow(now: now)
        for offset in stride(from: maximumHours, through: 1, by: -1) {
            let hour = window.end.addingTimeInterval(-Double(offset) * 3_600)
            if !stored.contains(hour) { return offset }
        }
        return nil
    }
}
