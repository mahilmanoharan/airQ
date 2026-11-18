import Foundation
import SwiftData

public enum ChartSeries {
    /// Builds the chart off the caller's actor. Days are local to `timeZone`; per-day counts sum to
    /// the total because days tile exactly (see `LocalDay`).
    @concurrent
    public static func build(domain: DateInterval, timeZone: TimeZone, records: [DailyRecordSnapshot],
                             environment: EnvironmentSeries, detections: [DetectionSnapshot],
                             sessions: [ListeningSessionSnapshot], checkIns: [CheckInRow],
                             tuning: DetectionTuningParameters, detectionLabel: String,
                             contextEvents: [ContextEventSnapshot] = []) async -> ChartData {
        make(domain: domain, timeZone: timeZone, records: records, environment: environment, detections: detections,
             sessions: sessions, checkIns: checkIns, tuning: tuning, detectionLabel: detectionLabel,
             contextEvents: contextEvents)
    }

    public static func make(domain: DateInterval, timeZone: TimeZone, records: [DailyRecordSnapshot],
                            environment: EnvironmentSeries, detections: [DetectionSnapshot],
                            sessions: [ListeningSessionSnapshot], checkIns: [CheckInRow],
                            tuning: DetectionTuningParameters, detectionLabel: String,
                            contextEvents: [ContextEventSnapshot] = []) -> ChartData {
        var localDays: [LocalDay] = []
        var cursor = LocalDay(containing: domain.start, in: timeZone)
        while cursor.interval.start < domain.end, localDays.count < 3_660 {
            localDays.append(cursor)
            cursor = cursor.next
        }
        let recorded = Set(records.map(\.dayKey))
        let days = localDays.map { day in
            let status: ChartData.DayStatus = !recorded.contains(day.key) ? .notCollected
                : environment.successDayKeys.contains(day.key) ? .collected : .collectedNoData
            return ChartData.Day(dayKey: day.key, interval: day.interval, status: status)
        }
        func dayStart(_ date: Date) -> Date { LocalDay(containing: date, in: timeZone).interval.start }

        // The provider's date is a calendar label, not an instant to shift through a time zone.
        // Only legacy rows with no date use the local request day; malformed dates are skipped.
        let datedPollen = environment.pollen.compactMap { reading -> (Date, EnvironmentSeries.PollenReading)? in
            let day: Date
            if let key = reading.forecastDate {
                guard let forecastDay = LocalDay(key: key, in: timeZone) else { return nil }
                day = forecastDay.interval.start
            } else { day = dayStart(reading.requestedAt) }
            guard day >= domain.start && day < domain.end else { return nil }
            return (day, reading)
        }
        let pollenByDay = Dictionary(grouping: datedPollen, by: { $0.0 }).mapValues { $0.map(\.1) }
        let pollen = pollenByDay.flatMap { day, readings -> [ChartData.PollenBar] in
            guard let latest = readings.map(\.requestedAt).max() else { return [] }
            return readings.filter { $0.requestedAt == latest }.map { .init(day: day, code: $0.code, upi: $0.upi) }
        }
        .sorted { ($0.day, $0.code) < ($1.day, $1.code) }

        let filtered = DetectionAnalysis.filterByThreshold(detections, threshold: tuning.confidenceThreshold)
        let events = DetectionAnalysis.debounce(filtered, minInterEventGap: tuning.minInterEventGap)
        let eventCounts = Dictionary(grouping: events) { dayStart($0.timestamp) }.mapValues(\.count)
        var listening: [Date: TimeInterval] = [:]
        for session in sessions {
            // Split each session across the local days it spans.
            var start = session.startedAt
            let end = session.knownEnd
            while start < end {
                let day = LocalDay(containing: start, in: timeZone)
                let sliceEnd = min(end, day.interval.end)
                listening[day.interval.start, default: 0] += sliceEnd.timeIntervalSince(start)
                start = sliceEnd
            }
        }
        let detectionDays = Set(eventCounts.keys).union(listening.keys)
        let detectionBars = detectionDays.filter { $0 >= domain.start && $0 < domain.end }
            .sorted()
            .map { ChartData.DetectionBar(day: $0, count: eventCounts[$0] ?? 0, listeningSeconds: listening[$0] ?? 0) }

        let checkInPoints = CheckInAnalysis.latestPerDay(checkIns).values.compactMap { row -> ChartData.CheckInPoint? in
            guard let day = LocalDay(key: row.draft.dayKey, in: timeZone), day.interval.start >= domain.start,
                  day.interval.start < domain.end else { return nil }
            let severity: Int? = switch row.draft.daytimeSymptoms {
            case false?: 0
            case true?: row.draft.daytimeSeverity
            case nil: nil
            }
            return .init(day: day.interval.start, severity: severity, daytimeSymptoms: row.draft.daytimeSymptoms,
                         nightWaking: row.draft.nightWaking, rescueInhalerUses: row.draft.rescueInhalerUses,
                         controllerAdherence: row.draft.controllerAdherence, peakFlowLPM: row.draft.peakFlowLPM)
        }
        .sorted { $0.day < $1.day }

        let air = AirCoverage.resolve(environment.hourly.filter { $0.date >= domain.start && $0.date < domain.end })
        let hasListeningSessions = sessions.contains { session in
            session.startedAt < domain.end && (session.startedAt >= domain.start || session.knownEnd > domain.start)
        }
        return ChartData(domain: domain, days: days,
                         waqi: environment.waqi.filter { domain.contains($0.date) },
                         hourly: air.points,
                         pollen: pollen, detections: detectionBars, checkIns: checkInPoints,
                         context: contextSpans(contextEvents, domain: domain, timeZone: timeZone),
                         detectionLabel: detectionLabel,
                         hourOfDay: hourOfDay(eventTimes: events.map(\.timestamp), sessions: sessions, domain: domain, timeZone: timeZone),
                         airCoverage: air.coverage, hasListeningSessions: hasListeningSessions)
    }

    /// Events and listening time by local hour of day. A session is split at every local hour
    /// boundary (so a 23:40–00:20 session is credited to both hours) and clipped to the domain.
    static func hourOfDay(eventTimes: [Date], sessions: [ListeningSessionSnapshot], domain: DateInterval,
                          timeZone: TimeZone) -> [ChartData.HourBin] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var counts = [Int](repeating: 0, count: 24)
        var seconds = [TimeInterval](repeating: 0, count: 24)
        for time in eventTimes where domain.contains(time) {
            counts[calendar.component(.hour, from: time)] += 1
        }
        for session in sessions {
            var cursor = max(session.startedAt, domain.start)
            let end = min(session.knownEnd, domain.end)
            while cursor < end {
                guard let block = calendar.dateInterval(of: .hour, for: cursor), block.end > cursor else { break }
                let sliceEnd = min(end, block.end)
                seconds[calendar.component(.hour, from: cursor)] += sliceEnd.timeIntervalSince(cursor)
                cursor = sliceEnd
            }
        }
        return (0..<24).map { .init(hour: $0, count: counts[$0], listeningSeconds: seconds[$0]) }
    }

    /// Retracted events are left out; day keys that don't parse are skipped rather than guessed.
    static func contextSpans(_ events: [ContextEventSnapshot], domain: DateInterval,
                             timeZone: TimeZone) -> [ChartData.ContextSpan] {
        events.compactMap { event -> ChartData.ContextSpan? in
            guard !event.isRetracted, let first = LocalDay(key: event.draft.startDayKey, in: timeZone) else { return nil }
            let ongoing = event.draft.endDayKey == nil
                && ContextEventCategory(rawValue: event.draft.category)?.isOpenEndedWithoutEndDate == true
            let end: Date
            if let endKey = event.draft.endDayKey {
                guard let last = LocalDay(key: endKey, in: timeZone) else { return nil }
                end = last.interval.end
            } else {
                end = ongoing ? max(domain.end, first.interval.end) : first.interval.end
            }
            let start = max(first.interval.start, domain.start)
            let clippedEnd = min(end, domain.end)
            guard start < clippedEnd else { return nil }
            return .init(id: event.originalID, category: event.draft.category, note: event.draft.note,
                         start: start, end: clippedEnd, isOngoing: ongoing,
                         originalStartDayKey: event.draft.startDayKey, originalEndDayKey: event.draft.endDayKey)
        }
        .sorted { ($0.start, $0.category) < ($1.start, $1.category) }
    }
}
