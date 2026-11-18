import Foundation
import Observation

/// The last 30 whole days (not today) of stored hourly history as one peak value per day, for a "how were the last
/// 30 days" card. Read-only over what is already stored (no provider request), and drawn from the
/// hourly series only, so it never mixes indexes from different sources.
@MainActor @Observable
public final class MonthAirQualityViewModel {
    public static let dayCount = 30

    public private(set) var days: [DayPeak] = []
    public private(set) var partialDays = 0
    public private(set) var hasLoaded = false
    public private(set) var errorMessage: String?

    private let records: any EnvironmentSeriesReading
    private let place: RecordPlace?
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private var loadGeneration = 0

    public init(records: any EnvironmentSeriesReading, place: RecordPlace?, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.records = records
        self.place = place
        self.timeZone = timeZone
        self.now = now
    }

    public var isEmpty: Bool { days.isEmpty }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Today is never a full day, so the month is the 30 whole days before it.
        let end = calendar.startOfDay(for: now())
        guard let start = calendar.date(byAdding: .day, value: -Self.dayCount, to: end) else { return }
        do {
            let series = try await records.environmentSeries(in: DateInterval(start: start, end: end), near: place)
            guard generation == loadGeneration else { return }
            try Task.checkCancellation()
            let result = DailyPeaks.compute(hourly: series.hourly, timeZone: timeZone)
            days = result.days
            partialDays = result.partialDays
            errorMessage = nil
            hasLoaded = true
        } catch {
            guard generation == loadGeneration else { return }
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }
}
