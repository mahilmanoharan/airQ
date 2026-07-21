import Foundation
import Testing
@testable import AirQualityKit

@Suite("TimelineScheduler")
struct TimelineSchedulerTests {

    @Test("Produces a real entry from a present snapshot")
    func makeEntriesWithSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = now.addingTimeInterval(-120)
        let snapshot = AQSnapshot(aqi: 42, locationName: "San Francisco", lastUpdated: updated)

        let entries = TimelineScheduler.makeEntries(from: snapshot, currentDate: now)

        #expect(entries.count == 1)
        #expect(entries[0].date == now)
        #expect(entries[0].aqi == 42)
        #expect(entries[0].locationName == "San Francisco")
        #expect(entries[0].lastUpdated == updated)
        #expect(entries[0].hasData == true)
    }

    @Test("Produces a placeholder entry when no snapshot has ever been written")
    func makeEntriesWithoutSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let entries = TimelineScheduler.makeEntries(from: nil, currentDate: now)

        #expect(entries.count == 1)
        #expect(entries[0].aqi == nil)
        #expect(entries[0].locationName == "Current Location")
        #expect(entries[0].lastUpdated == nil)
        #expect(entries[0].hasData == false)
    }

    @Test("Still surfaces a stale snapshot as data rather than as a placeholder")
    func makeEntriesWithStaleSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let staleUpdate = now.addingTimeInterval(-60 * 60 * 6) // 6 hours old
        let snapshot = AQSnapshot(aqi: 88, locationName: "Oakland", lastUpdated: staleUpdate)

        let entries = TimelineScheduler.makeEntries(from: snapshot, currentDate: now)

        #expect(entries[0].hasData == true)
        #expect(entries[0].lastUpdated == staleUpdate)
    }

    @Test("Schedules the next refresh exactly 30 minutes later")
    func nextRefreshDateIsThirtyMinutesLater() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let next = TimelineScheduler.nextRefreshDate(after: now)

        #expect(next.timeIntervalSince(now) == 30 * 60)
    }
}
