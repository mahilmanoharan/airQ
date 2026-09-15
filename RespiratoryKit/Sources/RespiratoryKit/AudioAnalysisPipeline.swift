import AVFAudio
import CoreMedia
import SoundAnalysis

/// Setup completes before publication. Afterward all analyzer mutation, including
/// teardown, is confined to queue; config/continuation are immutable and Sendable.
final class AnalysisPipeline: @unchecked Sendable {
    let config: SessionAudioConfig
    private let analyzer: SNAudioStreamAnalyzer
    private let observer: ResultsObserver
    private let continuation: AsyncThrowingStream<RawDetection, any Error>.Continuation
    private let queue = DispatchQueue(label: "com.airq.respiratorykit.analysis")
    private let capacity = DispatchSemaphore(value: 8)
    private var isFinished = false // queue only

    init(format: AVAudioFormat, continuation: AsyncThrowingStream<RawDetection, any Error>.Continuation) throws {
        self.continuation = continuation
        analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        config = SessionAudioConfig(windowDuration: request.windowDuration.seconds,
                                    overlapFactor: request.overlapFactor, classifierIdentifier: "version1")
        observer = ResultsObserver(continuation: continuation)
        try analyzer.add(request, withObserver: observer)
    }

    func enqueue(_ buffer: AVAudioPCMBuffer, at position: AVAudioFramePosition) {
        // Never wait on the audio callback, nor accumulate an unbounded queue of samples.
        guard capacity.wait(timeout: .now()) == .success else {
            continuation.finish(throwing: AudioAnalysisError.processingOverloaded)
            return
        }
        guard let copy = CopiedAudioBuffer(buffer) else {
            capacity.signal()
            continuation.finish(throwing: AudioAnalysisError.processingOverloaded)
            return
        }
        queue.async { [self] in
            defer { capacity.signal() }
            guard !isFinished else { return }
            analyzer.analyze(copy.buffer, atAudioFramePosition: position)
        }
    }

    func finish() async {
        await withCheckedContinuation { finished in
            queue.async { [self] in
                isFinished = true
                analyzer.removeAllRequests()
                finished.resume()
            }
        }
    }
}

/// Owns a deep copy: the engine may reuse its original samples after the tap returns.
/// After initialization this buffer is read only, by its one analysis-queue consumer.
final class CopiedAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(_ source: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        copy.frameLength = source.frameLength
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let outputs = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard inputs.count == outputs.count else { return nil }
        for index in inputs.indices {
            let count = Int(inputs[index].mDataByteSize)
            guard count <= Int(outputs[index].mDataByteSize),
                  let input = inputs[index].mData, let output = outputs[index].mData else { return nil }
            output.copyMemory(from: input, byteCount: count)
        }
        buffer = copy
    }
}

/// NSObjectProtocol is required by SoundAnalysis. This immutable forwarder touches
/// only AsyncThrowingStream's thread-safe continuation, never model or actor state.
private final class ResultsObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<RawDetection, any Error>.Continuation

    init(continuation: AsyncThrowingStream<RawDetection, any Error>.Continuation) {
        self.continuation = continuation
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult, let top = result.classifications.first else { return }
        let detection = RawDetection(label: top.identifier, confidence: top.confidence, timestamp: Date())
        if case .dropped = continuation.yield(detection) {
            continuation.finish(throwing: AudioAnalysisError.processingOverloaded)
        }
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        continuation.finish(throwing: AudioAnalysisError.analysisFailed(underlying: error.localizedDescription))
    }
}
