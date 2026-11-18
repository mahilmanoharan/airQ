import Foundation
import SwiftData

/// Additive to SchemaV2: `DailyCheckIn` gains `controllerAdherence` (check-in question set 2), so
/// V2 → V3 is a lightweight migration. Every other model is SchemaV2's, unchanged. Frozen once any
/// device has opened it: change a model only by adding SchemaV4 with a migration stage.
public enum SchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.DetectionEvent.self,
            SchemaV2.ListeningSession.self, SchemaV2.ClassifierWindow.self, SchemaV2.DetectionAnnotation.self,
            SchemaV2.DailyRecord.self, SchemaV2.EnvironmentalObservation.self, SchemaV2.HourlyAirQuality.self,
            DailyCheckIn.self, SchemaV2.ContextEvent.self,
        ]
    }
}

extension SchemaV3 {
    /// SchemaV2's check-in plus `controllerAdherence`. Rows written before question set 2 read nil
    /// there: the question wasn't asked, which is different from "not answered".
    @Model
    public final class DailyCheckIn {
        #Index<DailyCheckIn>([\.dayKey], [\.recordedAt])

        public var id: UUID = UUID()
        /// The local day being described (chosen by the user), not necessarily the day recorded.
        public var dayKey: String = ""
        public var recordedAt: Date = Date.distantPast
        public var recordedTimeZoneID: String = ""
        /// Wording, scales, recall periods and chip set in force for this row.
        public var questionSetVersion: Int = 0
        public var daytimeSymptoms: Bool?
        public var daytimeSeverity: Int?
        /// About the night ending on the morning of `dayKey`.
        public var nightWaking: Bool?
        public var rescueInhalerUses: Int?
        public var activityLimited: Bool?
        public var symptomsPresented: [String] = []
        public var symptomsSelected: [String] = []
        public var windowsOpen: String?
        /// Litres per minute from a physical peak-flow meter.
        public var peakFlowLPM: Int?
        public var peakFlowMeasuredAt: Date?
        public var completionSeconds: Double?
        public var appVersion: String = ""
        public var schemaVersion: Int = 0
        /// `CheckInQuestionSet.ControllerAdherence` raw value (question set ≥ 2); nil = not answered
        /// or not asked (see `questionSetVersion`).
        public var controllerAdherence: String?

        public init(
            id: UUID = UUID(), dayKey: String, recordedAt: Date, recordedTimeZoneID: String,
            questionSetVersion: Int, symptomsPresented: [String],
            appVersion: String, schemaVersion: Int = RespiratoryStore.schemaVersion
        ) {
            self.id = id
            self.dayKey = dayKey
            self.recordedAt = recordedAt
            self.recordedTimeZoneID = recordedTimeZoneID
            self.questionSetVersion = questionSetVersion
            self.symptomsPresented = symptomsPresented
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }
    }
}
