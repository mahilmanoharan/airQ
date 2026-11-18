import Foundation

/// One day of WAQI's daily forecast. Pollutant values are AQI sub-indices (the same scale as the
/// station's `iaqi`), not concentrations. `day` is the station's local date, "yyyy-MM-dd".
public struct AirQualityForecastDay: Codable, Sendable, Equatable, Identifiable {
    public struct Range: Codable, Sendable, Equatable {
        public let min: Int
        public let average: Int
        public let max: Int

        public init(min: Int, average: Int, max: Int) {
            self.min = min
            self.average = average
            self.max = max
        }
    }

    public let day: String
    /// Keyed by WAQI pollutant code (`pm25`, `pm10`, `o3`).
    public let pollutants: [String: Range]
    public let uvIndex: Range?
    public var id: String { day }

    public init(day: String, pollutants: [String: Range], uvIndex: Range?) {
        self.day = day
        self.pollutants = pollutants
        self.uvIndex = uvIndex
    }

    /// The highest forecast sub-index of the day and its pollutant, the way AQI is driven by its
    /// worst pollutant. Ties resolve in `StationConditions.pollutantOrder`.
    public var peak: (code: String, subIndex: Int)? {
        StationConditions.pollutantOrder.compactMap { code in pollutants[code].map { (code, $0.max) } }
            .max { $0.1 < $1.1 }
            .map { (code: $0.0, subIndex: $0.1) }
    }

    /// The day as a date at noon in `calendar`'s zone, or nil if malformed.
    public func date(in calendar: Calendar) -> Date? {
        guard let utc = DayKey.date(day) else { return nil }
        let parts = DayKey.calendar.dateComponents([.year, .month, .day], from: utc)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    /// Today and later, in order. Days are compared as local calendar dates, so a station a time zone
    /// away can be a day off at the edges; that is accepted rather than guessing the station's zone.
    public static func upcoming(_ days: [AirQualityForecastDay], asOf date: Date,
                                calendar: Calendar = .current, limit: Int = 5) -> [AirQualityForecastDay] {
        let key = DayKey.local(date, in: calendar)
        return Array(days.filter { $0.day >= key }.sorted { $0.day < $1.day }.prefix(limit))
    }

    /// Groups WAQI's per-pollutant arrays into days. Unknown series other than `uvi` are ignored.
    static func days(fromDaily daily: [String: [(day: String, min: Int, average: Int, max: Int)]]) -> [AirQualityForecastDay] {
        var pollutants: [String: [String: Range]] = [:]
        var uv: [String: Range] = [:]
        for (code, items) in daily {
            for item in items {
                let range = Range(min: item.min, average: item.average, max: item.max)
                if code == "uvi" { uv[item.day] = range }
                else if StationConditions.pollutantOrder.contains(code) { pollutants[item.day, default: [:]][code] = range }
            }
        }
        return Set(pollutants.keys).union(uv.keys).sorted().map {
            AirQualityForecastDay(day: $0, pollutants: pollutants[$0] ?? [:], uvIndex: uv[$0])
        }
    }
}
