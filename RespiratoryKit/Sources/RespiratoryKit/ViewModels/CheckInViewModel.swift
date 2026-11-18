import Foundation
import Observation

@MainActor @Observable
public final class CheckInViewModel {
    public enum Target: String, Sendable, CaseIterable, Identifiable {
        case today, yesterday
        public var id: String { rawValue }
    }

    public var target: Target = .today { didSet { if target != oldValue { resetDraft() } } }
    public var draft: CheckInDraft
    public private(set) var rows: [CheckInRow] = []
    public private(set) var records: [DailyRecordSnapshot] = []
    public private(set) var isLoading = false
    private var hasLoadedCheckIns = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var lastSavedAt: Date?
    /// True from `begin` until `finishEditing`: answers are being given, so reloads keep the draft.
    public private(set) var isEditing = false

    private let store: any CheckInStoring
    private let appVersion: String
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private var openedAt: Date
    /// "Today" as of the last draft reset. The draft's day is fixed then, so the screen's day must be too:
    /// a form opened at 23:50 and saved at 00:10 stays the day it was filled in for.
    private var pinnedToday: LocalDay

    public init(store: any CheckInStoring, appVersion: String, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.appVersion = appVersion
        self.timeZone = timeZone
        self.now = now
        let opened = now()
        openedAt = opened
        let today = LocalDay(containing: opened, in: timeZone)
        pinnedToday = today
        draft = CheckInDraft(dayKey: today.key)
    }

    public var targetDay: LocalDay {
        target == .today ? pinnedToday : pinnedToday.previous
    }

    /// The saved check-in the form started from, if the target day already had one.
    public var existing: CheckInRow? { CheckInAnalysis.latestPerDay(rows)[targetDay.key] }

    public var compliance: (checkedIn: Int, days: Int)? {
        CheckInAnalysis.compliance(checkInDays: Set(rows.map(\.draft.dayKey)), records: records, through: now(),
                                   in: timeZone)
    }

    /// Recent saved check-ins, newest day first, with their derived timing.
    public var history: [(row: CheckInRow, timing: CheckInAnalysis.Timing?)] {
        CheckInAnalysis.latestPerDay(rows).values
            .sorted { $0.draft.dayKey > $1.draft.dayKey }
            .map { ($0, CheckInAnalysis.timing(of: $0)) }
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await store.checkInRows()
            let records = try await store.dailyRecords()
            try Task.checkCancellation()
            self.rows = rows
            self.records = records
            hasLoadedCheckIns = true
            // A reload (returning to the app, the tab badge) must never wipe answers being given.
            if !isEditing { resetDraft() }
            errorMessage = nil
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    /// Answers that usually stay the same from day to day, from the latest check-in of an earlier day.
    public struct StableAnswers: Sendable, Equatable {
        public let dayKey: String
        public let controllerAdherence: String?
        public let windowsOpen: String?
    }

    /// Offered as one explicit tap, never prefilled: an unanswered question stays unanswered until the person chooses.
    public var previousStableAnswers: StableAnswers? {
        let earlier = CheckInAnalysis.latestPerDay(rows).values
            .filter { $0.draft.dayKey < targetDay.key && ($0.draft.controllerAdherence != nil || $0.draft.windowsOpen != nil) }
            .max { $0.draft.dayKey < $1.draft.dayKey }
        return earlier.map { StableAnswers(dayKey: $0.draft.dayKey, controllerAdherence: $0.draft.controllerAdherence,
                                           windowsOpen: $0.draft.windowsOpen) }
    }

    /// True while reusing would answer something still unanswered.
    public var canReusePreviousAnswers: Bool {
        guard let previous = previousStableAnswers else { return false }
        return (previous.controllerAdherence != nil && draft.controllerAdherence == nil)
            || (previous.windowsOpen != nil && draft.windowsOpen == nil)
    }

    /// Fills the unanswered medication and windows questions from `previousStableAnswers`; answers given today stay.
    public func reusePreviousAnswers() {
        guard let previous = previousStableAnswers else { return }
        if draft.controllerAdherence == nil { draft.controllerAdherence = previous.controllerAdherence }
        if draft.windowsOpen == nil { draft.windowsOpen = previous.windowsOpen }
    }

    /// One of the last seven local days, for the check-in tab's strip of dots.
    public struct RecentDay: Sendable, Equatable, Identifiable {
        public let dayKey: String
        public let isCheckedIn: Bool
        /// The form can fill in today and yesterday; older days are shown, not editable.
        public let target: Target?
        /// Before airQ was first used: not a missed day, so it isn't drawn as one.
        public let isBeforeFirstUse: Bool
        public var id: String { dayKey }
    }

    /// Oldest first, ending with today (the real today, even if the form was opened before midnight).
    public var recentDays: [RecentDay] {
        let checkedIn = Set(rows.map(\.draft.dayKey))
        var day = LocalDay(containing: now(), in: timeZone)
        // The first day airQ was opened or checked in for (today, when nothing is stored yet).
        let firstUse = (records.map(\.dayKey) + rows.map(\.draft.dayKey) + [day.key]).min() ?? day.key
        var days: [RecentDay] = []
        for offset in 0..<7 {
            let target: Target? = offset == 0 ? .today : offset == 1 ? .yesterday : nil
            days.append(RecentDay(dayKey: day.key, isCheckedIn: checkedIn.contains(day.key), target: target,
                                  isBeforeFirstUse: day.key < firstUse))
            day = day.previous
        }
        return days.reversed()
    }

    /// Whether today has any saved check-in (a quick "no symptoms" entry included).
    public var hasCheckedInToday: Bool { recentDays.last?.isCheckedIn == true }

    /// Today can skip the check-in hub only when the saved record confirms the day is empty.
    public var canStartNewCheckInToday: Bool {
        hasLoadedCheckIns && !isLoading && errorMessage == nil && !isEditing && !hasCheckedInToday
    }

    /// Starts filling in `target` from its saved answers (or blank), dropping any edits not saved.
    public func begin(_ target: Target) {
        self.target = target
        resetDraft()
        isEditing = true
    }

    /// The person left the check-in (saved or not): later reloads may reset the draft again.
    public func finishEditing() { isEditing = false }

    public func answerNoSymptoms() { draft.answerNoSymptoms() }

    public func toggleSymptom(_ symptom: String) {
        if let index = draft.symptomsSelected.firstIndex(of: symptom) {
            draft.symptomsSelected.remove(at: index)
        } else {
            draft.symptomsSelected.append(symptom)
            // Choosing a symptom answers the daytime question.
            if draft.daytimeSymptoms != true { draft.daytimeSymptoms = true }
        }
    }

    /// "No" also clears the chips (as "No symptoms today" does); chips imply "yes", so keeping them
    /// would store a contradiction. Clearing the answer (nil) keeps them for the user to re-answer.
    public func setDaytimeSymptoms(_ value: Bool?) {
        draft.daytimeSymptoms = value
        if value != true { draft.daytimeSeverity = nil }
        if value == false { draft.symptomsSelected = [] }
    }

    /// Stamps the measurement time only when the value actually changes, so reopening a saved
    /// check-in doesn't move an earlier reading's time.
    public func setPeakFlow(_ value: Int?) {
        guard value != draft.peakFlowLPM else { return }
        draft.peakFlowLPM = value
        draft.peakFlowMeasuredAt = value == nil ? nil : now()
    }

    @discardableResult
    public func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let savedAt = now()
        do {
            try await store.appendCheckIn(draft, recordedAt: savedAt, timeZone: timeZone,
                                          completionSeconds: savedAt.timeIntervalSince(openedAt), appVersion: appVersion)
            rows = try await store.checkInRows()
            if let refreshed = try? await store.dailyRecords() { records = refreshed }
            lastSavedAt = savedAt
            openedAt = now()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Starts from the target day's latest answers, if any; otherwise everything unanswered.
    private func resetDraft() {
        pinnedToday = LocalDay(containing: now(), in: timeZone)
        var fresh = existing?.draft ?? CheckInDraft(dayKey: targetDay.key)
        fresh.dayKey = targetDay.key
        draft = fresh
        openedAt = now()
    }
}
