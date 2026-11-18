import Foundation

public protocol EnvironmentSeriesReading: Sendable {
    /// `place` limits the series to records requested near it; nil means every place.
    func environmentSeries(in interval: DateInterval, near place: RecordPlace?) async throws -> EnvironmentSeries
}

public protocol ChartRecordReading: EnvironmentSeriesReading {
    func dailyRecords() async throws -> [DailyRecordSnapshot]
    func checkInRows() async throws -> [CheckInRow]
    func contextEventRows() async throws -> [ContextEventRow]
}

extension RecordStore: ChartRecordReading {}

extension ChartRecordReading {
    /// The chart series for `domain` from everything stored. The detection store is a separate actor, so its reads
    /// overlap the record-store reads; without one (nil) the detection series stay empty. Candidates below `tuning`'s
    /// threshold are never loaded, since the series threshold anyway.
    func chartData(domain: DateInterval, timeZone: TimeZone, dailyRecords: [DailyRecordSnapshot], checkIns: [CheckInRow],
                   detections: (any DetectionStoring)?, tuning: DetectionTuningParameters,
                   detectionLabel: String, contextRecordedIn: Range<Date>? = nil) async throws -> ChartData {
        async let candidateRead = detections?.candidates(label: detectionLabel, in: domain,
                                                         minimumConfidence: tuning.confidenceThreshold) ?? []
        async let sessionRead = detections?.sessions(in: domain) ?? []
        let environment = try await environmentSeries(in: domain, near: nil)
        let contextRows = try await contextEventRows()
        // An archive may include only part of an edit chain. Resolve the same saved versions as its CSV.
        let contextEvents = ContextEventResolution.resolve(contextRecordedIn.map { range in
            contextRows.filter { range.contains($0.recordedAt) }
        } ?? contextRows)
        let candidates = try await candidateRead
        let sessions = try await sessionRead
        return await ChartSeries.build(domain: domain, timeZone: timeZone, records: dailyRecords, environment: environment,
                                       detections: candidates, sessions: sessions, checkIns: checkIns, tuning: tuning,
                                       detectionLabel: detectionLabel, contextEvents: contextEvents)
    }
}
