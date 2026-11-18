import Foundation

/// A plain, factual recap of a period for someone else to read (for example at an appointment):
/// counts of what the person recorded and what the air was, side by side. Every figure is a read-time
/// count over stored observations; there are no scores, trends, comparisons or interpretations, and it
/// says what each number is and isn't.
public struct ClinicianSummary: Sendable, Equatable {
    public struct AirDays: Sendable, Equatable {
        public var good = 0, moderate = 0, sensitive = 0, unhealthy = 0
        public var reported: Int { good + moderate + sensitive + unhealthy }
    }

    public let firstDayKey: String
    public let lastDayKey: String
    public let dayCount: Int
    public let checkInDays: Int
    /// Days whose check-in answered the daytime-symptoms question.
    public let symptomAnswered: Int
    public let symptomDays: Int
    public let mildDays: Int, moderateDays: Int, severeDays: Int
    public let nightWakingAnswered: Int
    public let nightWakingDays: Int
    public let rescueAnswered: Int
    public let rescueUses: Int
    public let rescueDays: Int
    /// Controller-medication answers by `CheckInQuestionSet.ControllerAdherence` raw value.
    public let adherence: [String: Int]
    /// Days with a saved peak-flow reading, and the lowest and highest of them (L/min).
    public let peakFlowReadings: Int
    public let peakFlowLowest: Int?
    public let peakFlowHighest: Int?
    public let air: AirDays
    public let airPartialDays: Int
    public let airCoverage: AirCoverage
    public let worstAirDay: DayPeak?
    public let pollenDays: Int
    public let pollenHighDays: Int
    /// Checked-in days by that day's air band and pollen level, with the symptom days among them.
    public let symptomDaysByLevel: SymptomDaysByLevel
    /// Life events the person noted that overlap the period, oldest first.
    public struct LifeEvent: Sendable, Equatable {
        public let title: String
        public let note: String
        public let firstDayKey: String
        /// Nil when the event is still ongoing.
        public let lastDayKey: String?
    }
    public let lifeEvents: [LifeEvent]
    public let coughEvents: Int
    public let listeningSeconds: TimeInterval
    public let detectionLabel: String
    public let confidenceThreshold: Double
    public let minInterEventGap: TimeInterval

    /// Pollen index at or above which a day counts as "high" here (Google's index: 3 = Moderate).
    public static let pollenHighIndex = 3
    static let lifeEventLimit = 12

    public static func make(from data: ChartData, timeZone: TimeZone, tuning: DetectionTuningParameters) -> ClinicianSummary {
        let first = data.days.first?.dayKey ?? ""
        let last = data.days.last?.dayKey ?? ""

        let checkIns = data.checkIns
        let symptomAnswers = checkIns.compactMap(\.daytimeSymptoms)
        let nightAnswers = checkIns.compactMap(\.nightWaking)
        let rescue = checkIns.compactMap(\.rescueInhalerUses)
        let peakFlows = checkIns.compactMap(\.peakFlowLPM)
        var adherence: [String: Int] = [:]
        for answer in checkIns.compactMap(\.controllerAdherence) { adherence[answer, default: 0] += 1 }

        // Air: each whole day in the category of its highest hourly value, days with too few hours left out.
        let peaks = DailyPeaks.compute(hourly: data.hourly, timeZone: timeZone)
        var air = AirDays()
        for day in peaks.days {
            switch AirQualityBand.of(day.peak) {
            case .good: air.good += 1
            case .moderate: air.moderate += 1
            case .sensitive: air.sensitive += 1
            case .unhealthy: air.unhealthy += 1
            }
        }

        // Pollen: the highest type index of each day's latest forecast.
        var pollenByDay: [Date: Int] = [:]
        for bar in data.pollen { pollenByDay[bar.day] = max(pollenByDay[bar.day] ?? 0, bar.upi) }

        let lifeEvents = data.context.map { span -> LifeEvent in
            let first = span.originalStartDayKey ?? LocalDay(containing: span.start, in: timeZone).key
            let last = span.originalEndDayKey ?? span.originalStartDayKey
                ?? LocalDay(containing: span.end.addingTimeInterval(-1), in: timeZone).key
            return LifeEvent(title: ContextEventCategory(rawValue: span.category)?.title ?? span.category, note: span.note,
                             firstDayKey: first,
                             lastDayKey: span.isOngoing ? nil : last)
        }.sorted { ($0.firstDayKey, $0.title) < ($1.firstDayKey, $1.title) }

        return ClinicianSummary(
            firstDayKey: first, lastDayKey: last, dayCount: data.days.count,
            checkInDays: checkIns.count,
            symptomAnswered: symptomAnswers.count, symptomDays: symptomAnswers.filter { $0 }.count,
            mildDays: checkIns.filter { $0.severity == 1 }.count,
            moderateDays: checkIns.filter { $0.severity == 2 }.count,
            severeDays: checkIns.filter { $0.severity == 3 }.count,
            nightWakingAnswered: nightAnswers.count, nightWakingDays: nightAnswers.filter { $0 }.count,
            rescueAnswered: rescue.count, rescueUses: rescue.reduce(0, +), rescueDays: rescue.filter { $0 > 0 }.count,
            adherence: adherence, peakFlowReadings: peakFlows.count, peakFlowLowest: peakFlows.min(),
            peakFlowHighest: peakFlows.max(), air: air, airPartialDays: peaks.partialDays,
            airCoverage: data.airCoverage ?? AirCoverage.resolve(data.hourly).coverage,
            worstAirDay: peaks.days.max { ($0.peak, $1.dayKey) < ($1.peak, $0.dayKey) },
            pollenDays: pollenByDay.count, pollenHighDays: pollenByDay.values.filter { $0 >= pollenHighIndex }.count,
            symptomDaysByLevel: SymptomDaysByLevel.make(from: data, timeZone: timeZone),
            lifeEvents: lifeEvents, coughEvents: data.detections.reduce(0) { $0 + $1.count },
            listeningSeconds: data.detections.reduce(0) { $0 + $1.listeningSeconds },
            detectionLabel: data.detectionLabel, confidenceThreshold: tuning.confidenceThreshold,
            minInterEventGap: tuning.minInterEventGap)
    }

    /// The summary as plain text that reads the same in a message, a note or a printout.
    public var text: String {
        func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }
        var lines = ["airQ summary, \(firstDayKey) to \(lastDayKey) (\(days(dayCount)))", ""]

        lines.append("Recorded by the person")
        lines.append("- Check-ins: \(checkInDays) of \(dayCount) days.")
        if checkInDays > 0 {
            if symptomAnswered > 0 {
                var line = "- Daytime symptoms: \(symptomDays) of \(symptomAnswered) answered days"
                if symptomDays > 0 {
                    line += " (mild \(mildDays), moderate \(moderateDays), severe \(severeDays))"
                }
                lines.append(line + ".")
            }
            if nightWakingAnswered > 0 { lines.append("- Woke at night with symptoms: \(nightWakingDays) of \(nightWakingAnswered) answered days.") }
            if rescueAnswered > 0 {
                lines.append("- Rescue inhaler: \(rescueUses) uses in total; used on \(rescueDays) of \(rescueAnswered) answered days.")
            }
            if let low = peakFlowLowest, let high = peakFlowHighest {
                lines.append("- Peak flow (own meter): \(peakFlowReadings) readings, lowest \(low), highest \(high) L/min.")
            }
            let taken = adherence.values.reduce(0, +)
            if taken > 0 {
                let parts = CheckInQuestionSet.ControllerAdherence.allCases.compactMap { option -> String? in
                    guard let count = adherence[option.rawValue], count > 0 else { return nil }
                    return "\(Self.adherenceWords[option] ?? option.rawValue) \(count)"
                }
                lines.append("- Controller medication as prescribed: \(parts.joined(separator: ", ")) (of \(taken) answered days).")
            }
        }

        if !lifeEvents.isEmpty {
            lines.append("")
            lines.append("Life events the person noted")
            for event in lifeEvents.prefix(Self.lifeEventLimit) {
                let when = event.lastDayKey == nil ? "\(event.firstDayKey), ongoing"
                    : event.lastDayKey == event.firstDayKey ? event.firstDayKey : "\(event.firstDayKey) to \(event.lastDayKey ?? "")"
                lines.append("- \(when): \(event.title)" + (event.note.isEmpty ? "" : " (\(event.note))"))
            }
            if lifeEvents.count > Self.lifeEventLimit { lines.append("- and \(lifeEvents.count - Self.lifeEventLimit) more.") }
        }

        lines.append("")
        lines.append("Air history for saved places (Google Air Quality hourly index, US AQI)")
        if airCoverage.storedHours > 0 {
            let areas = airCoverage.places.count
            lines.append("- \(airCoverage.storedHours) stored hours across \(areas) saved \(areas == 1 ? "area" : "areas").")
            if airCoverage.ambiguousHours > 0 {
                lines.append("- \(airCoverage.ambiguousHours) overlapping hours have different or uncertain places and are left out.")
            }
            if airCoverage.unknownPlaceHours > 0 {
                lines.append("- \(airCoverage.unknownPlaceHours) stored hours include records without a saved place.")
            }
        }
        if air.reported == 0 {
            lines.append("- No day has enough stored hours to report.")
        } else {
            lines.append("- \(days(air.reported)) reported, each by its highest hour: Good \(air.good), Moderate \(air.moderate), "
                         + "Unhealthy for sensitive groups \(air.sensitive), Unhealthy or worse \(air.unhealthy).")
            if let worst = worstAirDay { lines.append("- Highest hour on any day: AQI \(worst.peak) on \(worst.dayKey).") }
        }
        if airPartialDays > 0 { lines.append("- \(days(airPartialDays)) had too few stored hours and are left out.") }
        lines.append(pollenDays == 0
                     ? "- Pollen forecast: none stored."
                     : "- Pollen forecast (Google index 0–5): \(pollenHighDays) of \(pollenDays) days at index \(Self.pollenHighIndex) or higher.")
        if pollenDays > 0 { lines.append("- Pollen uses the forecast date; older entries without a date use the local request day.") }

        if !symptomDaysByLevel.isEmpty {
            lines.append("")
            lines.append("Daytime symptoms by that day's air and pollen (checked-in days only)")
            for row in symptomDaysByLevel.air {
                lines.append("- Air \(Self.bandWords[row.level] ?? ""): symptoms on \(row.symptomDays) of \(days(row.days)).")
            }
            for row in symptomDaysByLevel.pollen {
                lines.append("- Pollen index \(row.level): symptoms on \(row.symptomDays) of \(days(row.days)).")
            }
            lines.append("- Side-by-side counts only: they don't show that the air or pollen caused the symptoms.")
        }

        lines.append("")
        lines.append("Cough sounds heard by the phone")
        if listeningSeconds <= 0 {
            lines.append("- The phone was not listening in this period.")
        } else {
            let hours = listeningSeconds / 3_600
            lines.append("- \(coughEvents) \(detectionLabel) sounds in \(hours.formatted(.number.precision(.fractionLength(1)))) hours of listening.")
        }

        lines.append("")
        lines.append("What these numbers are")
        lines.append("- Check-in answers are the person's own. Days without a check-in are unknown, not zero.")
        lines.append("- Sounds are found by Apple's on-device sound classifier (score at least "
                     + "\(confidenceThreshold.formatted(.percent.precision(.fractionLength(0)))), repeats within "
                     + "\(minInterEventGap.formatted(.number.precision(.fractionLength(0...1)))) s merged). It can't tell who made "
                     + "a sound, and other people, TV and music can be counted. Listening time varies, so compare rates only "
                     + "with the listening time beside them.")
        lines.append("- Air histories describe saved request locations, including hours before the request. They do not establish where the person was or measure what they breathed.")
        lines.append("- Counts are not a diagnosis or a measure of lung function.")
        return lines.joined(separator: "\n")
    }

    private static let bandWords: [AirQualityBand: String] = [
        .good: "good", .moderate: "moderate", .sensitive: "unhealthy for sensitive groups", .unhealthy: "unhealthy or worse",
    ]

    private static let adherenceWords: [CheckInQuestionSet.ControllerAdherence: String] = [
        .yes: "yes", .partly: "partly", .no: "no", .notPrescribed: "none prescribed",
    ]
}
