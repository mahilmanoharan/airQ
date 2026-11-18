import Foundation
import SwiftData

/// The wording, scales and chip set in force for a check-in. Any change to a question, scale or
/// chip means a new version, so answers are never compared across different wordings unknowingly.
///
/// Check-in day D asks about "last night (ending the morning of D)" and "today (D)" (decision D5).
/// It resembles, but is not, a validated instrument (e.g. ACT); recall periods and scales differ.
///
/// Version history: 1 = the original set. 2 = adds `controllerAdherence`; every version-1 question
/// is unchanged, so version-1 answers stay comparable question by question.
public enum CheckInQuestionSet {
    public static let version = 2

    /// "Did you take your controller (preventer) medication today as prescribed?" Asked from version 2.
    /// `notPrescribed` separates "no controller" from a missed dose.
    public enum ControllerAdherence: String, Sendable, CaseIterable, Identifiable {
        case yes, partly, no, notPrescribed
        public var id: String { rawValue }
    }

    public enum Severity: Int, Sendable, CaseIterable, Identifiable {
        case mild = 1, moderate = 2, severe = 3
        public var id: Int { rawValue }
    }

    public enum WindowsOpen: String, Sendable, CaseIterable, Identifiable {
        case yes, no, partly
        public var id: String { rawValue }
    }

    /// Chip identifiers (stored), in display order.
    public static let symptoms: [String] = [
        "cough", "wheeze", "shortnessOfBreath", "chestTightness",
        "sneezing", "runnyOrBlockedNose", "itchyEyes", "soreThroat",
    ]

    /// Plausible adult peak-flow range in L/min; values outside are rejected as typos.
    public static let peakFlowRange = 50...900
    public static let rescueUsesRange = 0...50
}

/// One check-in as answered. Every answer is optional: nil means "not answered", never "no".
public struct CheckInDraft: Sendable, Equatable {
    public var dayKey: String
    public var daytimeSymptoms: Bool?
    public var daytimeSeverity: Int?
    public var nightWaking: Bool?
    public var rescueInhalerUses: Int?
    public var activityLimited: Bool?
    public var symptomsSelected: [String]
    public var windowsOpen: String?
    public var peakFlowLPM: Int?
    public var peakFlowMeasuredAt: Date?
    /// A `CheckInQuestionSet.ControllerAdherence` raw value; nil = not answered.
    public var controllerAdherence: String?

    public init(dayKey: String, daytimeSymptoms: Bool? = nil, daytimeSeverity: Int? = nil, nightWaking: Bool? = nil,
                rescueInhalerUses: Int? = nil, activityLimited: Bool? = nil, symptomsSelected: [String] = [],
                windowsOpen: String? = nil, peakFlowLPM: Int? = nil, peakFlowMeasuredAt: Date? = nil,
                controllerAdherence: String? = nil) {
        self.dayKey = dayKey
        self.daytimeSymptoms = daytimeSymptoms
        self.daytimeSeverity = daytimeSeverity
        self.nightWaking = nightWaking
        self.rescueInhalerUses = rescueInhalerUses
        self.activityLimited = activityLimited
        self.symptomsSelected = symptomsSelected
        self.windowsOpen = windowsOpen
        self.peakFlowLPM = peakFlowLPM
        self.peakFlowMeasuredAt = peakFlowMeasuredAt
        self.controllerAdherence = controllerAdherence
    }

    /// "No symptoms today": answers every symptom question explicitly. Environment (windows), peak
    /// flow and medication aren't symptoms, so they're left as they are.
    public mutating func answerNoSymptoms() {
        daytimeSymptoms = false
        daytimeSeverity = nil
        nightWaking = false
        rescueInhalerUses = 0
        activityLimited = false
        symptomsSelected = []
    }

    /// Any symptom answer that isn't "none": a daytime symptom, a chip, night waking, a rescue use or limited activity.
    public var reportsSymptoms: Bool {
        daytimeSymptoms == true || !symptomsSelected.isEmpty || nightWaking == true
            || (rescueInhalerUses ?? 0) > 0 || activityLimited == true
    }

    public var answeredCount: Int {
        [daytimeSymptoms != nil, nightWaking != nil, rescueInhalerUses != nil, activityLimited != nil,
         windowsOpen != nil, controllerAdherence != nil].count(where: \.self)
    }
}

public struct CheckInRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let draft: CheckInDraft
    public let recordedAt: Date
    public let recordedTimeZoneID: String
    public let questionSetVersion: Int
    public let symptomsPresented: [String]
    public let completionSeconds: Double?

    public init(id: UUID, draft: CheckInDraft, recordedAt: Date, recordedTimeZoneID: String,
                questionSetVersion: Int, symptomsPresented: [String], completionSeconds: Double?) {
        self.id = id
        self.draft = draft
        self.recordedAt = recordedAt
        self.recordedTimeZoneID = recordedTimeZoneID
        self.questionSetVersion = questionSetVersion
        self.symptomsPresented = symptomsPresented
        self.completionSeconds = completionSeconds
    }
}

public enum CheckInError: LocalizedError, Sendable, Equatable {
    case invalidDay(String), severityWithoutSymptoms, invalidSeverity, invalidRescueUses, invalidPeakFlow
    case invalidWindowsAnswer, invalidAdherenceAnswer, unknownSymptom(String), symptomsWithoutDaytimeSymptoms

    public var errorDescription: String? {
        switch self {
        case .invalidDay(let key): "\(key) is not a valid date."
        case .severityWithoutSymptoms: "Severity needs daytime symptoms to be answered yes."
        case .invalidSeverity: "Severity must be mild, moderate or severe."
        case .invalidRescueUses: "Rescue inhaler uses must be between 0 and 50."
        case .invalidPeakFlow: "Peak flow must be between 50 and 900 L/min."
        case .invalidWindowsAnswer: "Windows must be yes, no or partly."
        case .invalidAdherenceAnswer: "Controller medication must be yes, partly, no or not prescribed."
        case .unknownSymptom(let symptom): "\(symptom) isn't one of the listed symptoms."
        case .symptomsWithoutDaytimeSymptoms: "Symptoms are selected, but daytime symptoms is answered no."
        }
    }
}
