import Foundation
import Observation

/// Loads the stored record for an `ExportPeriod` and turns it into a `ClinicianSummary`. It reads only
/// what is already stored; nothing is requested from a provider.
@MainActor @Observable
public final class ClinicianSummaryViewModel {
    public private(set) var summary: ClinicianSummary?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let records: any ChartRecordReading
    private let detections: (any DetectionStoring)?
    private let tuning: @MainActor () -> DetectionTuningParameters
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private var generation = 0

    public init(records: any ChartRecordReading, detections: (any DetectionStoring)?,
                tuning: @escaping @MainActor () -> DetectionTuningParameters, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.records = records
        self.detections = detections
        self.tuning = tuning
        self.timeZone = timeZone
        self.now = now
    }

    /// Whole local days ending with today. "Everything" starts at the first day anything was recorded.
    func domain(for period: ExportPeriod, dailyRecords: [DailyRecordSnapshot], checkIns: [CheckInRow]) -> DateInterval {
        let today = LocalDay(containing: now(), in: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let range = period.range(now: now(), calendar: calendar) {
            return DateInterval(start: LocalDay(containing: range.start, in: timeZone).interval.start, end: today.interval.end)
        }
        let firstKey = (dailyRecords.map(\.dayKey) + checkIns.map(\.draft.dayKey)).min()
        let first = firstKey.flatMap { LocalDay(key: $0, in: timeZone) } ?? today
        return DateInterval(start: min(first.interval.start, today.interval.start), end: today.interval.end)
    }

    /// Limited archives pass the same recorded-at bounds as their CSVs. Report uses the whole-day view.
    public func load(period: ExportPeriod, recordedIn archiveRange: DateInterval? = nil) async {
        generation += 1
        let mine = generation
        summary = nil
        errorMessage = nil
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let dailyRecords = try await records.dailyRecords()
            let checkInRows = try await records.checkInRows()
            let recordedIn = archiveRange.map { $0.start..<$0.end }
            let checkIns = recordedIn.map { range in checkInRows.filter { range.contains($0.recordedAt) } } ?? checkInRows
            let domain = domain(for: period, dailyRecords: dailyRecords, checkIns: checkIns)
            let tuning = tuning()
            let built = try await records.chartData(domain: domain, timeZone: timeZone, dailyRecords: dailyRecords,
                                                    checkIns: checkIns, detections: detections, tuning: tuning,
                                                    detectionLabel: "cough", contextRecordedIn: recordedIn)
            guard mine == generation else { return }
            try Task.checkCancellation()
            summary = ClinicianSummary.make(from: built, timeZone: timeZone, tuning: tuning)
            errorMessage = nil
        } catch {
            guard mine == generation else { return }
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }
}
