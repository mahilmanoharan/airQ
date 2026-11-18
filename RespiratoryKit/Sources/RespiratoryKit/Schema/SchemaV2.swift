import Foundation
import SwiftData

/// Additive to SchemaV1, so V1 → V2 is a lightweight migration. Frozen once any device has opened
/// it: change a model only by adding SchemaV3 with a migration stage.
///
/// Conventions: no relationships (rows join by UUID or dayKey), enums stored as String raw values,
/// optionals mean "unanswered/unavailable" (never a stand-in for zero), and every row records the
/// schema and app version that wrote it. Nothing stored here has a threshold or aggregation applied.
public enum SchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.DetectionEvent.self,
            ListeningSession.self, ClassifierWindow.self, DetectionAnnotation.self,
            DailyRecord.self, EnvironmentalObservation.self, HourlyAirQuality.self,
            DailyCheckIn.self, ContextEvent.self,
        ]
    }
}

extension SchemaV2 {
    /// One Start→Stop listening session: the exposure denominator and the capture configuration that
    /// produced every `ClassifierWindow` in it. `endedAt == nil` means it never closed cleanly.
    @Model
    public final class ListeningSession {
        #Index<ListeningSession>([\.id], [\.startedAt])

        public var id: UUID = UUID()
        public var startedAt: Date = Date.distantPast
        public var endedAt: Date?
        public var endReason: String?
        public var timeZoneID: String = ""
        public var sampleRate: Double = 0
        public var channelCount: Int = 0
        public var tapBufferSize: Int = 0
        public var inputPortType: String?
        public var inputPortName: String?
        public var classifierIdentifier: String = ""
        public var windowDuration: Double = 0
        public var overlapFactor: Double = 0
        /// Index order of every window's `scores` in this session.
        public var scoredLabels: [String] = []
        public var topK: Int = 0
        public var captureSemanticsVersion: Int = 0
        public var appVersion: String = ""
        public var osVersion: String = ""
        public var deviceModel: String = ""
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), startedAt: Date, timeZoneID: String,
            sampleRate: Double, channelCount: Int, tapBufferSize: Int,
            inputPortType: String?, inputPortName: String?,
            classifierIdentifier: String, windowDuration: Double, overlapFactor: Double,
            scoredLabels: [String], topK: Int, captureSemanticsVersion: Int,
            appVersion: String, osVersion: String, deviceModel: String,
            schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.startedAt = startedAt
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
            self.appVersion = appVersion
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.schemaVersion = schemaVersion
        }
    }

    /// One analysis window's raw classifier output: a score for every label in the session's
    /// `scoredLabels` regardless of rank, plus the top-K by rank. Absolute time is derived at read
    /// time as `session.startedAt + startFrame / session.sampleRate`.
    @Model
    public final class ClassifierWindow {
        #Index<ClassifierWindow>([\.sessionID], [\.deliveredAt], [\.id])

        public var id: UUID = UUID()
        public var sessionID: UUID = UUID()
        public var windowIndex: Int = 0
        public var startFrame: Int64 = 0
        public var durationFrames: Int64 = 0
        public var deliveredAt: Date = Date.distantPast
        public var scores: [Float] = []
        public var topLabels: [String] = []
        public var topScores: [Float] = []
        /// Linear RMS and peak sample amplitude (0...1) of the window's audio; nil if not measurable.
        public var rms: Float?
        public var peak: Float?
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), sessionID: UUID, windowIndex: Int,
            startFrame: Int64, durationFrames: Int64, deliveredAt: Date,
            scores: [Float], topLabels: [String], topScores: [Float],
            rms: Float?, peak: Float?,
            schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.sessionID = sessionID
            self.windowIndex = windowIndex
            self.startFrame = startFrame
            self.durationFrames = durationFrames
            self.deliveredAt = deliveredAt
            self.scores = scores
            self.topLabels = topLabels
            self.topScores = topScores
            self.rms = rms
            self.peak = peak
            self.schemaVersion = schemaVersion
        }
    }

    /// Append-only review label. The latest annotation per (target, label) wins at read time; a V1
    /// row's legacy `isFalsePositive` is the baseline before any annotation exists.
    @Model
    public final class DetectionAnnotation {
        #Index<DetectionAnnotation>([\.targetWindowID], [\.targetLegacyEventID])

        public var id: UUID = UUID()
        public var targetWindowID: UUID?
        public var targetLegacyEventID: UUID?
        public var label: String = ""
        public var verdict: String = ""
        public var createdAt: Date = Date.distantPast
        public var source: String = ""
        public var note: String?
        public var appVersion: String = ""
        public var schemaVersion: Int = 0

        public init(
            id: UUID = UUID(), targetWindowID: UUID?, targetLegacyEventID: UUID?,
            label: String, verdict: String, createdAt: Date, source: String, note: String? = nil,
            appVersion: String, schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.targetWindowID = targetWindowID
            self.targetLegacyEventID = targetLegacyEventID
            self.label = label
            self.verdict = verdict
            self.createdAt = createdAt
            self.source = source
            self.note = note
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }
    }
}
