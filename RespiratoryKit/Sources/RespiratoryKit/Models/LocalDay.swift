import Foundation

/// A local calendar day in a specific time zone: its "yyyy-MM-dd" key and its exact half-open
/// interval [start, end). DST transition days are 23 h or 25 h long, and consecutive days tile
/// with no gap or overlap, so bucketing instants by `LocalDay` never double-counts or drops one.
public struct LocalDay: Sendable, Hashable {
    public let key: String
    public let interval: DateInterval
    public let timeZone: TimeZone

    public init(containing date: Date, in timeZone: TimeZone) {
        let calendar = Self.calendar(in: timeZone)
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            preconditionFailure("The Gregorian calendar always defines a day interval")
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: interval.start)
        self.key = Self.key(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
        self.interval = interval
        self.timeZone = timeZone
    }

    /// Returns nil for a malformed key or a date that doesn't exist.
    public init?(key: String, in timeZone: TimeZone) {
        let fields = key.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        let calendar = Self.calendar(in: timeZone)
        let components = DateComponents(year: fields[0], month: fields[1], day: fields[2], hour: 12)
        guard let noon = calendar.date(from: components) else { return nil }
        let day = LocalDay(containing: noon, in: timeZone)
        guard day.key == key else { return nil }
        self = day
    }

    public var utcOffsetAtStartSeconds: Int { timeZone.secondsFromGMT(for: interval.start) }

    /// Half-open: the end instant belongs to the next day.
    public func contains(_ date: Date) -> Bool {
        interval.start <= date && date < interval.end
    }

    public var next: LocalDay { LocalDay(containing: interval.end, in: timeZone) }

    public var previous: LocalDay { LocalDay(containing: interval.start.addingTimeInterval(-1), in: timeZone) }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func key(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
