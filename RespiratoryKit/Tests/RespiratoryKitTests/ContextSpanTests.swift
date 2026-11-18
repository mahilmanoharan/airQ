import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Context spans on the chart")
struct ContextSpanTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private func day(_ key: String) -> LocalDay {
        guard let day = LocalDay(key: key, in: zone) else { preconditionFailure("bad key \(key)") }
        return day
    }

    /// 2026-09-10 through 2026-09-20 inclusive.
    private var domain: DateInterval { DateInterval(start: day("2026-09-10").interval.start, end: day("2026-09-20").interval.end) }

    private func event(_ category: ContextEventCategory, _ start: String, _ end: String? = nil,
                       retracted: Bool = false) -> ContextEventSnapshot {
        ContextEventSnapshot(id: UUID(), originalID: UUID(),
                             draft: ContextEventDraft(category: category.rawValue, note: "n", startDayKey: start, endDayKey: end),
                             firstRecordedAt: .distantPast, lastRecordedAt: .distantPast, revisionCount: 0,
                             isRetracted: retracted)
    }

    @Test("A medication change without an end is one day; illness without an end runs to the domain end")
    func openEndedByCategory() {
        let spans = ChartSeries.contextSpans([event(.medicationChanged, "2026-09-12"), event(.illness, "2026-09-15")],
                                             domain: domain, timeZone: zone)
        #expect(spans.count == 2)
        #expect(spans[0].start == day("2026-09-12").interval.start && spans[0].end == day("2026-09-12").interval.end)
        #expect(!spans[0].isOngoing)
        #expect(spans[1].end == domain.end && spans[1].isOngoing)
    }

    @Test("Spans are clipped to the domain; retracted, outside and malformed events are dropped")
    func clippingAndDropping() {
        let spans = ChartSeries.contextSpans([
            event(.travel, "2026-09-01", "2026-09-11"),
            event(.illness, "2026-09-12", "2026-09-13", retracted: true),
            event(.movedHome, "2026-08-01"),
            event(.other, "not-a-day"),
            event(.travel, "2026-09-18", "bad"),
        ], domain: domain, timeZone: zone)
        #expect(spans.count == 1)
        #expect(spans[0].start == domain.start)
        #expect(spans[0].end == day("2026-09-11").interval.end)
    }

    @Test("An unknown stored category is kept verbatim as a single day")
    func unknownCategory() {
        let unknown = ContextEventSnapshot(
            id: UUID(), originalID: UUID(),
            draft: ContextEventDraft(category: "futureKind", note: "", startDayKey: "2026-09-14", endDayKey: nil),
            firstRecordedAt: .distantPast, lastRecordedAt: .distantPast, revisionCount: 0, isRetracted: false)
        let spans = ChartSeries.contextSpans([unknown], domain: domain, timeZone: zone)
        #expect(spans.map(\.category) == ["futureKind"])
        #expect(spans.first?.end == day("2026-09-14").interval.end)
    }
}
