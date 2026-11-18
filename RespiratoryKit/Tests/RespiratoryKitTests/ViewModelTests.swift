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
        #expect(await audio.stops >= 1)
    }

    @Test("Every window is persisted while the display is bounded, and stop reasons are recorded")
    func rawPersistence() async {
        let audio = TestAudio()
        let store = TestDetectionStore()
        let model = ListenViewModel(controller: audio, store: store, appVersion: "test", displayLimit: 2)
        let task = Task { await model.listen() }
        await audio.waitForStart()
        model.requestStop(.userStopped)
        await audio.emit((0..<3).map { window($0) })
        await task.value
        #expect(model.windows.count == 2 && model.windowCount == 3)
        #expect(await store.ingested == 3)
        #expect(model.lastOutcome?.endReason == .userStopped)
        #expect(await store.appVersions == ["test"])
    }

    @Test("Cancelling without a reason records navigating away, after the drain completes")
    func cancellationReason() async {
        let audio = TestAudio()
        let store = TestDetectionStore()
        let model = ListenViewModel(controller: audio, store: store, appVersion: "test")
        let task = Task { await model.listen() }
        await audio.waitForStart()
        await audio.emit([window(0)], finish: false)
        task.cancel()
        await task.value
        #expect(model.lastOutcome?.endReason == .navigatedAway)
        #expect(await store.ingested == 1)
    }

    @Test("Cancellation during the ingest handoff stops capture while the store is still waiting")
    func cancellationDuringIngestHandoff() async {
        let audio = TestAudio()
        let handoff = IngestHandoff()
        let store = TestDetectionStore(handoff: handoff)
        let model = ListenViewModel(controller: audio, store: store, appVersion: "test")
        let task = Task { await model.listen() }
        for await _ in handoff.entered.stream {}
        await audio.emit([window(0)], finish: false)
        model.requestStop(.backgrounded)
        task.cancel()

        let stoppedBeforeHandoff = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var stops = audio.stopNotifications.stream.makeAsyncIterator()
                return await stops.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return false
            }
            let stopped = await group.next() ?? false
            group.cancelAll()
            return stopped
        }
        handoff.release.continuation.finish()
        await task.value

        #expect(stoppedBeforeHandoff)
        #expect(model.lastOutcome == IngestOutcome(windowCount: 1, endReason: .backgrounded, failure: nil))
        #expect(model.phase == .idle)
    }

    @Test("A start rejected by the controller leaves the other listener's capture alone")
    func rejectedStartLeavesCaptureAlone() async {
        let permission = PermissionGate()
        let controller = AudioAnalysisController(requestPermission: { await permission.request() })
        let owner = Task { try await controller.start() }
        await permission.waitForRequest()
        let model = ListenViewModel(controller: controller, store: TestDetectionStore(), appVersion: "test")
        await model.listen()
        await permission.resolve(false)

        await #expect(throws: AudioAnalysisError.microphonePermissionDenied) { try await owner.value }
        #expect(model.phase == .idle)
        #expect(model.errorMessage == AudioAnalysisError.sessionAlreadyActive.errorDescription)
    }

    @Test("Persistence and analyzer failures are surfaced, not swallowed")
    func listeningErrors() async {
        for failSaving in [true, false] {
            let audio = TestAudio()
            let model = ListenViewModel(controller: audio, store: TestDetectionStore(fails: failSaving), appVersion: "test")
            let task = Task { await model.listen() }
            await audio.waitForStart()
            if failSaving {
                await audio.emit([window(0)])
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
        #expect(await store.verdicts.isEmpty)
    }

    @Test("Review shows candidates above the threshold newest first, and toggles verdicts as annotations")
    func review() async throws {
        let store = TestDetectionStore(snapshots: [event(confidence: 0.8, offset: 0), event(confidence: 0.2, offset: 1),
                                                   event(confidence: 0.6, offset: 2)])
        let model = DetectionReviewViewModel(store: store, appVersion: "test")
        await model.load()
        #expect(model.snapshots.map(\.confidence) == [0.6, 0.8])
        let snapshot = try #require(model.snapshots.first)
        await model.toggle(.falsePositive, for: snapshot)
        #expect(model.snapshots.first?.isFalsePositive == true)
        await model.toggle(.falsePositive, for: snapshot)
        #expect(model.snapshots.first?.verdict == nil)
        #expect(await store.verdicts == [.falsePositive, .cleared])
        #expect(await store.fetches == 1)
    }

    @Test("Both history screens expose storage errors")
    func loadErrors() async {
        let store = TestDetectionStore(fails: true)
        let tuning = DetectionTuningViewModel(store: store)
        let review = DetectionReviewViewModel(store: store, appVersion: "test")
        await tuning.load()
        await review.load()
        #expect(tuning.errorMessage != nil)
        #expect(review.errorMessage != nil)
        #expect(!tuning.isLoading && !review.isLoading)
    }

    private func event(confidence: Double, offset: TimeInterval = 0) -> DetectionSnapshot {
        DetectionSnapshot(id: UUID(), timestamp: Date(timeIntervalSince1970: 1_790_000_000 + offset), label: "cough",
                          confidence: confidence, isFalsePositive: false)
    }

    private func window(_ index: Int) -> WindowObservation {
        WindowObservation(windowIndex: index, startFrame: Int64(index) * 8_000, durationFrames: 16_000,
                          deliveredAt: .now, scores: [0.01], topLabels: ["speech"], topScores: [0.9], rms: nil, peak: nil)
    }
}

private enum FixtureError: Error { case failed }

private struct IngestHandoff: Sendable {
    let entered = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
}

private actor TestAudio: AudioAnalyzing {
    var starts = 0
    var stops = 0
    let stopNotifications = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let events = AsyncThrowingStream<CaptureEvent, any Error>.makeStream()
    private let display = AsyncStream<WindowObservation>.makeStream()
    private var started: CheckedContinuation<Void, Never>?
    private let sessionID = UUID()

    func start() async throws -> AudioAnalysisSession {
        starts += 1
        started?.resume()
        started = nil
        let info = CaptureSessionInfo(id: sessionID, requestedAt: .now, timeZoneID: "UTC", sampleRate: 16_000, channelCount: 1,
                                      tapBufferSize: 4096, inputPortType: nil, inputPortName: nil,
                                      classifierIdentifier: "version1", windowDuration: 1, overlapFactor: 0.5,
                                      scoredLabels: ["cough"], topK: 3, captureSemanticsVersion: 2,
                                      osVersion: "test", deviceModel: "test")
        return AudioAnalysisSession(info: info, events: events.stream, display: display.stream)
    }
    func stop(sessionID: UUID) async {
        guard sessionID == self.sessionID else { return }
        stops += 1
        events.continuation.finish()
        display.continuation.finish()
        stopNotifications.continuation.yield()
    }
    func waitForStart() async {
        if starts > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func emit(_ windows: [WindowObservation], finish: Bool = true) {
        events.continuation.yield(.started(.now))
        for window in windows {
            events.continuation.yield(.window(window))
            display.continuation.yield(window)
        }
        if finish { events.continuation.finish(); display.continuation.finish() }
    }
    func fail() {
        events.continuation.finish(throwing: AudioAnalysisError.processingOverloaded)
        display.continuation.finish()
    }
}

private actor TestDetectionStore: DetectionStoring {
    var ingested = 0
    var appVersions: [String] = []
    var verdicts: [AnnotationVerdict] = []
    var fetches = 0
    let snapshots: [DetectionSnapshot]
    let fails: Bool
    let handoff: IngestHandoff?
    init(snapshots: [DetectionSnapshot] = [], fails: Bool = false, handoff: IngestHandoff? = nil) {
        self.snapshots = snapshots
        self.fails = fails
        self.handoff = handoff
    }
    func beginIngest(_ info: CaptureSessionInfo, appVersion: String, events: AsyncThrowingStream<CaptureEvent, any Error>,
                     stopRequest: ListeningStopRequest,
                     stopCapture: @escaping @Sendable () async -> Void) async -> Task<IngestOutcome, Never> {
        if let handoff {
            handoff.entered.continuation.finish()
            // An unstructured task keeps the handoff suspended even when the caller is cancelled.
            await Task { for await _ in handoff.release.stream {} }.value
        }
        appVersions.append(appVersion)
        return Task {
            var count = 0
            do {
                for try await event in events {
                    guard case .window = event else { continue }
                    if fails {
                        await stopCapture()
                        return IngestOutcome(windowCount: 0, endReason: .storageFailed, failure: "save failed")
                    }
                    count += 1
                    self.ingested += 1
                }
            } catch {
                return IngestOutcome(windowCount: count, endReason: ListeningEndReason(error),
                                     failure: error.localizedDescription)
            }
            return IngestOutcome(windowCount: count, endReason: stopRequest.reason ?? .userStopped, failure: nil)
        }
    }
    func candidates(label: String, in interval: DateInterval?, minimumConfidence: Double) throws -> [DetectionSnapshot] {
        if fails { throw FixtureError.failed }
        fetches += 1
        return snapshots
    }
    func sessions(in interval: DateInterval?) throws -> [ListeningSessionSnapshot] {
        if fails { throw FixtureError.failed }
        return []
    }
    func annotate(_ target: DetectionSnapshot, verdict: AnnotationVerdict, source: String, note: String?,
                  at date: Date, appVersion: String) throws {
        if fails { throw FixtureError.failed }
        verdicts.append(verdict)
    }
}
