import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Hour of day")
struct HourOfDayTests {
    private let la = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private func utc(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }

    private func session(_ start: Date, _ end: Date) -> ListeningSessionSnapshot {
        ListeningSessionSnapshot(id: UUID(), startedAt: start, endedAt: end, endReason: "userStopped", windowCount: 1,
                                 lastWindowEnd: nil, captureSemanticsVersion: 2, inputPortType: nil)
    }

    private func bins(events: [Date] = [], sessions: [ListeningSessionSnapshot] = [],
                      domain: DateInterval, zone: TimeZone) -> [ChartData.HourBin] {
        ChartSeries.hourOfDay(eventTimes: events, sessions: sessions, domain: domain, timeZone: zone)
    }

    private var wide: DateInterval { DateInterval(start: Date(timeIntervalSince1970: 0), end: .distantFuture) }

    @Test("There are always 24 bins, and events land in their local hour")
    func eventsByLocalHour() throws {
        let events = [try utc("2026-09-11T09:10:00Z"), try utc("2026-09-12T09:50:00Z"), try utc("2026-09-11T10:00:00Z")]
        // 02:10, 02:50, 03:00 PDT
        let result = bins(events: events, domain: wide, zone: la)
        #expect(result.count == 24 && result.map(\.hour) == Array(0..<24))
        #expect(result[2].count == 2 && result[3].count == 1)
        #expect(result.map(\.count).reduce(0, +) == 3)
    }

    @Test("A session across a local hour boundary is credited to both hours")
    func sessionSplitsAtHour() throws {
        let start = try utc("2026-09-12T06:40:00Z")  // 23:40 PDT
        let result = bins(sessions: [session(start, start.addingTimeInterval(40 * 60))], domain: wide, zone: la)
        #expect(result[23].listeningSeconds == 20 * 60 && result[0].listeningSeconds == 20 * 60)
    }

    @Test("Listening outside the domain is clipped away")
    func clipped() throws {
        let start = try utc("2026-09-12T17:00:00Z")
        let domain = DateInterval(start: start.addingTimeInterval(600), end: start.addingTimeInterval(1_200))
        let result = bins(sessions: [session(start, start.addingTimeInterval(3_600))], domain: domain, zone: la)
        #expect(result.map(\.listeningSeconds).reduce(0, +) == 600)
    }

    @Test("The repeated hour on a fall-back day accumulates both passes and no time is lost")
    func daylightSavingFallBack() throws {
        // 2026-11-01: 01:00–02:00 happens twice in Los Angeles.
        let start = try utc("2026-11-01T07:30:00Z")  // 00:30 PDT
        let end = try utc("2026-11-01T11:30:00Z")    // 03:30 PST
        let result = bins(sessions: [session(start, end)], domain: wide, zone: la)
        #expect(result[1].listeningSeconds == 2 * 3_600)
        #expect(result.map(\.listeningSeconds).reduce(0, +) == end.timeIntervalSince(start))
    }

    @Test("A half-hour offset zone bins on its own local hours")
    func halfHourZone() throws {
        let india = TimeZone(identifier: "Asia/Kolkata") ?? .gmt  // UTC+5:30
        let start = try utc("2026-09-12T04:45:00Z")  // 10:15 local
        let result = bins(sessions: [session(start, start.addingTimeInterval(30 * 60))], domain: wide, zone: india)
        #expect(result[10].listeningSeconds == 30 * 60)
    }

    @Test("Chart data reports whether there is anything to show")
    func hasData() {
        let empty = bins(domain: wide, zone: la)
        #expect(!empty.contains { $0.count > 0 || $0.listeningSeconds > 0 })
    }
}
