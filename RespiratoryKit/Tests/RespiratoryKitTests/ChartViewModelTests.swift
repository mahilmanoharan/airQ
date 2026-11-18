import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Chart and superseded loads") @MainActor
struct ChartViewModelTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 07:13 PDT

    @Test("The domain is whole local days ending with today")
    func domain() throws {
        let model = ChartViewModel(records: StubChartRecords(), detections: nil, tuning: { .init() },
                                   timeZone: zone, now: { [now] in now })
        model.span = .week
        let today = LocalDay(containing: now, in: zone)
        #expect(model.domain.end == today.interval.end)
        #expect(LocalDay(containing: model.domain.start, in: zone).key == "2026-09-15")
        #expect(model.domain.start == LocalDay(containing: model.domain.start, in: zone).interval.start)
    }

    @Test("Loading builds every series; without a detection store the others still draw")
    func loadsWithoutDetections() async throws {
        let records = StubChartRecords()
        let model = ChartViewModel(records: records, detections: nil, tuning: { .init() }, timeZone: zone,
                                   now: { [now] in now })
        await model.load()
        let data = try #require(model.data)
        #expect(data.days.count == ChartViewModel.Span.month.rawValue)
        #expect(data.waqi.map(\.value) == [42])
        #expect(data.detections.isEmpty)
        #expect(model.errorMessage == nil && !model.isLoading)
    }

    @Test("A storage error is shown")
    func loadError() async {
        let model = ChartViewModel(records: StubChartRecords(fails: true), detections: nil, tuning: { .init() },
                                   timeZone: zone, now: { [now] in now })
        await model.load()
        #expect(model.errorMessage != nil && model.data == nil)
    }

    @Test("A newer chart query keeps its result when the older query finishes")
    func supersededChartLoad() async {
        let store = GatedCandidates(timestamp: now)
        let model = ChartViewModel(records: StubChartRecords(), detections: store, tuning: { .init() },
                                   timeZone: zone, now: { [now] in now })
        let first = Task { await model.load() }
        await store.waitForGatedRequest()

        model.span = .week
        model.detectionLabel = "sneeze"
        await model.load()
        let latest = model.data
        #expect(latest?.days.count == 7)
        #expect(latest?.detectionLabel == "sneeze")
        #expect(latest?.detections.map(\.count) == [1])

        await store.release()
        await first.value
        #expect(model.data == latest)
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test("A newer detection review query keeps its result when the older query finishes")
    func supersededReviewLoad() async {
        let store = GatedCandidates(timestamp: now)
        let model = DetectionReviewViewModel(store: store, appVersion: "t", now: { [now] in now })
        model.threshold = 0
        let first = Task { await model.load() }
        await store.waitForGatedRequest()
        model.label = "sneeze"
        await model.load()
        #expect(model.snapshots.map(\.label) == ["sneeze"])
        await store.release()
        await first.value
        #expect(model.snapshots.map(\.label) == ["sneeze"])
        #expect(!model.isLoading)
    }

    @Test("Default tuning merges a sound reported by two overlapping windows 1.5 s apart")
    func defaultGapCoversWindowHop() {
        let parameters = DetectionTuningParameters()
        let a = DetectionSnapshot(id: UUID(), timestamp: now, label: "cough", confidence: 0.8, isFalsePositive: false)
        let b = DetectionSnapshot(id: UUID(), timestamp: now.addingTimeInterval(1.5), label: "cough", confidence: 0.7,
                                  isFalsePositive: false)
        #expect(DetectionAnalysis.debounce([a, b], minInterEventGap: parameters.minInterEventGap).count == 1)
    }
}

private struct StubChartRecords: ChartRecordReading {
    var fails = false
    struct Failure: Error {}
    func dailyRecords() async throws -> [DailyRecordSnapshot] {
        if fails { throw Failure() }
        return []
    }
    func environmentSeries(in interval: DateInterval, near place: RecordPlace?) async throws -> EnvironmentSeries {
        EnvironmentSeries(waqi: [.init(date: interval.end.addingTimeInterval(-3_600), value: 42, source: "waqi")],
                          hourly: [], pollen: [], successDayKeys: [])
    }
    func checkInRows() async throws -> [CheckInRow] { [] }
    func contextEventRows() async throws -> [ContextEventRow] { [] }
}

/// The first "cough" query waits until released; any other label answers immediately.
private actor GatedCandidates: DetectionStoring {
    private let timestamp: Date
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var gated = false

    init(timestamp: Date) {
        self.timestamp = timestamp
    }

    func candidates(label: String, in interval: DateInterval?, minimumConfidence: Double) async throws -> [DetectionSnapshot] {
        if label == "cough" && !gated {
            gated = true
            await withCheckedContinuation { gate = $0; arrival?.resume(); arrival = nil }
        }
        return [DetectionSnapshot(id: UUID(), timestamp: timestamp, label: label, confidence: 0.9, isFalsePositive: false)]
    }
    func waitForGatedRequest() async {
        if gate != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func release() { gate?.resume(); gate = nil }
    func beginIngest(_ info: CaptureSessionInfo, appVersion: String, events: AsyncThrowingStream<CaptureEvent, any Error>,
                     stopRequest: ListeningStopRequest,
                     stopCapture: @escaping @Sendable () async -> Void) -> Task<IngestOutcome, Never> {
        Task { IngestOutcome(windowCount: 0, endReason: .userStopped, failure: nil) }
    }
    func sessions(in interval: DateInterval?) throws -> [ListeningSessionSnapshot] { [] }
    func annotate(_ target: DetectionSnapshot, verdict: AnnotationVerdict, source: String, note: String?,
                  at date: Date, appVersion: String) throws {}
}
