import Foundation

public struct AudioAnalysisSession: Sendable {
    public let sessionID: UUID
    public let stream: AsyncThrowingStream<RawDetection, any Error>
    public let config: SessionAudioConfig

    public init(sessionID: UUID, stream: AsyncThrowingStream<RawDetection, any Error>, config: SessionAudioConfig) {
        self.sessionID = sessionID
        self.stream = stream
        self.config = config
    }
}

public protocol AudioAnalyzing: Sendable {
    func start() async throws -> AudioAnalysisSession
    func stop() async
}

public protocol DetectionStoring: Sendable {
    func record(sessionID: UUID, label: String, confidence: Double, timestamp: Date, config: DetectionConfig) async throws
    func setFalsePositive(_ id: UUID, isFalsePositive: Bool) async throws
    func fetchSnapshots(limit: Int?, newestFirst: Bool) async throws -> [DetectionSnapshot]
}
