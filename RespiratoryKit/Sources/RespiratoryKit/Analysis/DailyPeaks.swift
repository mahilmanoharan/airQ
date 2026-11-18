import Foundation

/// One local day's highest hourly index and how many of its hours were stored.
public struct DayPeak: Sendable, Equatable, Identifiable {
    public let dayKey: String
    public let peak: Int
    public let hours: Int
    public var id: String { dayKey }
}

public enum DailyPeaks {
    /// A day needs this many stored hours before its peak is reported: a day with a few hours
    /// would understate how high it went, so it is left out (and counted) rather than shown.
    public static let minimumHours = 18

    /// Groups hourly points by local day. Repeated hours count once. `partialDays` is the number of
    /// days that had some data but too little to report.
    public static func compute(hourly: [EnvironmentSeries.AQIPoint], timeZone: TimeZone)
        -> (days: [DayPeak], partialDays: Int) {
        var byDay: [String: [Date: Int]] = [:]
        for point in AirCoverage.resolve(hourly).points {
            let key = LocalDay(containing: point.date, in: timeZone).key
            byDay[key, default: [:]][point.date] = max(byDay[key]?[point.date] ?? .min, point.value)
        }
        var days: [DayPeak] = []
        var partial = 0
        for (key, hours) in byDay {
            guard hours.count >= minimumHours, let peak = hours.values.max() else { partial += 1; continue }
            days.append(DayPeak(dayKey: key, peak: peak, hours: hours.count))
        }
        return (days.sorted { $0.dayKey < $1.dayKey }, partial)
    }
}
