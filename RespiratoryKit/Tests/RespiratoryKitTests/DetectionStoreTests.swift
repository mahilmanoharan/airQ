import Foundation
import SwiftData
import Testing
@testable import RespiratoryKit

@Suite("DetectionStore")
struct DetectionStoreTests {
    private func makeStore() throws -> DetectionStore {
        DetectionStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
    }

    private static let legacyConfig = DetectionConfig(windowDuration: 1.0, overlapFactor: 0.5,
                                                      classifierIdentifier: "version1", appVersion: "1.0 (2)")
    private static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func info(id: UUID = UUID(), labels: [String] = ["cough", "speech"]) -> CaptureSessionInfo {
        CaptureSessionInfo(id: id, requestedAt: start.addingTimeInterval(-1), timeZoneID: "UTC", sampleRate: 16_000,
                           channelCount: 1, tapBufferSize: 4096, inputPortType: "MicrophoneBuiltIn",
                           inputPortName: "iPhone Microphone", classifierIdentifier: "version1", windowDuration: 1,
                           overlapFactor: 0.5, scoredLabels: labels, topK: 3, captureSemanticsVersion: 2,
                           osVersion: "test", deviceModel: "test")
    }

    static func window(_ index: Int, cough: Float, speech: Float = 0.1, top: String = "speech") -> WindowObservation {
        WindowObservation(windowIndex: index, startFrame: Int64(index) * 8_000, durationFrames: 16_000,
                          deliveredAt: start, scores: [cough, speech], topLabels: [top], topScores: [max(cough, speech)],
                          rms: 0.01, peak: 0.1)
    }

    private func ingest(_ store: DetectionStore, _ events: [CaptureEvent], error: (any Error)? = nil,
                        reason: ListeningEndReason? = nil, info: CaptureSessionInfo = info()) async -> IngestOutcome {
        let stream = AsyncThrowingStream<CaptureEvent, any Error> { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish(throwing: error)
        }
        let request = ListeningStopRequest()
        if let reason { request.request(reason) }
        return await store.beginIngest(info, appVersion: "1.0 (3)", events: stream, stopRequest: request,
                                       stopCapture: {}).value
    }

    @Test("Ingest persists every window, anchors the session at the first buffer, and records why it ended")
    func ingestsSession() async throws {
        let store = try makeStore()
        let windows = (0..<120).map { Self.window($0, cough: 0.2) }
        let outcome = await ingest(store, [.started(Self.start)] + windows.map(CaptureEvent.window), reason: .backgrounded)
        #expect(outcome == IngestOutcome(windowCount: 120, endReason: .backgrounded, failure: nil))

        let session = try #require(try await store.sessions(in: nil).first)
        #expect(session.startedAt == Self.start)
        #expect(session.endedAt != nil && session.endReason == "backgrounded")
        #expect(session.windowCount == 120)
        // Window time is derived: start + startFrame / sampleRate.
        #expect(session.lastWindowEnd == Self.start.addingTimeInterval((119 * 8_000 + 16_000) / 16_000))
    }

    @Test("A cancelled caller doesn't cut the drain short")
    func drainSurvivesCancellation() async throws {
        let store = try makeStore()
        let pair = AsyncThrowingStream<CaptureEvent, any Error>.makeStream()
        let beganIngest = AsyncStream<Void>.makeStream()
        let request = ListeningStopRequest()
        let caller = Task {
            let ingest = await store.beginIngest(Self.info(), appVersion: "t", events: pair.stream,
                                                 stopRequest: request, stopCapture: {})
            beganIngest.continuation.finish()
            return await (ingest.value, Task.isCancelled)
        }
        for await _ in beganIngest.stream {}
        caller.cancel()
        request.request(.navigatedAway)
        pair.continuation.yield(.started(Self.start))
        for index in 0..<10 { pair.continuation.yield(.window(Self.window(index, cough: 0.9))) }
        pair.continuation.finish()
        let (outcome, wasCancelled) = await caller.value
        #expect(wasCancelled)
        #expect(outcome.windowCount == 10 && outcome.endReason == .navigatedAway)
        #expect(try await store.candidates(label: "cough", in: nil).count == 10)
    }

    @Test("A pipeline error saves arrived windows and records a visible failure",
          arguments: [(AudioAnalysisError.processingOverloaded, "overloaded"), (.flushTimedOut, "flushTimedOut")])
    func streamFailure(error: AudioAnalysisError, endReason: String) async throws {
        let store = try makeStore()
        let outcome = await ingest(store, [.started(Self.start), .window(Self.window(0, cough: 0.4))],
                                   error: error, reason: .userStopped)
        #expect(outcome.endReason.rawValue == endReason && outcome.windowCount == 1)
        #expect(outcome.failure == error.errorDescription)
        #expect(try await store.sessions(in: nil).first?.endReason == endReason)
    }

    @Test("Candidates carry a label's score at any rank, merged with legacy rows, oldest first")
    func candidatesMergeV1AndV2() async throws {
        let store = try makeStore()
        _ = await ingest(store, [.started(Self.start), .window(Self.window(0, cough: 0.4)),
                                 .window(Self.window(1, cough: 0.7, speech: 0.2, top: "cough"))])
        try await store.recordLegacy(sessionID: UUID(), label: "cough", confidence: 0.9,
                                     timestamp: Self.start.addingTimeInterval(-100), config: Self.legacyConfig)
        try await store.recordLegacy(sessionID: UUID(), label: "sneeze", confidence: 0.9,
                                     timestamp: Self.start.addingTimeInterval(-50), config: Self.legacyConfig)

        let candidates = try await store.candidates(label: "cough", in: nil)
        #expect(candidates.map(\.confidence).map { ($0 * 10).rounded() / 10 } == [0.9, 0.4, 0.7])
        #expect(candidates.map(\.source) == [.legacy, .window, .window])
        #expect(candidates.map(\.captureSemanticsVersion) == [1, 2, 2])
        #expect(candidates.map(\.rank) == [1, nil, 1])
        #expect(candidates[2].timestamp == Self.start.addingTimeInterval(0.5))
        #expect(candidates[1].topLabel == "speech" && candidates[2].topLabel == "cough")

        let ranged = try await store.candidates(label: "cough",
                                                in: DateInterval(start: Self.start, duration: 0.25))
        #expect(ranged.count == 1)

        // A floor only limits what is loaded: legacy rows and windows below it are left out, the rest are unchanged.
        let floored = try await store.candidates(label: "cough", in: nil, minimumConfidence: 0.5)
        #expect(floored.map(\.confidence).map { ($0 * 10).rounded() / 10 } == [0.9, 0.7])
        #expect(floored.map(\.source) == [.legacy, .window])
    }

    @Test("Unscored labels still surface when they ranked in the top K")
    func topRankedUnscoredLabel() async throws {
        let store = try makeStore()
        let window = WindowObservation(windowIndex: 0, startFrame: 0, durationFrames: 16_000, deliveredAt: Self.start,
                                       scores: [0.1, 0.1], topLabels: ["dog_bark"], topScores: [0.8], rms: nil, peak: nil)
        _ = await ingest(store, [.started(Self.start), .window(window)])
        #expect(try await store.candidates(label: "dog_bark", in: nil).first?.confidence == Double(Float(0.8)))
        #expect(try await store.candidates(label: "cat", in: nil).isEmpty)
    }

    @Test("Annotations are append-only; the latest per target wins over a legacy flag, and cleared withdraws")
    func annotationsLatestWins() async throws {
        let store = try makeStore()
        try await store.recordLegacy(sessionID: UUID(), label: "cough", confidence: 0.8, timestamp: Self.start,
                                     config: Self.legacyConfig, isFalsePositive: true)
        var target = try #require(try await store.candidates(label: "cough", in: nil).first)
        #expect(target.verdict == .falsePositive)

        try await store.annotate(target, verdict: .confirmed, source: "review", note: nil, at: Self.start, appVersion: "t")
        target = try #require(try await store.candidates(label: "cough", in: nil).first)
        #expect(target.verdict == .confirmed)

        try await store.annotate(target, verdict: .cleared, source: "review", note: nil,
                                 at: Self.start.addingTimeInterval(1), appVersion: "t")
        #expect(try await store.candidates(label: "cough", in: nil).first?.verdict == nil)

        // An annotation on one label doesn't affect another label on the same window.
        _ = await ingest(store, [.started(Self.start), .window(Self.window(0, cough: 0.5))])
        let window = try #require(try await store.candidates(label: "cough", in: nil).first { $0.source == .window })
        try await store.annotate(window, verdict: .falsePositive, source: "review", note: nil, at: Self.start, appVersion: "t")
        #expect(try await store.candidates(label: "speech", in: nil).first?.verdict == nil)
        let context = ModelContext(store.modelContainer)
        #expect(try context.fetchCount(FetchDescriptor<DetectionAnnotation>()) == 3)
        #expect(try context.fetch(FetchDescriptor<DetectionEvent>()).first?.isFalsePositive == true)
    }
}
