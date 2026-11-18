import Foundation
import Observation

/// The last few hours of stored air quality for the dashboard: Google's hourly history plus the
/// WAQI station readings recorded on each app open. Read-only over what's already stored, so it
/// never makes a provider request. The series are shown side by side, never merged: they are
/// different indexes from different sources.
@MainActor @Observable
public final class RecentAirQualityViewModel {
    public static let defaultHours = 48

    public private(set) var hourly: [EnvironmentSeries.AQIPoint] = []
    public private(set) var station: [EnvironmentSeries.AQIPoint] = []
    public private(set) var window: DateInterval
    public private(set) var hasLoaded = false
    public private(set) var errorMessage: String?

    private let records: any EnvironmentSeriesReading
    private let place: RecordPlace?
    private let hours: Int
    private let now: @Sendable () -> Date
    private var loadGeneration = 0

    /// `place` is where the dashboard's reading is from; only records near it are drawn.
    public init(records: any EnvironmentSeriesReading, place: RecordPlace?, hours: Int = defaultHours,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.records = records
        self.place = place
        self.hours = max(1, hours)
        self.now = now
        window = Self.window(endingAt: now(), hours: max(1, hours))
    }

    public var isEmpty: Bool { hourly.isEmpty && station.isEmpty }

    /// The hourly points split into runs of consecutive hours, so a line is never drawn across a
    /// missing hour (missing means unavailable, never an interpolated value).
    public var hourlyRuns: [[EnvironmentSeries.AQIPoint]] {
        var runs: [[EnvironmentSeries.AQIPoint]] = []
        for point in hourly.sorted(by: { $0.date < $1.date }) {
            if let last = runs.last?.last, point.date.timeIntervalSince(last.date) <= 3_600 {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return runs
    }

    /// Lowest and highest value over both series, for a plain range caption. Nil when empty.
    public var valueRange: ClosedRange<Int>? {
        let values = (hourly + station).map(\.value)
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }

    /// The values nearest a touched time: the hourly point within half an hour and the station
    /// reading within 90 minutes (station readings are sparse). Either can be nil.
    public func values(near date: Date) -> (hourly: EnvironmentSeries.AQIPoint?, station: EnvironmentSeries.AQIPoint?) {
        func nearest(_ points: [EnvironmentSeries.AQIPoint], within tolerance: TimeInterval) -> EnvironmentSeries.AQIPoint? {
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                .flatMap { abs($0.date.timeIntervalSince(date)) <= tolerance ? $0 : nil }
        }
        return (nearest(hourly, within: 30 * 60), nearest(station, within: 90 * 60))
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let window = Self.window(endingAt: now(), hours: hours)
        do {
            let series = try await records.environmentSeries(in: window, near: place)
            guard generation == loadGeneration else { return }
            try Task.checkCancellation()
            self.window = window
            hourly = series.hourly
            station = series.waqi.filter { window.contains($0.date) }
            errorMessage = nil
            hasLoaded = true
        } catch {
            guard generation == loadGeneration else { return }
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    /// Ends at the start of the next hour, so the current partial hour's station reading is inside.
    static func window(endingAt date: Date, hours: Int) -> DateInterval {
        let hourSeconds = 3_600.0
        let end = (date.timeIntervalSinceReferenceDate / hourSeconds).rounded(.down) * hourSeconds + hourSeconds
        let endDate = Date(timeIntervalSinceReferenceDate: end)
        return DateInterval(start: endDate.addingTimeInterval(-Double(hours) * hourSeconds), end: endDate)
    }
}
