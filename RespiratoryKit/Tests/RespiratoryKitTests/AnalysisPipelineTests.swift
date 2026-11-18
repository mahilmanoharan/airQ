import AVFAudio
import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Analysis pipeline (real classifier)")
struct AnalysisPipelineTests {
    @Test("Frames are session-relative, windows are contiguous and fully scored, and finish flushes without timing out")
    func endToEnd() async throws {
        let rate = 16_000.0
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let events = AsyncThrowingStream<CaptureEvent, any Error>.makeStream(bufferingPolicy: .bufferingOldest(4_096))
        let display = AsyncStream<WindowObservation>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let pipeline = try AnalysisPipeline(format: format, slotFrameCapacity: 8_192,
                                            events: events.continuation, display: display.continuation)
        let start = Date()
        let frames: AVAudioFrameCount = 4_096
        let hostOffset: Int64 = 123_456  // The engine's sample clock doesn't start at 0.
        for index in 0..<24 {  // ~6 s
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            let samples = try #require(buffer.floatChannelData)[0]
            for frame in 0..<Int(frames) {
                let t = Double(index * Int(frames) + frame) / rate
                samples[frame] = Float(0.2 * sin(2 * .pi * 440 * t))
            }
            pipeline.enqueue(buffer, sampleTime: hostOffset + Int64(index) * Int64(frames), at: start)
            await pipeline.barrier()  // Stay within the 8-slot bound, as a real-time source would.
        }
        await pipeline.finish()

        var windows: [WindowObservation] = []
        var anchor: Date?
        for try await event in events.stream {
            switch event {
            case .started(let date): anchor = date
            case .window(let window): windows.append(window)
            }
        }
        #expect(anchor == start)
        #expect(!windows.isEmpty)
        #expect(windows.map(\.windowIndex) == Array(0..<windows.count))
        #expect(windows.first?.startFrame == 0)
        #expect(windows.allSatisfy { $0.scores.count == pipeline.scoredLabels.count })
        #expect(windows.allSatisfy { $0.topLabels.count == CaptureLabels.topK && $0.rms != nil })
        let lastEnd = try #require(windows.last.map { $0.startFrame + $0.durationFrames })
        #expect(lastEnd <= 24 * Int64(frames))
        #expect(pipeline.scoredLabels.contains("cough"))
    }

    @Test("Finishing with an error (e.g. a route change) delivers exactly the windows a normal finish does, then the error")
    func finishWithErrorKeepsWindows() async throws {
        func run(finishingWith error: (any Error)?) async throws -> (windows: Int, thrown: (any Error)?) {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            let events = AsyncThrowingStream<CaptureEvent, any Error>.makeStream(bufferingPolicy: .bufferingOldest(4_096))
            let display = AsyncStream<WindowObservation>.makeStream()
            let pipeline = try AnalysisPipeline(format: format, slotFrameCapacity: 8_192,
                                                events: events.continuation, display: display.continuation)
            for index in 0..<22 {  // ~5.6 s: ends mid-window, so the last window exists only via the flush.
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
                buffer.frameLength = 4_096
                let samples = try #require(buffer.floatChannelData)[0]
                for frame in 0..<4_096 { samples[frame] = Float(0.1 * sin(Double(index * 4_096 + frame) / 10)) }
                pipeline.enqueue(buffer, sampleTime: Int64(index) * 4_096, at: Date())
                await pipeline.barrier()
            }
            await pipeline.finish(throwing: error)
            var windows = 0
            do {
                for try await event in events.stream { if case .window = event { windows += 1 } }
                return (windows, nil)
            } catch let thrown {
                return (windows, thrown)
            }
        }
        let normal = try await run(finishingWith: nil)
        let routeChange = try await run(finishingWith: AudioAnalysisError.routeChanged)
        #expect(normal.windows > 0 && normal.thrown == nil)
        #expect(routeChange.windows == normal.windows)
        #expect((routeChange.thrown as? AudioAnalysisError) == .routeChanged)
    }

    @Test("An expired flush reports incomplete analysis, even if stopping followed a route change",
          arguments: [false, true])
    func reportsExpiredFlush(routeChanged: Bool) async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let events = AsyncThrowingStream<CaptureEvent, any Error>.makeStream()
        let display = AsyncStream<WindowObservation>.makeStream()
        let pipeline = try AnalysisPipeline(format: format, slotFrameCapacity: 8_192,
                                            events: events.continuation, display: display.continuation)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
        buffer.frameLength = 4_096
        let samples = try #require(buffer.floatChannelData)[0]
        for frame in 0..<4_096 { samples[frame] = 0 }
        let startedAt = Date()
        pipeline.enqueue(buffer, sampleTime: 0, at: startedAt)

        await pipeline.finish(throwing: routeChanged ? AudioAnalysisError.routeChanged : nil, flushTimeout: .zero)

        var anchor: Date?
        var thrown: (any Error)?
        do {
            for try await event in events.stream {
                if case .started(let date) = event { anchor = date }
            }
        } catch {
            thrown = error
        }
        #expect(anchor == startedAt)
        let failure = try #require(thrown)
        #expect(ListeningEndReason(failure).rawValue == "flushTimedOut")
    }

    @Test("Without a host time on the first buffer, frames stay contiguous even if later buffers have one")
    func anchorWithoutHostTime() async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let events = AsyncThrowingStream<CaptureEvent, any Error>.makeStream(bufferingPolicy: .bufferingOldest(4_096))
        let display = AsyncStream<WindowObservation>.makeStream()
        let pipeline = try AnalysisPipeline(format: format, slotFrameCapacity: 8_192,
                                            events: events.continuation, display: display.continuation)
        for index in 0..<16 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
            buffer.frameLength = 4_096
            pipeline.enqueue(buffer, sampleTime: index == 0 ? nil : 9_000_000_000 + Int64(index) * 4_096, at: .now)
            await pipeline.barrier()
        }
        await pipeline.finish()
        var lastEnd: Int64 = 0
        for try await event in events.stream {
            if case .window(let window) = event { lastEnd = max(lastEnd, window.startFrame + window.durationFrames) }
        }
        #expect(lastEnd > 0 && lastEnd <= 16 * 4_096)
    }
}
