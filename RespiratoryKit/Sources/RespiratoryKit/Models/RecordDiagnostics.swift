import Foundation

/// Whether a local day was a collection opportunity. Derived at read time: a day with no
/// `DailyRecord` between the first record and today is "not collected".
public struct DayCollection: Sendable, Equatable, Identifiable {
    public let dayKey: String
    public let isCollected: Bool
    public var id: String { dayKey }

    public init(dayKey: String, isCollected: Bool) {
        self.dayKey = dayKey
        self.isCollected = isCollected
    }
}

public struct ProviderUsage: Sendable, Equatable, Identifiable {
    public let provider: String
    public let used: Int
    public let limit: Int
    public var id: String { provider }

    public init(provider: String, used: Int, limit: Int) {
        self.provider = provider
        self.used = used
        self.limit = limit
    }
}

public enum RecordCoverage {
    /// Every local day from the first recorded day through the day containing `now`, newest first.
    /// Days are keyed in `timeZone`; a record keyed in another zone that falls outside that range is
    /// still listed, so no stored day is ever hidden.
    public static func days(records: [DailyRecordSnapshot], through now: Date, in timeZone: TimeZone) -> [DayCollection] {
        guard let firstStart = records.map(\.dayStart).min() else { return [] }
        let collected = Set(records.map(\.dayKey))
        let last = LocalDay(containing: now, in: timeZone)
        var day = LocalDay(containing: firstStart, in: timeZone)
        var keys: [String] = []
        // Bounded so a corrupt far-past date can't spin; ten years of days is ample.
        while day.interval.start <= last.interval.start, keys.count < 3_660 {
            keys.append(day.key)
            day = day.next
        }
        let listed = Set(keys)
        let all = keys + collected.subtracting(listed)
        return all.sorted(by: >).map { DayCollection(dayKey: $0, isCollected: collected.contains($0)) }
    }
}
