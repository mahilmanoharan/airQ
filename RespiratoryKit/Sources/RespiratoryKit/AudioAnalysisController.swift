import AVFAudio
import Foundation

/// One window's top-ranked classification, without a confidence cutoff.
public struct RawDetection: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let label: String
    public let confidence: Double
    public let timestamp: Date

    public init(id: UUID = UUID(), label: String, confidence: Double, timestamp: Date) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public enum AudioAnalysisError: LocalizedError, Sendable, Equatable {
    case microphonePermissionDenied, sessionAlreadyActive, invalidInputFormat, processingOverloaded
    case engineStartFailed(underlying: String)
    case analysisFailed(underlying: String)
    case inputInterrupted

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: "Microphone access denied. Enable it in Settings to use Listen."
        case .sessionAlreadyActive: "A listening session is already active or stopping."
        case .invalidInputFormat: "No usable microphone input is available."
        case .processingOverloaded: "Audio processing could not keep up. Listening stopped; please try again."
        case .engineStartFailed(let message): "Could not start listening: \(message)"
        case .analysisFailed(let message): "Sound analysis stopped: \(message)"
        case .inputInterrupted: "Microphone input was interrupted or changed. Start a new listening session to continue."
        }
    }
}

public struct SessionAudioConfig: Sendable, Equatable {
    public let windowDuration: TimeInterval
    public let overlapFactor: Double
    public let classifierIdentifier: String

    public init(windowDuration: TimeInterval, overlapFactor: Double, classifierIdentifier: String) {
        self.windowDuration = windowDuration
        self.overlapFactor = overlapFactor
        self.classifierIdentifier = classifierIdentifier
    }
}

/// Owns engine lifecycle; AnalysisPipeline owns the serial analyzer boundary.
public actor AudioAnalysisController: AudioAnalyzing {
    public private(set) var isRunning = false
    private var activeID: UUID?
    private var isStopping = false
    private var cleanupTask: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var pipeline: AnalysisPipeline?
    private var continuation: AsyncThrowingStream<RawDetection, any Error>.Continuation?
    private var notificationObservers: [any NSObjectProtocol] = []
    private var audioSessionIsActive = false
    private let requestPermission: @Sendable () async -> Bool

    public init(requestPermission: @escaping @Sendable () async -> Bool = {
        await AVAudioApplication.requestRecordPermission()
    }) {
        self.requestPermission = requestPermission
    }

    public func start() async throws -> AudioAnalysisSession {
        guard activeID == nil, !isStopping else { throw AudioAnalysisError.sessionAlreadyActive }
        let id = UUID()
        activeID = id // Reserve the session before the permission suspension point.
        do {
            let allowed = await requestPermission()
            try Task.checkCancellation()
            guard activeID == id else { throw CancellationError() }
            guard allowed else { throw AudioAnalysisError.microphonePermissionDenied }
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            audioSessionIsActive = true
            #endif

            let engine = AVAudioEngine()
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioAnalysisError.invalidInputFormat }
            let pair = AsyncThrowingStream<RawDetection, any Error>.makeStream(bufferingPolicy: .bufferingOldest(512))
            let pipeline = try AnalysisPipeline(format: format, continuation: pair.continuation)
            self.engine = engine
            self.pipeline = pipeline
            continuation = pair.continuation

            // installAudioTap is iOS 27+ only; installTap is the supported iOS 26 API.
            // This callback captures only the explicitly queue-confined Sendable bridge.
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                pipeline.enqueue(buffer, at: time.sampleTime)
            }
            do { try engine.start() }
            catch { throw AudioAnalysisError.engineStartFailed(underlying: error.localizedDescription) }
            isRunning = true
            observeInputChanges(engine: engine, continuation: pair.continuation)
            pair.continuation.onTermination = { [weak self] _ in
                Task { await self?.stop(sessionID: id) }
            }
            return AudioAnalysisSession(sessionID: id, stream: pair.stream, config: pipeline.config)
        } catch {
            if activeID == id { await stop() }
            throw error
        }
    }

    public func stop() async {
        if let cleanupTask { await cleanupTask.value; return }
        guard activeID != nil else { return }
        activeID = nil
        isStopping = true
        isRunning = false
        for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
        notificationObservers.removeAll()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let finishingPipeline = pipeline
        pipeline = nil
        continuation?.finish()
        continuation = nil
        let shouldDeactivateSession = audioSessionIsActive
        audioSessionIsActive = false
        // Barrier: remove requests on the same queue as analyze, never concurrently.
        let cleanup = Task {
            await finishingPipeline?.finish()
            #if os(iOS)
            if shouldDeactivateSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            #endif
            isStopping = false
            cleanupTask = nil
        }
        cleanupTask = cleanup
        await cleanup.value
    }

    private func stop(sessionID: UUID) async {
        guard activeID == sessionID else { return } // Old stream termination cannot stop a new session.
        await stop()
    }

    private func observeInputChanges(engine: AVAudioEngine,
                                     continuation: AsyncThrowingStream<RawDetection, any Error>.Continuation) {
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in
            continuation.finish(throwing: AudioAnalysisError.inputInterrupted)
        })
        #if os(iOS)
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            continuation.finish(throwing: AudioAnalysisError.inputInterrupted)
        })
        #endif
    }
}
