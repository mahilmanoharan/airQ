import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Context events") @MainActor
struct ContextEventsTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private func makeModel(clock: Clock = Clock()) throws -> (ContextEventsViewModel, RecordStore) {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        return (ContextEventsViewModel(store: store, appVersion: "test", timeZone: zone, now: { clock.tick() }), store)
    }

    private func draft(_ note: String, start: String = "2026-09-01", end: String? = nil) -> ContextEventDraft {
        ContextEventDraft(category: ContextEventCategory.illness.rawValue, note: note, startDayKey: start, endDayKey: end)
    }

    @Test("An edit appends a superseding row; the latest version is shown and history is kept")
    func reviseKeepsHistory() async throws {
        let (model, store) = try makeModel()
        #expect(await model.add(draft("cold")))
        let original = try #require(model.events.first)
        #expect(await model.revise(original, with: draft("  flu  ", end: "2026-09-05")))

        let current = try #require(model.events.first)
        #expect(model.events.count == 1)
        #expect(current.draft.note == "flu" && current.draft.endDayKey == "2026-09-05")
        #expect(current.originalID == original.id && current.revisionCount == 1)
        #expect(try await store.contextEventRows().count == 2)
    }

    @Test("A retraction hides the event but never deletes a row, and it can't be revised afterwards")
    func retraction() async throws {
        let (model, store) = try makeModel()
        await model.add(draft("travel"))
        let event = try #require(model.events.first)
        #expect(await model.retract(event))
        #expect(model.events.isEmpty)
        #expect(model.retracted.first?.draft.note == "travel")
        #expect(try await store.contextEventRows().count == 2)

        let retracted = try #require(model.retracted.first)
        #expect(await model.revise(retracted, with: draft("again")) == false)
        #expect(model.errorMessage == ContextEventError.alreadyRetracted.errorDescription)
    }

    @Test("Only the latest version can be revised, so stale edits can't fork a chain")
    func staleRevision() async throws {
        let (model, _) = try makeModel()
        await model.add(draft("a"))
        let first = try #require(model.events.first)
        await model.revise(first, with: draft("b"))
        #expect(await model.revise(first, with: draft("c")) == false)
        #expect(model.events.map(\.draft.note) == ["b"])
    }

    @Test("Invalid ranges and dates are rejected before anything is written")
    func validation() async throws {
        let (model, store) = try makeModel()
        #expect(await model.add(draft("x", start: "2026-09-05", end: "2026-09-01")) == false)
        #expect(model.errorMessage == ContextEventError.endBeforeStart.errorDescription)
        #expect(await model.add(draft("x", start: "2026-02-30")) == false)
        #expect(try await store.contextEventRows().isEmpty)
    }

    @Test("Resolution tolerates cycles and orders events newest start first")
    func resolutionEdges() {
        let a = UUID(), b = UUID()
        let t = Date(timeIntervalSince1970: 0)
        let rows = [
            ContextEventRow(id: a, draft: draft("a"), recordedAt: t, recordedTimeZoneID: "UTC", supersedesID: b, isRetraction: false),
            ContextEventRow(id: b, draft: draft("b"), recordedAt: t.addingTimeInterval(1), recordedTimeZoneID: "UTC", supersedesID: a, isRetraction: false),
            ContextEventRow(id: UUID(), draft: draft("later", start: "2026-09-10"), recordedAt: t, recordedTimeZoneID: "UTC", supersedesID: nil, isRetraction: false),
        ]
        let resolved = ContextEventResolution.resolve(rows)
        #expect(resolved.first?.draft.note == "later")
        #expect(resolved.count <= 3)
    }
}

/// Strictly increasing timestamps so recordedAt order is deterministic.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(start: Date = Date(timeIntervalSince1970: 1_790_000_000)) { current = start }
    func tick() -> Date {
        lock.withLock {
            current = current.addingTimeInterval(1)
            return current
        }
    }
}
