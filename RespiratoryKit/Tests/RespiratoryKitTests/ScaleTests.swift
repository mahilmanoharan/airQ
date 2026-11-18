import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Scale")
struct ScaleTests {
    @Test("An hour of windows ingests, queries and exports in bounded time")
    func listeningHour() async throws {
        let container = try RespiratoryStore.makeInMemoryContainer()
        let store = DetectionStore(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let labels = CaptureLabels.scored
        let count = Int(ProcessInfo.processInfo.environment["SCALE_WINDOWS"] ?? "") ?? 2_400
        let stream = AsyncThrowingStream<CaptureEvent, any Error> { continuation in
            continuation.yield(.started(start))
            for index in 0..<count {
                continuation.yield(.window(WindowObservation(
                    windowIndex: index, startFrame: Int64(index) * 72_000, durationFrames: 144_000, deliveredAt: start,
                    scores: labels.map { _ in Float.random(in: 0...1) }, topLabels: ["speech", "cough", "music"],
                    topScores: [0.5, 0.3, 0.1], rms: 0.01, peak: 0.1)))
            }
            continuation.finish()
        }
        let info = CaptureSessionInfo(requestedAt: start, timeZoneID: "UTC", sampleRate: 48_000, channelCount: 1,
                                      tapBufferSize: 4096, inputPortType: nil, inputPortName: nil, classifierIdentifier: "version1",
                                      windowDuration: 3, overlapFactor: 0.5, scoredLabels: labels, topK: 3,
                                      captureSemanticsVersion: 2, osVersion: "t", deviceModel: "t")
        let clock = ContinuousClock()
        let ingest = await clock.measure {
            let outcome = await store.beginIngest(info, appVersion: "t", events: stream, stopRequest: .init(), stopCapture: {}).value
            #expect(outcome.windowCount == count)
        }
        var candidates: [DetectionSnapshot] = []
        let query = try await clock.measure { candidates = try await store.candidates(label: "cough", in: nil) }
        #expect(candidates.count == count)
        let folder = FileManager.default.temporaryDirectory.appending(path: "airq-scale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let exporter = RecordExporter(modelContainer: container)
        let export = try await clock.measure { _ = try await exporter.export(into: folder, appVersion: "t") }
        print("scale: ingest \(ingest), query \(query), export \(export) for \(count) windows")
        #expect(ingest < .seconds(20) && query < .seconds(10) && export < .seconds(20))
    }
}
