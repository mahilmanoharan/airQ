import Foundation
import Observation

@MainActor @Observable
public final class ChartViewModel {
    public typealias Span = HistoryPeriod

    public var span: Span = .month
    public var detectionLabel = "cough"
    public private(set) var data: ChartData?
    /// Check-in days by the day's air band and pollen level, for the span loaded (computed once per load).
    public private(set) var symptomDays: SymptomDaysByLevel?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let records: any ChartRecordReading
    private let detections: (any DetectionStoring)?
    private let tuning: @MainActor () -> DetectionTuningParameters
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    /// Each load supersedes earlier ones: only the newest query's result is applied.
    private var loadGeneration = 0

    /// `detections` is nil when the detection store is unavailable; the other series still draw.
    public init(records: any ChartRecordReading, detections: (any DetectionStoring)?,
                tuning: @escaping @MainActor () -> DetectionTuningParameters, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.records = records
        self.detections = detections
        self.tuning = tuning
        self.timeZone = timeZone
        self.now = now
    }

    /// Whole local days, ending with today.
    public var domain: DateInterval {
        var day = LocalDay(containing: now(), in: timeZone)
        let end = day.interval.end
        for _ in 1..<span.rawValue { day = day.previous }
        return DateInterval(start: day.interval.start, end: end)
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let built = try await records.chartData(domain: domain, timeZone: timeZone,
                                                    dailyRecords: try await records.dailyRecords(),
                                                    checkIns: try await records.checkInRows(), detections: detections,
                                                    tuning: tuning(), detectionLabel: detectionLabel)
            guard generation == loadGeneration else { return }
            try Task.checkCancellation()
            data = built
            symptomDays = SymptomDaysByLevel.make(from: built, timeZone: timeZone)
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }
}
