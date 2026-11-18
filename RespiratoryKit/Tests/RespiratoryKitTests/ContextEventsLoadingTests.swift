import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Context events loading and failures") @MainActor
struct ContextEventsLoadingTests {
    private struct Failure: LocalizedError { var errorDescription: String? { "disk full" } }

    private actor StubStore: ContextEventStoring {
        var rows: [ContextEventRow] = []
        var failReads = false
        var failWrites = false
        var appended = 0

        func setFailing(reads: Bool = false, writes: Bool = false) { failReads = reads; failWrites = writes }

        func contextEventRows() async throws -> [ContextEventRow] {
            if failReads { throw Failure() }
            return rows
        }

        func appendContextEvent(_ draft: ContextEventDraft, supersedes: UUID?, isRetraction: Bool,
                                recordedAt: Date, timeZone: TimeZone, appVersion: String) async throws {
            if failWrites { throw Failure() }
            appended += 1
        }
    }

    private let draft = ContextEventDraft(category: ContextEventCategory.travel.rawValue, note: "trip",
                                          startDayKey: "2026-09-01", endDayKey: nil)

    @Test("Load shows a storage error and clears it after a later success")
    func loadError() async {
        let store = StubStore()
        let model = ContextEventsViewModel(store: store, appVersion: "test")
        await store.setFailing(reads: true)
        await model.load()
        #expect(model.errorMessage == "disk full" && model.events.isEmpty && !model.isLoading)
        await store.setFailing()
        await model.load()
        #expect(model.errorMessage == nil)
    }

    @Test("A failed save reports false and keeps the message, so a form can stay open")
    func saveError() async {
        let store = StubStore()
        let model = ContextEventsViewModel(store: store, appVersion: "test")
        await store.setFailing(writes: true)
        #expect(await model.add(draft) == false)
        #expect(model.errorMessage == "disk full" && !model.isSaving)
        #expect(await store.appended == 0)
    }

    @Test("A successful add refreshes from the store")
    func saveRefreshes() async {
        let store = StubStore()
        let model = ContextEventsViewModel(store: store, appVersion: "test")
        #expect(await model.add(draft))
        #expect(await store.appended == 1 && model.errorMessage == nil)
    }
}
