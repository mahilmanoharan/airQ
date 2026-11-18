import AVFAudio
import Foundation

public enum AudioAnalysisError: LocalizedError, Sendable, Equatable {
    case microphonePermissionDenied, sessionAlreadyActive, invalidInputFormat, processingOverloaded
    case engineStartFailed(underlying: String)
    case analysisFailed(underlying: String)
    case flushTimedOut
    case inputInterrupted
    case routeChanged

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: "Microphone access denied. Enable it in Settings to use Listen."
        case .sessionAlreadyActive: "A listening session is already active or stopping."
        case .invalidInputFormat: "No usable microphone input is available."
        case .processingOverloaded: "Audio processing could not keep up. Listening stopped; please try again."
        case .engineStartFailed(let message): "Could not start listening: \(message)"
        case .analysisFailed(let message): "Sound analysis stopped: \(message)"
        case .flushTimedOut: "Sound analysis took too long to finish. Some sound checks may be missing."
        case .inputInterrupted: "Listening was interrupted (for example by a call). Start a new session to continue."
        case .routeChanged: "The microphone changed (for example headphones were connected). Start a new session to continue."
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
    private var cleanupTask: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var pipeline: AnalysisPipeline?
    private var notificationObservers: [any NSObjectProtocol] = []
    private var audioSessionIsActive = false
    private let requestPermission: @Sendable () async -> Bool
    /// Requested tap size; also the preallocated slot size (doubled for headroom).
    private let tapBufferSize: AVAudioFrameCount = 4096

    public init(requestPermission: @escaping @Sendable () async -> Bool = {
        await AVAudioApplication.requestRecordPermission()
    }) {
        self.requestPermission = requestPermission
    }

    public func start() async throws -> AudioAnalysisSession {
        guard activeID == nil else { throw AudioAnalysisError.sessionAlreadyActive }
        let id = UUID()
        activeID = id // Reserve the session before the permission suspension point.
        do {
            let allowed = await requestPermission()
            try Task.checkCancellation()
            guard activeID == id, cleanupTask == nil else { throw CancellationError() }
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
            let events = AsyncThrowingStream<CaptureEvent, any Error>.makeStream(bufferingPolicy: .bufferingOldest(4_096))
            let display = AsyncStream<WindowObservation>.makeStream(bufferingPolicy: .bufferingNewest(64))
            let pipeline = try AnalysisPipeline(format: format, slotFrameCapacity: tapBufferSize * 2,
                                                events: events.continuation, display: display.continuation)
            self.engine = engine
            self.pipeline = pipeline
            // Installed before the tap can deliver anything: the pipeline may end the stream from the
            // audio thread (backlog overflow) before `start()` returns, and that must still stop the engine.
            events.continuation.onTermination = { [weak self] _ in
                Task { await self?.stop(sessionID: id) }
            }
            let info = Self.sessionInfo(id: id, format: format, tapBufferSize: tapBufferSize, pipeline: pipeline)

            // installAudioTap is iOS 27+ only; installTap is the supported iOS 26 API.
            // This callback captures only the explicitly queue-confined Sendable bridge.
            engine.inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: format) { buffer, time in
                pipeline.enqueue(buffer, sampleTime: time.isSampleTimeValid ? time.sampleTime : nil, at: Date())
            }
            do { try engine.start() }
            catch { throw AudioAnalysisError.engineStartFailed(underlying: error.localizedDescription) }
            isRunning = true
            observeInputChanges(engine: engine, sessionID: id)
            return AudioAnalysisSession(info: info, events: events.stream, display: display.stream)
        } catch {
            await stop(sessionID: id)
            throw error
        }
    }

    /// Stops the current reservation, including a start waiting for microphone permission.
    public func stop() async {
        guard let activeID else { return }
        await stop(sessionID: activeID)
    }

    public func stop(sessionID: UUID) async { await stop(sessionID: sessionID, finishingWith: nil) }

    /// Keep the ID reserved during cleanup so a matching caller waits for the same task and
    /// an old stream termination or storage callback cannot stop a later session.
    private func stop(sessionID: UUID, finishingWith error: (any Error)?) async {
        guard activeID == sessionID else { return }
        if let cleanupTask { await cleanupTask.value; return }
        isRunning = false
        for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
        notificationObservers.removeAll()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let finishingPipeline = pipeline
        pipeline = nil
        let shouldDeactivateSession = audioSessionIsActive
        audioSessionIsActive = false
        // The tap is gone, so the pipeline can analyse what's queued, flush the final window and
        // end both streams; its analyzer work stays on its own queue.
        let cleanup = Task {
            await finishingPipeline?.finish(throwing: error)
            #if os(iOS)
            if shouldDeactivateSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            #endif
            activeID = nil
            cleanupTask = nil
        }
        cleanupTask = cleanup
        await cleanup.value
    }

    /// A route change or interruption stops capture and ends the stream with the reason, but only
    /// after the pipeline flushes: closing the stream here first would discard the queued windows.
    private func observeInputChanges(engine: AVAudioEngine, sessionID: UUID) {
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { await self?.stop(sessionID: sessionID, finishingWith: AudioAnalysisError.routeChanged) }
        })
        #if os(iOS)
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { await self?.stop(sessionID: sessionID, finishingWith: AudioAnalysisError.inputInterrupted) }
        })
        #endif
    }

    private static func sessionInfo(id: UUID, format: AVAudioFormat, tapBufferSize: AVAudioFrameCount,
                                    pipeline: AnalysisPipeline) -> CaptureSessionInfo {
        var portType: String?
        var portName: String?
        #if os(iOS)
        let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
        portType = input?.portType.rawValue
        portName = input?.portName
        #endif
        return CaptureSessionInfo(
            id: id, requestedAt: Date(), timeZoneID: TimeZone.current.identifier, sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount), tapBufferSize: Int(tapBufferSize),
            inputPortType: portType, inputPortName: portName,
            classifierIdentifier: pipeline.config.classifierIdentifier, windowDuration: pipeline.config.windowDuration,
            overlapFactor: pipeline.config.overlapFactor, scoredLabels: pipeline.scoredLabels, topK: pipeline.topK,
            captureSemanticsVersion: CaptureLabels.captureSemanticsVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString, deviceModel: DeviceModel.identifier)
    }
}

enum DeviceModel {
    /// The hardware identifier (e.g. "iPhone18,1"); the simulated model on a simulator.
    static var identifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
