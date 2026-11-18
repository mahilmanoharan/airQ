import Foundation

/// A resolved pollen reading on Google's 0–5 Universal Pollen Index, independent of the provider's
/// response shape. A nil index means that type was absent from the response, never a measured zero.
public struct PollenReading: Codable, Sendable, Equatable {
    /// The at-a-glance value: the highest available of grass/tree/weed, not an average, the same
    /// way AQI is driven by its worst pollutant. Nil when no type has a value.
    public let overallIndex: Int?
    public let grassIndex: Int?
    public let treeIndex: Int?
    public let weedIndex: Int?
    /// Today's plants that have a value, highest first. Nil in older snapshots.
    public let plants: [PollenPlant]?
    /// The forecast days after today, in order (day 1 = tomorrow). Nil in older snapshots.
    public let outlook: [PollenOutlookDay]?
    /// Google's date for the first forecast day ("yyyy-MM-dd"). It is UTC-based, so an evening fetch
    /// west of UTC can already be local tomorrow. Nil when absent and in older snapshots.
    public let firstDayKey: String?

    public init(grassIndex: Int?, treeIndex: Int?, weedIndex: Int?,
                plants: [PollenPlant]? = nil, outlook: [PollenOutlookDay]? = nil, firstDayKey: String? = nil) {
        self.grassIndex = grassIndex
        self.treeIndex = treeIndex
        self.weedIndex = weedIndex
        self.overallIndex = [grassIndex, treeIndex, weedIndex].compactMap { $0 }.max()
        self.plants = plants
        self.outlook = outlook
        self.firstDayKey = firstDayKey
    }

    /// The forecast day keys in order: the first day, then one per outlook entry. Nil without a
    /// parseable `firstDayKey`.
    public var dayKeys: [String]? {
        guard let firstDayKey, let first = DayKey.date(firstDayKey) else { return nil }
        return (0...(outlook?.count ?? 0)).compactMap { offset in
            DayKey.calendar.date(byAdding: .day, value: offset, to: first).map(DayKey.string)
        }
    }

    /// The highest type index forecast for `dayKey`, or nil when that day isn't in the forecast.
    public func overallIndex(forDayKey dayKey: String) -> Int? {
        guard let offset = dayKeys?.firstIndex(of: dayKey) else { return nil }
        return offset == 0 ? overallIndex : outlook?[offset - 1].overallIndex
    }
}

/// "yyyy-MM-dd" keys as plain calendar dates (Gregorian, UTC arithmetic, so no DST effects).
public enum DayKey {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    public static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }

    /// The one place a day key is spelled: "yyyy-MM-dd".
    static func key(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func key(_ date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    public static func string(_ date: Date) -> String { key(date, in: calendar) }

    /// The key of the local day containing `date` in `calendar`.
    public static func local(_ date: Date, in calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "Today", "Tomorrow" or a short weekday for `key`, relative to the local day containing `date`
    /// (pass a widget entry's date, not the render time). Returns the key itself if it's malformed.
    public static func label(_ key: String, relativeTo date: Date, calendar: Calendar = .current,
                             locale: Locale = .current) -> String {
        guard let day = Self.date(key) else { return key }
        if key == local(date, in: calendar) { return "Today" }
        if let next = calendar.date(byAdding: .day, value: 1, to: date), key == local(next, in: calendar) {
            return "Tomorrow"
        }
        var style = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated)
        style.locale = locale
        return day.formatted(style)
    }
}

/// One plant (e.g. oak, ragweed) on the Universal Pollen Index.
public struct PollenPlant: Codable, Sendable, Equatable, Identifiable {
    public let code: String
    public let name: String
    public let index: Int
    /// Google's `inSeason`; nil when not reported. Off-season plants can still carry a value.
    public let inSeason: Bool?
    public var id: String { code }

    public init(code: String, name: String, index: Int, inSeason: Bool? = nil) {
        self.code = code
        self.name = name
        self.index = index
        self.inSeason = inSeason
    }
}

/// A later forecast day's type indexes. A nil type means no value that day, never zero.
public struct PollenOutlookDay: Codable, Sendable, Equatable {
    public let grassIndex: Int?
    public let treeIndex: Int?
    public let weedIndex: Int?

    public init(grassIndex: Int?, treeIndex: Int?, weedIndex: Int?) {
        self.grassIndex = grassIndex
        self.treeIndex = treeIndex
        self.weedIndex = weedIndex
    }

    public var overallIndex: Int? { [grassIndex, treeIndex, weedIndex].compactMap { $0 }.max() }
}
