import Foundation
import Testing
@testable import RespiratoryKit

@Suite("LocalDay (DST-safe local calendar days)")
struct LocalDayTests {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!  // Known-valid IANA identifier.

    private func utc(_ iso: String) throws -> Date {
        try Date(iso, strategy: .iso8601)
    }

    @Test("Spring-forward day (2026-03-08) is 23 hours")
    func springForward() throws {
        let day = LocalDay(containing: try utc("2026-03-08T20:00:00Z"), in: losAngeles)
        #expect(day.key == "2026-03-08")
        #expect(day.interval.duration == 82_800)
        #expect(day.interval.start == (try utc("2026-03-08T08:00:00Z")))
    }

    @Test("Fall-back day (2026-11-01) is 25 hours")
    func fallBack() throws {
        let day = LocalDay(containing: try utc("2026-11-01T20:00:00Z"), in: losAngeles)
        #expect(day.key == "2026-11-01")
        #expect(day.interval.duration == 90_000)
        #expect(day.utcOffsetAtStartSeconds == -25_200)
        #expect(day.next.utcOffsetAtStartSeconds == -28_800)
    }

    @Test("An ordinary day is 24 hours")
    func ordinaryDay() throws {
        #expect(LocalDay(containing: try utc("2026-06-15T20:00:00Z"), in: losAngeles).interval.duration == 86_400)
    }

    @Test("Consecutive days tile with no gap or overlap across both transitions",
          arguments: ["2026-03-06T20:00:00Z", "2026-10-30T20:00:00Z"])
    func tiling(startISO: String) throws {
        var day = LocalDay(containing: try utc(startISO), in: losAngeles)
        for _ in 0..<4 {
            let next = day.next
            #expect(day.interval.end == next.interval.start)
            #expect(day.contains(day.interval.end) == false)
            #expect(next.contains(day.interval.end))
            #expect(next.previous == day)
            day = next
        }
    }

    @Test("Both 01:30s on the repeated hour of 2026-11-01 belong to 2026-11-01")
    func repeatedHour() throws {
        let firstOneThirty = try utc("2026-11-01T08:30:00Z")   // 01:30 PDT
        let secondOneThirty = try utc("2026-11-01T09:30:00Z")  // 01:30 PST
        #expect(LocalDay(containing: firstOneThirty, in: losAngeles).key == "2026-11-01")
        #expect(LocalDay(containing: secondOneThirty, in: losAngeles).key == "2026-11-01")
    }

    @Test("Bucketing events across the fall-back transition neither double-counts nor drops any")
    func bucketingConservesCounts() throws {
        let start = try utc("2026-10-31T07:00:00Z")  // 2026-10-31 00:00 PDT
        let end = try utc("2026-11-03T08:00:00Z")    // 2026-11-03 00:00 PST
        let events = stride(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, by: 600)
            .map { Date(timeIntervalSince1970: $0) }

        let counts = Dictionary(grouping: events) { LocalDay(containing: $0, in: losAngeles).key }.mapValues(\.count)

        #expect(counts == ["2026-10-31": 144, "2026-11-01": 150, "2026-11-02": 144])
        #expect(counts.values.reduce(0, +) == events.count)
    }

    @Test("A key round-trips to the same interval; malformed or impossible keys are rejected")
    func keyRoundTrip() throws {
        let fromInstant = LocalDay(containing: try utc("2026-11-01T20:00:00Z"), in: losAngeles)
        #expect(LocalDay(key: "2026-11-01", in: losAngeles) == fromInstant)
        #expect(LocalDay(key: "2026-02-30", in: losAngeles) == nil)
        #expect(LocalDay(key: "yesterday", in: losAngeles) == nil)
    }

    @Test("The same instant can be different local days in different time zones")
    func timeZoneDependence() throws {
        let instant = try utc("2026-06-01T06:00:00Z")
        let london = TimeZone(identifier: "Europe/London")!  // Known-valid IANA identifier.
        #expect(LocalDay(containing: instant, in: losAngeles).key == "2026-05-31")
        #expect(LocalDay(containing: instant, in: london).key == "2026-06-01")
    }
}
