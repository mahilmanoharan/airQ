import Foundation

/// How much history an export covers. Everything is the default because an export is also the
/// only backup besides a device backup; a shorter period is for sharing, e.g. with a clinician.
public enum ExportPeriod: String, CaseIterable, Identifiable, Sendable {
    case everything, last90, last30, last7

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .everything: "Everything"
        case .last90: "Last 90 days"
        case .last30: "Last 30 days"
        case .last7: "Last 7 days"
        }
    }

    /// From the start of the local day `days - 1` days before today, to just after `now` (so a row
    /// recorded this instant is inside). Days are counted on the calendar, not as 24-hour blocks,
    /// so a daylight-saving change can't shift the start off midnight. Nil means no limit.
    public func range(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        let days: Int
        switch self {
        case .everything: return nil
        case .last90: days = 90
        case .last30: days = 30
        case .last7: days = 7
        }
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else { return nil }
        return DateInterval(start: start, end: now.addingTimeInterval(60))
    }
}
