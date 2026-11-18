import Foundation

/// Check-in days grouped by that day's air-quality band and pollen level, with how many of them the person
/// answered "yes" to daytime symptoms. Counts only: no rates, scores or conclusions. A day is counted in a row
/// only when both its level and its symptom answer are known, so unanswered days and days without enough air
/// data are left out rather than guessed.
public struct SymptomDaysByLevel: Sendable, Equatable {
    public struct Row<Level: Sendable & Equatable>: Sendable, Equatable {
        public let level: Level
        public let days: Int
        public let symptomDays: Int
    }

    /// By the day's peak hourly index (whole days only, as in the month card and the summary), best first.
    public let air: [Row<AirQualityBand>]
    /// By the day's highest pollen-type index (0–5), lowest first.
    public let pollen: [Row<Int>]

    public var isEmpty: Bool { air.isEmpty && pollen.isEmpty }

    public static func make(from data: ChartData, timeZone: TimeZone) -> SymptomDaysByLevel {
        func key(_ day: Date) -> String { LocalDay(containing: day, in: timeZone).key }
        var answered: [String: Bool] = [:]
        for point in data.checkIns {
            if let symptoms = point.daytimeSymptoms { answered[key(point.day)] = symptoms }
        }

        var airByDay: [String: AirQualityBand] = [:]
        for day in DailyPeaks.compute(hourly: data.hourly, timeZone: timeZone).days {
            airByDay[day.dayKey] = .of(day.peak)
        }
        var pollenByDay: [String: Int] = [:]
        for bar in data.pollen { pollenByDay[key(bar.day)] = max(pollenByDay[key(bar.day)] ?? 0, bar.upi) }

        func rows<Level: Hashable & Comparable & Sendable>(_ levels: [String: Level]) -> [Row<Level>] {
            var days: [Level: (days: Int, symptoms: Int)] = [:]
            for (day, symptoms) in answered {
                guard let level = levels[day] else { continue }
                days[level, default: (0, 0)].days += 1
                if symptoms { days[level, default: (0, 0)].symptoms += 1 }
            }
            return days.keys.sorted().map { Row(level: $0, days: days[$0]?.days ?? 0, symptomDays: days[$0]?.symptoms ?? 0) }
        }
        return SymptomDaysByLevel(air: rows(airByDay), pollen: rows(pollenByDay))
    }
}
