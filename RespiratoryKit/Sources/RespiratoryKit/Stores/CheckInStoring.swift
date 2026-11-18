import Foundation
import SwiftData

public protocol CheckInStoring: Sendable {
    func checkInRows() async throws -> [CheckInRow]
    func dailyRecords() async throws -> [DailyRecordSnapshot]
    func appendCheckIn(_ draft: CheckInDraft, recordedAt: Date, timeZone: TimeZone, completionSeconds: Double?,
                       appVersion: String) async throws
}

extension RecordStore: CheckInStoring {
    public func checkInRows() throws -> [CheckInRow] {
        try modelContext.fetch(FetchDescriptor<DailyCheckIn>(sortBy: [SortDescriptor(\.recordedAt)])).map {
            CheckInRow(id: $0.id,
                       draft: CheckInDraft(dayKey: $0.dayKey, daytimeSymptoms: $0.daytimeSymptoms,
                                           daytimeSeverity: $0.daytimeSeverity, nightWaking: $0.nightWaking,
                                           rescueInhalerUses: $0.rescueInhalerUses, activityLimited: $0.activityLimited,
                                           symptomsSelected: $0.symptomsSelected, windowsOpen: $0.windowsOpen,
                                           peakFlowLPM: $0.peakFlowLPM, peakFlowMeasuredAt: $0.peakFlowMeasuredAt,
                                           controllerAdherence: $0.controllerAdherence),
                       recordedAt: $0.recordedAt, recordedTimeZoneID: $0.recordedTimeZoneID,
                       questionSetVersion: $0.questionSetVersion, symptomsPresented: $0.symptomsPresented,
                       completionSeconds: $0.completionSeconds)
        }
    }

    /// Validates against the current question set, then appends a row (never updates one).
    public func appendCheckIn(_ draft: CheckInDraft, recordedAt: Date, timeZone: TimeZone, completionSeconds: Double?,
                              appVersion: String) throws {
        try requireWritesAvailable()
        guard LocalDay(key: draft.dayKey, in: timeZone) != nil else { throw CheckInError.invalidDay(draft.dayKey) }
        if let severity = draft.daytimeSeverity {
            guard draft.daytimeSymptoms == true else { throw CheckInError.severityWithoutSymptoms }
            guard CheckInQuestionSet.Severity(rawValue: severity) != nil else { throw CheckInError.invalidSeverity }
        }
        if let uses = draft.rescueInhalerUses, !CheckInQuestionSet.rescueUsesRange.contains(uses) {
            throw CheckInError.invalidRescueUses
        }
        if let flow = draft.peakFlowLPM, !CheckInQuestionSet.peakFlowRange.contains(flow) {
            throw CheckInError.invalidPeakFlow
        }
        if let windows = draft.windowsOpen, CheckInQuestionSet.WindowsOpen(rawValue: windows) == nil {
            throw CheckInError.invalidWindowsAnswer
        }
        if let adherence = draft.controllerAdherence, CheckInQuestionSet.ControllerAdherence(rawValue: adherence) == nil {
            throw CheckInError.invalidAdherenceAnswer
        }
        if draft.daytimeSymptoms == false, !draft.symptomsSelected.isEmpty {
            throw CheckInError.symptomsWithoutDaytimeSymptoms
        }
        if let unknown = draft.symptomsSelected.first(where: { !CheckInQuestionSet.symptoms.contains($0) }) {
            throw CheckInError.unknownSymptom(unknown)
        }
        try ensureDay(containing: recordedAt, in: timeZone, appVersion: appVersion)
        let row = DailyCheckIn(dayKey: draft.dayKey, recordedAt: recordedAt, recordedTimeZoneID: timeZone.identifier,
                               questionSetVersion: CheckInQuestionSet.version,
                               symptomsPresented: CheckInQuestionSet.symptoms, appVersion: appVersion)
        row.daytimeSymptoms = draft.daytimeSymptoms
        row.daytimeSeverity = draft.daytimeSeverity
        row.nightWaking = draft.nightWaking
        row.rescueInhalerUses = draft.rescueInhalerUses
        row.activityLimited = draft.activityLimited
        row.symptomsSelected = CheckInQuestionSet.symptoms.filter(draft.symptomsSelected.contains)
        row.windowsOpen = draft.windowsOpen
        row.peakFlowLPM = draft.peakFlowLPM
        row.peakFlowMeasuredAt = draft.peakFlowLPM == nil ? nil : draft.peakFlowMeasuredAt
        row.controllerAdherence = draft.controllerAdherence
        row.completionSeconds = completionSeconds
        modelContext.insert(row)
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
    }
}

/// What a quick "no symptoms today" entry did.
public enum QuickCheckInOutcome: Sendable, Equatable {
    case saved(dayKey: String)
    /// Today's latest check-in already answers every symptom question with "none".
    case alreadyLogged
    /// Today already records a symptom; a quick entry never overwrites one (the form can).
    case todayHasSymptoms
}

extension RecordStore {
    /// "No symptoms today" without the form (Siri, Shortcuts, a control): today's latest answers with every
    /// symptom question answered "none", appended like any check-in. Medication, windows and peak flow keep
    /// whatever today already says. It has no form time, so `completion_seconds` is empty in exports.
    public func logNoSymptoms(at now: Date, timeZone: TimeZone, appVersion: String) throws -> QuickCheckInOutcome {
        try requireWritesAvailable()
        let today = LocalDay(containing: now, in: timeZone).key
        let existing = CheckInAnalysis.latestPerDay(try checkInRows())[today]?.draft
        if existing?.reportsSymptoms == true { return .todayHasSymptoms }
        var draft = existing ?? CheckInDraft(dayKey: today)
        draft.answerNoSymptoms()
        if draft == existing { return .alreadyLogged }
        try appendCheckIn(draft, recordedAt: now, timeZone: timeZone, completionSeconds: nil, appVersion: appVersion)
        return .saved(dayKey: today)
    }
}
