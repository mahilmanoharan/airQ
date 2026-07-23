import Foundation
import Testing
@testable import AirQualityKit

@Suite("TimelineScheduler")
struct TimelineSchedulerTests {

    @Test("Produces a real entry from a present snapshot")
    func makeEntriesWithSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = now.addingTimeInterval(-120)
        let snapshot = AQSnapshot(
            aqi: 42,
            dominantPollutant: "pm25",
            pollenIndex: 3,
            locationName: "San Francisco",
            lastUpdated: updated
        )

        let entries = TimelineScheduler.makeEntries(from: snapshot, currentDate: now)

        #expect(entries.count == 1)
        #expect(entries[0].date == now)
        #expect(entries[0].aqi == 42)
        #expect(entries[0].dominantPollutant == "pm25")
        #expect(entries[0].pollenIndex == 3)
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
        #expect(entries[0].dominantPollutant == nil)
        #expect(entries[0].pollenIndex == nil)
        #expect(entries[0].locationName == "Current Location")
        #expect(entries[0].lastUpdated == nil)
        #expect(entries[0].hasData == false)
    }

    @Test("Still surfaces a stale snapshot as data rather than as a placeholder")
    func makeEntriesWithStaleSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let staleUpdate = now.addingTimeInterval(-60 * 60 * 6) // 6 hours old
        let snapshot = AQSnapshot(
            aqi: 88,
            dominantPollutant: "o3",
            pollenIndex: 1,
            locationName: "Oakland",
            lastUpdated: staleUpdate
        )

        let entries = TimelineScheduler.makeEntries(from: snapshot, currentDate: now)

        #expect(entries[0].hasData == true)
        #expect(entries[0].lastUpdated == staleUpdate)
    }

    @Test("Schedules the next refresh exactly 60 minutes later")
    func nextRefreshDateIsSixtyMinutesLater() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let next = TimelineScheduler.nextRefreshDate(after: now)

        #expect(next.timeIntervalSince(now) == 60 * 60)
    }
}

@Suite("AQSnapshot freshness")
struct AQSnapshotFreshnessTests {

    @Test("A snapshot updated 10 minutes ago is fresh within an hour")
    func freshWithinInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AQSnapshot(
            aqi: 10,
            dominantPollutant: nil,
            pollenIndex: 0,
            locationName: "Test",
            lastUpdated: now.addingTimeInterval(-10 * 60)
        )

        #expect(snapshot.isFresh(asOf: now) == true)
    }

    @Test("A snapshot updated 90 minutes ago is not fresh within an hour")
    func staleBeyondInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AQSnapshot(
            aqi: 10,
            dominantPollutant: nil,
            pollenIndex: 0,
            locationName: "Test",
            lastUpdated: now.addingTimeInterval(-90 * 60)
        )

        #expect(snapshot.isFresh(asOf: now) == false)
    }
}
