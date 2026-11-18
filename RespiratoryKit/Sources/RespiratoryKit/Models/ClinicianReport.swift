import Foundation

/// The saved record in a shared History period, with local calendar days grouped into weeks.
public struct ClinicianReport: Sendable, Equatable {
    public struct AnsweredDays: Sendable, Equatable {
        public let positive: Int
        public let answered: Int

        init(positive: Int, answered: Int) {
            self.positive = positive
            self.answered = answered
        }

        init(_ answers: [Bool]) {
            self.init(positive: answers.filter { $0 }.count, answered: answers.count)
        }
    }

    public struct Week: Sendable, Equatable, Identifiable {
        public let firstDayKey: String
        public let lastDayKey: String
        public let dayCount: Int
        public let checkInDays: Int
        public let symptoms: AnsweredDays
        public let nightWaking: AnsweredDays
        public let rescueInhaler: AnsweredDays
        public let peakFlow: ClosedRange<Int>?
        public let airDays: Int
        public let highestAQI: Int?
        public let pollenDays: Int
        public let pollenAtLeastModerateDays: Int

        public var id: String { firstDayKey }
    }

    public let summary: ClinicianSummary
    public let weeks: [Week]

    static func make(from data: ChartData, timeZone: TimeZone, tuning: DetectionTuningParameters) -> ClinicianReport {
        let peaks = DailyPeaks.compute(hourly: data.hourly, timeZone: timeZone)
        let pollen = ClinicianSummary.pollenPeaks(in: data)
        let summary = ClinicianSummary.make(from: data, timeZone: timeZone, tuning: tuning,
                                            peaks: peaks, pollenByDay: pollen)
        let airByDay = Dictionary(uniqueKeysWithValues: peaks.days.map { ($0.dayKey, $0.peak) })
        let checkInByDay = Dictionary(uniqueKeysWithValues: data.checkIns.map { ($0.day, $0) })
        var weeks: [Week] = []
        var remainingDays = data.days[...]
        while !remainingDays.isEmpty {
            // Anchor the weeks to the end of the period. Only the oldest week can be shorter.
            let remainder = remainingDays.count % 7
            let week = remainingDays.prefix(remainder == 0 ? 7 : remainder)
            guard let first = week.first, let last = week.last else { break }
            let checkIns = week.compactMap { checkInByDay[$0.interval.start] }
            let peakFlows = checkIns.compactMap(\.peakFlowLPM)
            let airPeaks = week.compactMap { airByDay[$0.dayKey] }
            let pollenPeaks = week.compactMap { pollen[$0.interval.start] }
            weeks.append(Week(
                firstDayKey: first.dayKey, lastDayKey: last.dayKey, dayCount: week.count, checkInDays: checkIns.count,
                symptoms: AnsweredDays(checkIns.compactMap(\.daytimeSymptoms)),
                nightWaking: AnsweredDays(checkIns.compactMap(\.nightWaking)),
                rescueInhaler: AnsweredDays(checkIns.compactMap(\.rescueInhalerUses).map { $0 > 0 }),
                peakFlow: peakFlows.min().flatMap { low in peakFlows.max().map { low...$0 } },
                airDays: airPeaks.count, highestAQI: airPeaks.max(), pollenDays: pollenPeaks.count,
                pollenAtLeastModerateDays: pollenPeaks.filter { $0 >= ClinicianSummary.pollenHighIndex }.count))
            remainingDays = remainingDays.dropFirst(week.count)
        }
        return ClinicianReport(summary: summary, weeks: weeks)
    }

    @concurrent
    static func build(from data: ChartData, timeZone: TimeZone, tuning: DetectionTuningParameters) async -> ClinicianReport {
        make(from: data, timeZone: timeZone, tuning: tuning)
    }
}
