import Foundation

public enum CheckInAnalysis {
    public enum Timing: Sendable, Equatable {
        /// Recorded during the day it describes.
        case sameDay
        /// Recorded this many local days after the day it describes.
        case backfilled(days: Int)
        /// Recorded before the day began (e.g. a clock or zone change).
        case early
    }

    /// Latest check-in per day (append-only rows; re-saving adds a row).
    public static func latestPerDay(_ rows: [CheckInRow]) -> [String: CheckInRow] {
        Dictionary(grouping: rows, by: \.draft.dayKey).compactMapValues { group in
            group.max { ($0.recordedAt, $0.id.uuidString) < ($1.recordedAt, $1.id.uuidString) }
        }
    }

    /// Derived from the stored raw times, never stored. Uses the zone the row was recorded in.
    public static func timing(of row: CheckInRow) -> Timing? {
        guard let zone = TimeZone(identifier: row.recordedTimeZoneID),
              let day = LocalDay(key: row.draft.dayKey, in: zone) else { return nil }
        if day.contains(row.recordedAt) { return .sameDay }
        if row.recordedAt < day.interval.start { return .early }
        var lateness = 0
        var cursor = day
        while !cursor.contains(row.recordedAt), lateness < 3_660 {
            cursor = cursor.next
            lateness += 1
        }
        return .backfilled(days: lateness)
    }

    /// Days with at least one check-in divided by collection days from the first recorded day
    /// through `now`: a derived logging-compliance ratio, nil before any day was recorded.
    public static func compliance(checkInDays: Set<String>, records: [DailyRecordSnapshot], through now: Date,
                                  in timeZone: TimeZone) -> (checkedIn: Int, days: Int)? {
        let days = RecordCoverage.days(records: records, through: now, in: timeZone)
        guard !days.isEmpty else { return nil }
        return (days.count(where: { checkInDays.contains($0.dayKey) }), days.count)
    }
}
