import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Quick 'no symptoms' check-in")
struct QuickCheckInTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private func utc(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }
    private func store() throws -> RecordStore { RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer()) }

    @Test("With nothing saved today it saves every symptom question as no, for the local day, without a form time")
    func savesForLocalDay() async throws {
        let store = try store()
        // 02:00 UTC on the 21st is still the 20th in Los Angeles.
        let outcome = try await store.logNoSymptoms(at: try utc("2026-09-21T02:00:00Z"), timeZone: zone, appVersion: "t")
        #expect(outcome == .saved(dayKey: "2026-09-20"))
        let rows = try await store.checkInRows()
        #expect(rows.count == 1)
        var expected = CheckInDraft(dayKey: "2026-09-20")
        expected.answerNoSymptoms()
        #expect(rows.first?.draft == expected)
        #expect(rows.first?.completionSeconds == nil)
    }

    @Test("It keeps today's other answers (medication, windows, peak flow) and appends, never edits")
    func keepsOtherAnswers() async throws {
        let store = try store()
        let now = try utc("2026-09-20T19:00:00Z")
        var partial = CheckInDraft(dayKey: "2026-09-20", windowsOpen: "partly", peakFlowLPM: 420,
                                   controllerAdherence: CheckInQuestionSet.ControllerAdherence.yes.rawValue)
        partial.peakFlowMeasuredAt = now
        try await store.appendCheckIn(partial, recordedAt: now, timeZone: zone, completionSeconds: 30, appVersion: "t")
        let outcome = try await store.logNoSymptoms(at: now.addingTimeInterval(60), timeZone: zone, appVersion: "t")
        #expect(outcome == .saved(dayKey: "2026-09-20"))
        let rows = try await store.checkInRows()
        #expect(rows.count == 2)
        #expect(rows.first?.draft == partial)
        let latest = try #require(rows.last?.draft)
        #expect(latest.windowsOpen == "partly" && latest.peakFlowLPM == 420 && latest.controllerAdherence == "yes")
        #expect(latest.daytimeSymptoms == false && latest.rescueInhalerUses == 0)
    }

    @Test("It refuses when today already records a symptom, so a quick entry never overwrites one")
    func refusesOverSymptoms() async throws {
        let now = try utc("2026-09-20T19:00:00Z")
        for symptomatic in [CheckInDraft(dayKey: "2026-09-20", daytimeSymptoms: true),
                            CheckInDraft(dayKey: "2026-09-20", nightWaking: true),
                            CheckInDraft(dayKey: "2026-09-20", rescueInhalerUses: 2),
                            CheckInDraft(dayKey: "2026-09-20", activityLimited: true)] {
            let store = try store()
            try await store.appendCheckIn(symptomatic, recordedAt: now, timeZone: zone, completionSeconds: 30, appVersion: "t")
            let outcome = try await store.logNoSymptoms(at: now.addingTimeInterval(60), timeZone: zone, appVersion: "t")
            #expect(outcome == .todayHasSymptoms)
            #expect(try await store.checkInRows().count == 1)
        }
    }

    @Test("Logging twice adds nothing the second time")
    func idempotent() async throws {
        let store = try store()
        let now = try utc("2026-09-20T19:00:00Z")
        _ = try await store.logNoSymptoms(at: now, timeZone: zone, appVersion: "t")
        let second = try await store.logNoSymptoms(at: now.addingTimeInterval(60), timeZone: zone, appVersion: "t")
        #expect(second == .alreadyLogged)
        #expect(try await store.checkInRows().count == 1)
    }

    @Test("Yesterday's symptoms don't block today")
    func onlyToday() async throws {
        let store = try store()
        let now = try utc("2026-09-20T19:00:00Z")
        try await store.appendCheckIn(CheckInDraft(dayKey: "2026-09-19", daytimeSymptoms: true), recordedAt: now,
                                      timeZone: zone, completionSeconds: 30, appVersion: "t")
        #expect(try await store.logNoSymptoms(at: now, timeZone: zone, appVersion: "t") == .saved(dayKey: "2026-09-20"))
    }
}
