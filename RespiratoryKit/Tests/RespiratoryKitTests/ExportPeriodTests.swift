import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Export period")
struct ExportPeriodTests {
    private var la: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }
    private func date(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }

    @Test("Everything has no limit")
    func everything() throws {
        #expect(ExportPeriod.everything.range(now: try date("2026-09-28T12:00:00Z"), calendar: la) == nil)
    }

    @Test("Last 30 days starts at local midnight 29 days back and ends just after now")
    func last30() throws {
        let now = try date("2026-09-28T19:30:00Z")  // 12:30 PDT on Sep 28
        let range = try #require(ExportPeriod.last30.range(now: now, calendar: la))
        let parts = la.dateComponents([.year, .month, .day, .hour, .minute], from: range.start)
        #expect(parts.year == 2026 && parts.month == 8 && parts.day == 30 && parts.hour == 0 && parts.minute == 0)
        #expect(range.end == now.addingTimeInterval(60))
        #expect(range.contains(now))
    }

    @Test("A daylight-saving change inside the period doesn't move the start off midnight")
    func acrossFallBack() throws {
        let now = try date("2026-11-05T20:00:00Z")  // Oct 31 → Nov 1 fall-back is inside the 30 days
        let range = try #require(ExportPeriod.last30.range(now: now, calendar: la))
        let parts = la.dateComponents([.month, .day, .hour], from: range.start)
        #expect(parts.month == 10 && parts.day == 7 && parts.hour == 0)
        // 29 calendar days plus the partial day, with the extra fall-back hour inside.
        #expect(range.duration > 29 * 86_400)
    }

    @Test("90 days reaches further back than 30, and every period has a title")
    func ninety() throws {
        let now = try date("2026-09-28T19:30:00Z")
        let thirty = try #require(ExportPeriod.last30.range(now: now, calendar: la))
        let ninety = try #require(ExportPeriod.last90.range(now: now, calendar: la))
        #expect(ninety.start < thirty.start)
        #expect(ExportPeriod.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(ExportPeriod(rawValue: "last30") == .last30 && ExportPeriod(rawValue: "everything") == .everything)
    }
}
