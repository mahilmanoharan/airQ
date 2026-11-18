import Foundation
import Testing
@testable import RespiratoryKit

@Suite("History and report periods")
struct HistoryPeriodTests {
    @Test("Every history period and report covers the same local dates across daylight saving")
    @MainActor func matchingPeriods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let now = try Date("2026-11-05T18:00:00Z", strategy: .iso8601)
        for period in HistoryPeriod.allCases {
            let export = try #require(period.exportPeriod.range(now: now, calendar: calendar))
            let expected = try #require(calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: calendar.startOfDay(for: now)))
            #expect(export.start == expected)
            #expect(!period.title.isEmpty)
        }
        #expect(HistoryPeriod.allCases.map(\.rawValue) == [7, 30, 90])
    }
}
