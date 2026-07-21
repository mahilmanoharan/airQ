import Foundation

/// A single point-in-time entry the widget can render. Deliberately has no
/// WidgetKit dependency so it (and the scheduling logic below) can be unit
/// tested with Swift Testing without touching `TimelineProvider`/`Timeline<Entry>`.
public struct AQSnapshotEntry: Sendable, Equatable {
    public let date: Date
    public let aqi: Int?
    public let locationName: String
    public let lastUpdated: Date?
    public let hasData: Bool

    public init(date: Date, aqi: Int?, locationName: String, lastUpdated: Date?, hasData: Bool) {
        self.date = date
        self.aqi = aqi
        self.locationName = locationName
        self.lastUpdated = lastUpdated
        self.hasData = hasData
    }
}

public enum TimelineScheduler {
    public static let refreshInterval: TimeInterval = 30 * 60

    /// Builds the entries for a widget timeline from the last known snapshot.
    /// There's only ever one fetch source of truth (the main app), so this
    /// always produces a single "now" entry — either real data or a
    /// no-data placeholder — rather than trying to interpolate future readings.
    public static func makeEntries(from snapshot: AQSnapshot?, currentDate: Date) -> [AQSnapshotEntry] {
        guard let snapshot else {
            return [
                AQSnapshotEntry(
                    date: currentDate,
                    aqi: nil,
                    locationName: "Current Location",
                    lastUpdated: nil,
                    hasData: false
                )
            ]
        }

        return [
            AQSnapshotEntry(
                date: currentDate,
                aqi: snapshot.aqi,
                locationName: snapshot.locationName,
                lastUpdated: snapshot.lastUpdated,
                hasData: true
            )
        ]
    }

    public static func nextRefreshDate(after date: Date) -> Date {
        date.addingTimeInterval(refreshInterval)
    }
}
