import Foundation

/// How much history a detection screen queries. Always a bounded range by default: a listening
/// hour stores thousands of windows.
public enum DetectionRange: String, Sendable, CaseIterable, Identifiable {
    case lastDay, lastWeek, lastMonth, all
    public var id: String { rawValue }

    public func interval(endingAt now: Date) -> DateInterval? {
        let day: TimeInterval = 86_400
        switch self {
        case .lastDay: return DateInterval(start: now.addingTimeInterval(-day), end: now.addingTimeInterval(1))
        case .lastWeek: return DateInterval(start: now.addingTimeInterval(-7 * day), end: now.addingTimeInterval(1))
        case .lastMonth: return DateInterval(start: now.addingTimeInterval(-31 * day), end: now.addingTimeInterval(1))
        case .all: return nil
        }
    }
}
