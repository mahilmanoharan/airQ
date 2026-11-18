import AVFAudio
import CoreMedia
import SoundAnalysis
import Synchronization

/// Setup completes before publication. Afterward all analyzer mutation, including flush and
/// teardown, is confined to `queue`; everything else is immutable, lock-protected, or Sendable.
final class AnalysisPipeline: @unchecked Sendable {
    static let slotCount = 8

    let config: SessionAudioConfig
    let scoredLabels: [String]
    let topK: Int
    private let analyzer: SNAudioStreamAnalyzer
    private let observer: ResultsObserver
    private let meter: LevelMeter
    private let events: AsyncThrowingStream<CaptureEvent, any Error>.Continuation
    private let display: AsyncStream<WindowObservation>.Continuation
    private let queue = DispatchQueue(label: "com.airq.respiratorykit.analysis")
    /// One permit per preallocated slot: a permit held means that slot's samples are in flight.
    private let capacity = DispatchSemaphore(value: slotCount)
    private let slots: [AudioSlot]
    private let nextSlot = Atomic<Int>(0)
    private var anchorSampleTime: Int64?  // queue only; nil until the first buffer
    /// Whether the anchor came from a valid host sample time. If the first buffer had none, the
    /// whole session counts frames contiguously, never mixing in absolute host times.
    private var anchorIsHostTime = false  // queue only
    private var nextPosition: Int64 = 0   // queue only
    private var isFinished = false        // queue only

    init(format: AVAudioFormat, slotFrameCapacity: AVAudioFrameCount, topK: Int = CaptureLabels.topK,
         events: AsyncThrowingStream<CaptureEvent, any Error>.Continuation,
         display: AsyncStream<WindowObservation>.Continuation) throws {
        self.events = events
        self.display = display
        self.topK = topK
        analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        config = SessionAudioConfig(windowDuration: request.windowDuration.seconds,
                                    overlapFactor: request.overlapFactor, classifierIdentifier: "version1")
        let known = Set(request.knownClassifications)
        scoredLabels = CaptureLabels.scored.filter(known.contains)
        slots = try (0..<Self.slotCount).map { _ in
            guard let slot = AudioSlot(format: format, frameCapacity: slotFrameCapacity) else {
                throw AudioAnalysisError.invalidInputFormat
            }
            return slot
        }
        meter = LevelMeter(sampleRate: format.sampleRate)
        observer = ResultsObserver(sampleRate: format.sampleRate, scoredLabels: scoredLabels, topK: topK,
                                   meter: meter, events: events, display: display)
        try analyzer.add(request, withObserver: observer)
    }

    /// Called on the engine's tap thread. Never waits, and allocates only if the engine delivers a
    /// buffer larger than the preallocated slots.
    func enqueue(_ buffer: AVAudioPCMBuffer, sampleTime: Int64?, at date: Date) {
        guard capacity.wait(timeout: .now()) == .success else {
            events.finish(throwing: AudioAnalysisError.processingOverloaded)
            return
        }
        // FIFO reuse is safe: the queue releases permits in order, so when a permit is available the
        // slot used `slotCount` acquisitions ago has been fully analysed.
        let slot = slots[nextSlot.wrappingAdd(1, ordering: .relaxed).oldValue % Self.slotCount]
        let owned: AudioSlot
        if slot.copy(from: buffer) {
            owned = slot
        } else if let fallback = AudioSlot(copying: buffer) {
            owned = fallback
        } else {
            capacity.signal()
            events.finish(throwing: AudioAnalysisError.processingOverloaded)
            return
        }
        queue.async { [self] in
            defer { capacity.signal() }
            guard !isFinished else { return }
            let position: Int64
            if anchorSampleTime == nil {
                anchorSampleTime = sampleTime ?? 0
                anchorIsHostTime = sampleTime != nil
                position = 0
                if case .dropped = events.yield(.started(date)) {
                    events.finish(throwing: AudioAnalysisError.processingOverloaded)
                }
            } else if anchorIsHostTime, let anchorSampleTime, let sampleTime {
                position = sampleTime - anchorSampleTime
            } else {
                position = nextPosition  // No usable host sample time: assume contiguous audio.
            }
            nextPosition = position + Int64(owned.buffer.frameLength)
            meter.ingest(owned.buffer, startFrame: position)
            analyzer.analyze(owned.buffer, atAudioFramePosition: position)
        }
    }

    /// Analyses every queued buffer, flushes the final partial window, then ends both streams, with
    /// `error` when capture stopped for a reason such as a route change. The error is delivered only
    /// after the flushed windows, so they are still persisted. If the analyzer doesn't signal
    /// completion before `flushTimeout`, mark the flush as incomplete. Call after removing the tap.
    func finish(throwing error: (any Error)? = nil, flushTimeout: Duration = .seconds(2)) async {
        let shouldFlush = await onQueue { [self] () -> Bool in
            guard !isFinished else { return false }
            analyzer.completeAnalysis()
            return true
        }
        guard shouldFlush else { return }
        let completed = await observer.waitForCompletion(timeout: flushTimeout)
        await onQueue { [self] in
            isFinished = true
            analyzer.removeAllRequests()
        }
        if let failure = completed ? error : AudioAnalysisError.flushTimedOut {
            events.finish(throwing: failure)
        } else {
            events.finish()
        }
        display.finish()
    }

    /// Waits until everything enqueued so far has been analysed.
    func barrier() async { await onQueue {} }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in queue.async { done.resume(returning: work()) } }
    }
}

/// A PCM buffer owned by the pipeline. Its samples are written only while its semaphore permit is
/// held by the writer and read only by the one analysis-queue consumer afterwards.
final class AudioSlot: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        self.buffer = buffer
    }

    /// A one-off deep copy, for a source larger than the preallocated slots.
    convenience init?(copying source: AVAudioPCMBuffer) {
        self.init(format: source.format, frameCapacity: source.frameLength)
        guard copy(from: source) else { return nil }
    }

    /// Deep-copies samples: the engine may reuse its buffer after the tap returns.
    func copy(from source: AVAudioPCMBuffer) -> Bool {
        guard source.format == buffer.format, source.frameLength <= buffer.frameCapacity else { return false }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let outputs = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard inputs.count == outputs.count else { return false }
        buffer.frameLength = source.frameLength
        for index in inputs.indices {
            let count = Int(inputs[index].mDataByteSize)
            guard let input = inputs[index].mData, let output = outputs[index].mData,
                  count <= Int(buffer.frameCapacity * buffer.format.streamDescription.pointee.mBytesPerFrame)
            else { return false }
            output.copyMemory(from: input, byteCount: count)
            outputs[index].mDataByteSize = UInt32(count)
        }
        return true
    }
}

/// NSObjectProtocol is required by SoundAnalysis, so this can't be an actor. It only converts
/// results into Sendable values and forwards them to thread-safe continuations.
private final class ResultsObserver: NSObject, SNResultsObserving, Sendable {
    private let sampleRate: Double
    private let scoredLabels: [String]
    private let topK: Int
    private let meter: LevelMeter
    private let events: AsyncThrowingStream<CaptureEvent, any Error>.Continuation
    private let display: AsyncStream<WindowObservation>.Continuation
    private let windowCount = Mutex(0)
    private let completion = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

    init(sampleRate: Double, scoredLabels: [String], topK: Int, meter: LevelMeter,
         events: AsyncThrowingStream<CaptureEvent, any Error>.Continuation,
         display: AsyncStream<WindowObservation>.Continuation) {
        self.sampleRate = sampleRate
        self.scoredLabels = scoredLabels
        self.topK = topK
        self.meter = meter
        self.events = events
        self.display = display
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = frames(result.timeRange.start)
        let duration = frames(result.timeRange.duration)
        let top = result.classifications.sorted { $0.confidence > $1.confidence }.prefix(topK)
        let level = meter.level(startFrame: start, frames: duration)
        let index = windowCount.withLock { count in
            defer { count += 1 }
            return count
        }
        let window = WindowObservation(
            windowIndex: index, startFrame: start, durationFrames: duration, deliveredAt: Date(),
            scores: scoredLabels.map { Float(result.classification(forIdentifier: $0)?.confidence ?? .nan) },
            topLabels: top.map(\.identifier), topScores: top.map { Float($0.confidence) },
            rms: level?.rms, peak: level?.peak)
        if case .dropped = events.yield(.window(window)) {
            events.finish(throwing: AudioAnalysisError.processingOverloaded)
        }
        display.yield(window)  // Display may drop; it is UI only.
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        events.finish(throwing: AudioAnalysisError.analysisFailed(underlying: error.localizedDescription))
        signalCompletion()
    }

    func requestDidComplete(_ request: any SNRequest) {
        signalCompletion()
    }

    func waitForCompletion(timeout: Duration) async -> Bool {
        guard timeout > .zero else { return false }
        let stream = completion.stream
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let completed = await group.next() ?? false
            group.cancelAll()
            return completed
        }
    }

    private func signalCompletion() {
        completion.continuation.yield()
        completion.continuation.finish()
    }

    private func frames(_ time: CMTime) -> Int64 {
        guard time.isNumeric else { return 0 }
        return CMTimeConvertScale(time, timescale: CMTimeScale(sampleRate.rounded()), method: .roundHalfAwayFromZero).value
    }
}
