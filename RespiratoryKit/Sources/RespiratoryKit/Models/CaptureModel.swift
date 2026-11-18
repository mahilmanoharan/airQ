import Foundation
import Synchronization

/// Capture semantics 2 (build 3+): every analysis window is stored with a score for each scored
/// label regardless of rank, plus the top-K labels by rank. No threshold, no allowlist gate.
public enum CaptureLabels {
    public static let captureSemanticsVersion = 2
    public static let topK = 3

    /// Sounds commonly confused with respiratory events, scored so false-positive sessions can be
    /// studied later: speech and crowds, laughter, and other human or percussive sounds. `gargling`
    /// and `burp` are respiratory-adjacent. All are present on `SNClassifierIdentifier.version1`.
    public static let confounders: [String] = [
        "speech", "chatter", "babble", "crowd", "whispering", "shout", "yell",
        "laughter", "belly_laugh", "giggling", "chuckle_chortle", "snicker",
        "crying_sobbing", "music", "singing", "clapping", "thump_thud", "slap_smack",
        "gargling", "burp",
    ]

    /// Index order of `WindowObservation.scores` (before filtering to the classifier's known labels).
    public static let scored: [String] = RespiratoryLabels.allowlist.sorted() + confounders
}

/// One analysis window's raw classifier output. Sendable, extracted inside the SoundAnalysis
/// callback so no framework object crosses a concurrency boundary.
public struct WindowObservation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let windowIndex: Int
    /// Frames since the session's first audio buffer (`SNClassificationResult.timeRange`).
    public let startFrame: Int64
    public let durationFrames: Int64
    public let deliveredAt: Date
    /// One score per `CaptureSessionInfo.scoredLabels` entry; NaN if the classifier returned none.
    public let scores: [Float]
    public let topLabels: [String]
    public let topScores: [Float]
    /// Linear RMS / peak amplitude (0...1) of the window's audio, nil if not measurable.
    public let rms: Float?
    public let peak: Float?

    public init(id: UUID = UUID(), windowIndex: Int, startFrame: Int64, durationFrames: Int64, deliveredAt: Date,
                scores: [Float], topLabels: [String], topScores: [Float], rms: Float?, peak: Float?) {
        self.id = id
        self.windowIndex = windowIndex
        self.startFrame = startFrame
        self.durationFrames = durationFrames
        self.deliveredAt = deliveredAt
        self.scores = scores
        self.topLabels = topLabels
        self.topScores = topScores
        self.rms = rms
        self.peak = peak
    }

    public var topLabel: String? { topLabels.first }
    public var topScore: Float? { topScores.first }

    public func score(for label: String, in scoredLabels: [String]) -> Float? {
        if let index = scoredLabels.firstIndex(of: label), index < scores.count, !scores[index].isNaN {
            return scores[index]
        }
        return topLabels.firstIndex(of: label).flatMap { $0 < topScores.count ? topScores[$0] : nil }
    }
}

/// What the capture pipeline reports, in order: the wall-clock anchor of the first audio buffer,
/// then windows. Window time = anchor + startFrame / sampleRate.
public enum CaptureEvent: Sendable, Equatable {
    case started(Date)
    case window(WindowObservation)
}

/// Provenance for one listening session, written once to `ListeningSession`.
public struct CaptureSessionInfo: Sendable, Equatable {
    public let id: UUID
    /// When capture was requested; replaced by the first buffer's time once audio arrives.
    public let requestedAt: Date
    public let timeZoneID: String
    public let sampleRate: Double
    public let channelCount: Int
    public let tapBufferSize: Int
    public let inputPortType: String?
    public let inputPortName: String?
    public let classifierIdentifier: String
    public let windowDuration: Double
    public let overlapFactor: Double
    public let scoredLabels: [String]
    public let topK: Int
    public let captureSemanticsVersion: Int
    public let osVersion: String
    public let deviceModel: String

    public init(id: UUID = UUID(), requestedAt: Date, timeZoneID: String, sampleRate: Double, channelCount: Int,
                tapBufferSize: Int, inputPortType: String?, inputPortName: String?, classifierIdentifier: String,
                windowDuration: Double, overlapFactor: Double, scoredLabels: [String], topK: Int,
                captureSemanticsVersion: Int, osVersion: String, deviceModel: String) {
        self.id = id
        self.requestedAt = requestedAt
        self.timeZoneID = timeZoneID
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.tapBufferSize = tapBufferSize
        self.inputPortType = inputPortType
        self.inputPortName = inputPortName
        self.classifierIdentifier = classifierIdentifier
        self.windowDuration = windowDuration
        self.overlapFactor = overlapFactor
        self.scoredLabels = scoredLabels
        self.topK = topK
        self.captureSemanticsVersion = captureSemanticsVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }
}

/// Why a listening session's exposure denominator ended. Stored as the raw value.
public enum ListeningEndReason: String, Sendable, CaseIterable {
    case userStopped, backgrounded, navigatedAway, interrupted, routeChanged, overloaded
    case analyzerFailed, flushTimedOut, storageFailed

    public init(_ error: any Error) {
        switch error as? AudioAnalysisError {
        case .processingOverloaded: self = .overloaded
        case .inputInterrupted: self = .interrupted
        case .routeChanged: self = .routeChanged
        case .flushTimedOut: self = .flushTimedOut
        default: self = .analyzerFailed
        }
    }
}

/// The reason the app asked capture to stop, recorded by whichever caller asks first.
public final class ListeningStopRequest: Sendable {
    private let state = Mutex<ListeningEndReason?>(nil)

    public init() {}

    public func request(_ reason: ListeningEndReason) {
        state.withLock { if $0 == nil { $0 = reason } }
    }

    public var reason: ListeningEndReason? { state.withLock { $0 } }
}

/// Result of persisting one session's stream.
public struct IngestOutcome: Sendable, Equatable {
    public let windowCount: Int
    public let endReason: ListeningEndReason
    /// A user-facing message when the session ended because something failed.
    public let failure: String?

    public init(windowCount: Int, endReason: ListeningEndReason, failure: String?) {
        self.windowCount = windowCount
        self.endReason = endReason
        self.failure = failure
    }
}
