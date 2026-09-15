import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Respiratory view models") @MainActor
struct ViewModelTests {
    @Test("Listening guards pending starts and cancellation stops its session")
    func listeningLifecycle() async {
        let audio = TestAudio()
        let model = ListenViewModel(controller: audio, store: TestDetectionStore(), appVersion: "test")
        let task = Task { await model.listen() }
        await audio.waitForStart()
        await model.listen()
        #expect(await audio.starts == 1)
        task.cancel()
        await task.value
        #expect(model.phase == .idle)
        #expect(model.errorMessage == nil)
        #expect(await audio.stops == 1)
    }

    @Test("Raw low-confidence events persist while the display is bounded")
    func rawPersistence() async {
        let audio = TestAudio()
        let store = TestDetectionStore()
        let model = ListenViewModel(controller: audio, store: store, appVersion: "test", displayLimit: 2)
        let task = Task { await model.listen() }
        await audio.waitForStart()
        await audio.emit([
            RawDetection(label: "cough", confidence: 0.01, timestamp: .now),
            RawDetection(label: "speech", confidence: 0.9, timestamp: .now),
            RawDetection(label: "cough", confidence: 0.9, timestamp: .now)
        ])
        await task.value
        #expect(model.detections.count == 2)
        #expect(await store.recordedConfidences == [0.01, 0.9])
        #expect(await store.configs.allSatisfy { $0.appVersion == "test" && $0.windowDuration == 1 })
    }

    @Test("Persistence and analyzer failures are surfaced, not swallowed")
    func listeningErrors() async {
        for failSaving in [true, false] {
            let audio = TestAudio()
            let model = ListenViewModel(controller: audio, store: TestDetectionStore(fails: failSaving), appVersion: "test")
            let task = Task { await model.listen() }
            await audio.waitForStart()
            if failSaving {
                await audio.emit([RawDetection(label: "cough", confidence: 0.2, timestamp: .now)])
            } else {
                await audio.fail()
            }
            await task.value
            #expect(model.errorMessage != nil)
            #expect(model.phase == .idle)
        }
    }

    @Test("Retuning derives new counts without changing raw history")
    func tuning() async {
        let store = TestDetectionStore(snapshots: [event(confidence: 0.1), event(confidence: 0.9)])
        let model = DetectionTuningViewModel(store: store)
        await model.load()
        #expect(model.filteredEvents.count == 1)
        model.parameters.confidenceThreshold = 0
        #expect(model.filteredEvents.count == 2)
        #expect(model.snapshots.count == 2)
        #expect(await store.recordedConfidences.isEmpty)
    }

    @Test("Review fetches a bounded newest-first history and updates one annotation")
    func review() async throws {
        let store = TestDetectionStore(snapshots: [event(confidence: 0.8)])
        let model = DetectionReviewViewModel(store: store)
        await model.load()
        #expect(await store.requestedLimit == 500)
        let snapshot = try #require(model.snapshots.first)
        await model.toggleFalsePositive(snapshot)
        #expect(model.snapshots.first?.isFalsePositive == true)
        #expect(await store.fetches == 1)
        await model.load(allHistory: true)
        #expect(await store.requestedLimit == nil)
        #expect(model.isShowingAllHistory)
    }

    @Test("Both history screens expose storage errors")
    func loadErrors() async {
        let store = TestDetectionStore(fails: true)
        let tuning = DetectionTuningViewModel(store: store)
        let review = DetectionReviewViewModel(store: store)
        await tuning.load()
        await review.load()
        #expect(tuning.errorMessage != nil)
        #expect(review.errorMessage != nil)
        #expect(!tuning.isLoading && !review.isLoading)
    }

    private func event(confidence: Double) -> DetectionSnapshot {
        DetectionSnapshot(id: UUID(), timestamp: .now, label: "cough", confidence: confidence, isFalsePositive: false)
    }
}

private enum FixtureError: Error { case failed }

private actor TestAudio: AudioAnalyzing {
    var starts = 0
    var stops = 0
    private let pair = AsyncThrowingStream<RawDetection, any Error>.makeStream()
    private var started: CheckedContinuation<Void, Never>?

    func start() async throws -> AudioAnalysisSession {
        starts += 1
        started?.resume()
        started = nil
        return AudioAnalysisSession(sessionID: UUID(), stream: pair.stream,
                                    config: SessionAudioConfig(windowDuration: 1, overlapFactor: 0.5, classifierIdentifier: "version1"))
    }
    func stop() async { stops += 1; pair.continuation.finish() }
    func waitForStart() async {
        if starts > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func emit(_ detections: [RawDetection]) {
        for detection in detections { pair.continuation.yield(detection) }
        pair.continuation.finish()
    }
    func fail() { pair.continuation.finish(throwing: FixtureError.failed) }
}

private actor TestDetectionStore: DetectionStoring {
    var recordedConfidences: [Double] = []
    var configs: [DetectionConfig] = []
    var requestedLimit: Int?
    var fetches = 0
    let snapshots: [DetectionSnapshot]
    let fails: Bool
    init(snapshots: [DetectionSnapshot] = [], fails: Bool = false) {
        self.snapshots = snapshots
        self.fails = fails
    }
    func record(sessionID: UUID, label: String, confidence: Double, timestamp: Date, config: DetectionConfig) throws {
        if fails { throw FixtureError.failed }
        recordedConfidences.append(confidence)
        configs.append(config)
    }
    func fetchSnapshots(limit: Int?, newestFirst: Bool) throws -> [DetectionSnapshot] {
        if fails { throw FixtureError.failed }
        requestedLimit = limit
        fetches += 1
        return snapshots
    }
    func setFalsePositive(_ id: UUID, isFalsePositive: Bool) throws {
        if fails { throw FixtureError.failed }
    }
}
