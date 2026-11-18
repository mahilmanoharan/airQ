import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Daily check-in") @MainActor
struct CheckInTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private func utc(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }

    /// Time advances one second per read, so saves are strictly ordered.
    private func makeModel(at iso: String) throws -> (CheckInViewModel, RecordStore) {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let clock = Clock(start: try utc(iso))
        return (CheckInViewModel(store: store, appVersion: "test", timeZone: zone, now: { clock.tick() }), store)
    }

    @Test("The last day's medication and windows answers are offered, fill only what's unanswered, and never prefill")
    func reusesStableAnswers() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        let earlier = try utc("2026-09-18T19:00:00Z")
        try await store.appendCheckIn(CheckInDraft(dayKey: "2026-09-18", windowsOpen: "no",
                                                   controllerAdherence: CheckInQuestionSet.ControllerAdherence.notPrescribed.rawValue),
                                      recordedAt: earlier, timeZone: zone, completionSeconds: 20, appVersion: "t")
        await model.load()
        // Nothing is filled in until the person asks.
        #expect(model.draft.controllerAdherence == nil && model.draft.windowsOpen == nil)
        #expect(model.previousStableAnswers == .init(dayKey: "2026-09-18", controllerAdherence: "notPrescribed", windowsOpen: "no"))
        #expect(model.canReusePreviousAnswers)
        model.draft.windowsOpen = "yes"
        model.reusePreviousAnswers()
        #expect(model.draft.controllerAdherence == "notPrescribed")
        #expect(model.draft.windowsOpen == "yes", "An answer already given today is kept")
        #expect(!model.canReusePreviousAnswers)
    }

    @Test("Only earlier days are offered: nothing when there's no earlier check-in with those answers")
    func noStableAnswers() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        try await store.appendCheckIn(CheckInDraft(dayKey: "2026-09-19", daytimeSymptoms: false), recordedAt: try utc("2026-09-19T19:00:00Z"),
                                      timeZone: zone, completionSeconds: 20, appVersion: "t")
        await model.load()
        #expect(model.previousStableAnswers == nil && !model.canReusePreviousAnswers)
        model.target = .yesterday
        #expect(model.previousStableAnswers == nil)
    }

    @Test("Today opens a new check-in directly only after loading an empty day")
    func directCheckInRequiresLoadedEmptyDay() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        #expect(!model.canStartNewCheckInToday)
        await model.load()
        #expect(model.canStartNewCheckInToday)

        try await store.appendCheckIn(CheckInDraft(dayKey: "2026-09-20", daytimeSymptoms: false),
                                      recordedAt: try utc("2026-09-20T18:00:00Z"),
                                      timeZone: zone, completionSeconds: 10, appVersion: "t")
        await model.load()
        #expect(!model.canStartNewCheckInToday)
    }

    @Test("The week strip is the last seven local days, marks saved days, and only today and yesterday open the form")
    func recentDays() async throws {
        let (model, store) = try makeModel(at: "2026-09-21T02:00:00Z")  // still the 20th in Los Angeles
        #expect(!model.hasCheckedInToday)
        try await store.appendCheckIn(CheckInDraft(dayKey: "2026-09-18", daytimeSymptoms: false),
                                      recordedAt: try utc("2026-09-18T19:00:00Z"), timeZone: zone, completionSeconds: 10, appVersion: "t")
        try await store.appendCheckIn(CheckInDraft(dayKey: "2026-09-20", daytimeSymptoms: true),
                                      recordedAt: try utc("2026-09-21T01:00:00Z"), timeZone: zone, completionSeconds: 10, appVersion: "t")
        await model.load()
        let days = model.recentDays
        #expect(days.map(\.dayKey) == ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"])
        #expect(days.filter(\.isCheckedIn).map(\.dayKey) == ["2026-09-18", "2026-09-20"])
        #expect(days.map(\.target) == [nil, nil, nil, nil, nil, .yesterday, .today])
        #expect(model.hasCheckedInToday)
        // First use is the earliest check-in day here (no day records): earlier days aren't "missed".
        #expect(days.filter(\.isBeforeFirstUse).map(\.dayKey) == ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17"])
    }

    @Test("Beginning a day starts from its saved answers and drops unsaved edits, even for the same day")
    func begin() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        try await store.appendCheckIn(CheckInDraft(dayKey: "2026-09-20", windowsOpen: "partly"),
                                      recordedAt: try utc("2026-09-20T18:00:00Z"), timeZone: zone, completionSeconds: 10, appVersion: "t")
        await model.load()
        model.draft.windowsOpen = "yes"
        model.begin(.today)
        #expect(model.draft.windowsOpen == "partly")
        model.begin(.yesterday)
        #expect(model.draft == CheckInDraft(dayKey: "2026-09-19"))
    }

    @Test("Reloading while a check-in is being filled in keeps its answers; after finishing, it resets again")
    func reloadKeepsEdits() async throws {
        let (model, _) = try makeModel(at: "2026-09-20T19:00:00Z")
        await model.load()
        model.begin(.today)
        model.draft.windowsOpen = "yes"
        await model.load()  // e.g. returning to the app, or the badge refreshing
        #expect(model.draft.windowsOpen == "yes")
        model.finishEditing()
        await model.load()
        #expect(model.draft.windowsOpen == nil)
    }

    @Test("A new check-in starts fully unanswered, never defaulting to no")
    func startsUnanswered() throws {
        let (model, _) = try makeModel(at: "2026-09-20T19:00:00Z")
        #expect(model.draft == CheckInDraft(dayKey: "2026-09-20"))
        #expect(model.draft.answeredCount == 0)
    }

    @Test("No symptoms answers every symptom question explicitly but leaves windows and peak flow alone")
    func noSymptoms() throws {
        let (model, _) = try makeModel(at: "2026-09-20T19:00:00Z")
        model.draft.windowsOpen = "partly"
        model.answerNoSymptoms()
        #expect(model.draft.daytimeSymptoms == false && model.draft.nightWaking == false)
        #expect(model.draft.rescueInhalerUses == 0 && model.draft.activityLimited == false)
        #expect(model.draft.windowsOpen == "partly" && model.draft.peakFlowLPM == nil)
    }

    @Test("Controller adherence is saved with question set 2, survives No symptoms, and rejects unknown answers")
    func controllerAdherence() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        model.draft.controllerAdherence = CheckInQuestionSet.ControllerAdherence.partly.rawValue
        model.answerNoSymptoms()
        #expect(model.draft.controllerAdherence == "partly")
        #expect(model.draft.answeredCount == 5)
        #expect(await model.save())
        let row = try #require(try await store.checkInRows().last)
        #expect(row.draft.controllerAdherence == "partly")
        #expect(row.questionSetVersion == 2)

        model.draft.controllerAdherence = "sometimes"
        #expect(await model.save() == false)
        #expect(model.errorMessage == CheckInError.invalidAdherenceAnswer.errorDescription)
        #expect(try await store.checkInRows().count == 1)
    }

    @Test("Saving appends; re-saving adds a row and the latest per day wins; the form reopens from it")
    func appendOnly() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        await model.load()
        model.setDaytimeSymptoms(true)
        model.draft.daytimeSeverity = 2
        model.toggleSymptom("cough")
        #expect(await model.save())
        model.draft.daytimeSeverity = 3
        #expect(await model.save())

        let rows = try await store.checkInRows()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.questionSetVersion == CheckInQuestionSet.version })
        #expect(rows.first?.symptomsPresented == CheckInQuestionSet.symptoms)
        #expect(model.existing?.draft.daytimeSeverity == 3)
        #expect(model.history.count == 1)
        #expect(try await store.dailyRecords().map(\.dayKey) == ["2026-09-20"])
    }

    @Test("Yesterday is a separate day, and its check-in is derived as backfilled")
    func yesterdayBackfill() async throws {
        let (model, _) = try makeModel(at: "2026-09-20T19:00:00Z")
        await model.load()
        model.target = .yesterday
        #expect(model.draft.dayKey == "2026-09-19")
        model.draft.nightWaking = true
        #expect(await model.save())
        let entry = try #require(model.history.first)
        #expect(entry.timing == .backfilled(days: 1))
        model.target = .today
        #expect(model.draft.nightWaking == nil)
    }

    @Test("Answering no clears selected chips; the store rejects chips with a no answer")
    func noClearsChips() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        model.toggleSymptom("cough")
        #expect(model.draft.daytimeSymptoms == true)
        model.setDaytimeSymptoms(nil)
        #expect(model.draft.symptomsSelected == ["cough"])
        model.setDaytimeSymptoms(false)
        #expect(model.draft.symptomsSelected.isEmpty)

        model.draft.symptomsSelected = ["cough"]
        #expect(await model.save() == false)
        #expect(model.errorMessage == CheckInError.symptomsWithoutDaytimeSymptoms.errorDescription)
        #expect(try await store.checkInRows().isEmpty)
    }

    @Test("Deselecting daytime symptoms clears severity; invalid answers are rejected before writing")
    func validation() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        model.setDaytimeSymptoms(true)
        model.draft.daytimeSeverity = 2
        model.setDaytimeSymptoms(false)
        #expect(model.draft.daytimeSeverity == nil)

        model.draft.daytimeSeverity = 2
        #expect(await model.save() == false)
        #expect(model.errorMessage == CheckInError.severityWithoutSymptoms.errorDescription)
        model.draft.daytimeSeverity = nil
        model.setPeakFlow(20)
        #expect(await model.save() == false)
        #expect(try await store.checkInRows().isEmpty)
    }

    @Test("Compliance counts checked-in days over collection days since the first record")
    func compliance() async throws {
        let (model, store) = try makeModel(at: "2026-09-20T19:00:00Z")
        try await store.ensureDay(containing: try utc("2026-09-17T19:00:00Z"), in: zone, appVersion: "t")
        await model.load()
        model.answerNoSymptoms()
        await model.save()
        let compliance = try #require(model.compliance)
        #expect(compliance.checkedIn == 1 && compliance.days == 4)
    }

    @Test("Re-entering the same peak flow keeps its original measurement time")
    func peakFlowTimeIsStable() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let clock = Clock()
        let model = CheckInViewModel(store: store, appVersion: "t", timeZone: zone, now: { clock.tick() })
        model.setPeakFlow(420)
        let measured = model.draft.peakFlowMeasuredAt
        model.setPeakFlow(420)
        #expect(model.draft.peakFlowMeasuredAt == measured)
        model.setPeakFlow(430)
        #expect(model.draft.peakFlowMeasuredAt != measured)
    }

    @Test("A form opened before midnight and saved after it stays the day it was filled in for")
    func savedAcrossMidnight() async throws {
        final class Time: @unchecked Sendable {
            let lock = NSLock(); var date: Date
            init(_ date: Date) { self.date = date }
            func get() -> Date { lock.withLock { date } }
            func set(_ date: Date) { lock.withLock { self.date = date } }
        }
        let time = Time(try utc("2026-09-21T06:50:00Z"))  // 23:50 PDT on the 20th
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let model = CheckInViewModel(store: store, appVersion: "t", timeZone: zone, now: { time.get() })
        model.answerNoSymptoms()
        time.set(try utc("2026-09-21T07:10:00Z"))  // 00:10 PDT on the 21st
        #expect(model.targetDay.key == "2026-09-20")
        #expect(await model.save())
        #expect(model.existing?.draft.dayKey == "2026-09-20")
        // Reopening the screen moves on to the new day.
        await model.load()
        #expect(model.targetDay.key == "2026-09-21")
    }

    @Test("Timing uses the zone the check-in was recorded in")
    func timingZones() throws {
        let row = CheckInRow(id: UUID(), draft: CheckInDraft(dayKey: "2026-09-20"), recordedAt: try utc("2026-09-21T02:00:00Z"),
                             recordedTimeZoneID: "America/Los_Angeles", questionSetVersion: 1, symptomsPresented: [],
                             completionSeconds: nil)
        #expect(CheckInAnalysis.timing(of: row) == .sameDay)  // 19:00 PDT on the 20th
    }
}
