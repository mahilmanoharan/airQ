import Foundation
import Observation

/// Read-only diagnostics over the stored record: collection days, metered usage, hourly history
/// coverage and recent provider attempts. It never writes.
@MainActor @Observable
public final class RecordsViewModel {
    public static let attemptLimit = 100

    public private(set) var days: [DayCollection] = []
    public private(set) var usage: [ProviderUsage] = []
    public private(set) var coverage: [String: HourlyCoverage] = [:]
    public private(set) var attempts: [AttemptSummary] = []
    public private(set) var counts: RecordCounts?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var errorMessage: String?

    public var collectedDayCount: Int { days.count(where: \.isCollected) }
    public var missingDayCount: Int { days.count(where: { !$0.isCollected }) }

    private let store: any RecordReading
    private let usageLimits: [String: Int]
    private let usageWindow: TimeInterval
    private let historyProviders: [String]
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    public init(store: any RecordReading, usageLimits: [String: Int], usageWindow: TimeInterval,
                historyProviders: [String], timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.usageLimits = usageLimits
        self.usageWindow = usageWindow
        self.historyProviders = historyProviders
        self.timeZone = timeZone
        self.now = now
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let current = now()
            let records = try await store.dailyRecords()
            var usage: [ProviderUsage] = []
            for (provider, limit) in usageLimits.sorted(by: { $0.key < $1.key }) {
                let used = try await store.providerRequestCount(provider: provider, since: current.addingTimeInterval(-usageWindow))
                usage.append(ProviderUsage(provider: provider, used: used, limit: limit))
            }
            var coverage: [String: HourlyCoverage] = [:]
            for provider in historyProviders {
                coverage[provider] = try await store.hourlyCoverage(provider: provider)
            }
            let attempts = try await store.recentAttempts(limit: Self.attemptLimit)
            let counts = try await store.recordCounts()
            try Task.checkCancellation()
            self.days = RecordCoverage.days(records: records, through: current, in: timeZone)
            self.usage = usage
            self.coverage = coverage
            self.attempts = attempts
            self.counts = counts
            hasLoaded = true
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }
}
