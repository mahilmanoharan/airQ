import Foundation
import Testing
@testable import AirQualityKit

@Suite("TimelineScheduler")
struct TimelineSchedulerTests {

    @Test("With Google's dates, tomorrow's pollen is the day keyed tomorrow, even when day 0 is already local tomorrow")
    func pollenTomorrowByProviderDate() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let evening = Date(timeIntervalSince1970: 1_789_434_000)  // 2026-09-14 18:00 PDT = 09-15 01:00 UTC
        let reading = PollenReading(grassIndex: 2, treeIndex: nil, weedIndex: nil,
                                    outlook: [.init(grassIndex: 4, treeIndex: nil, weedIndex: nil)],
                                    firstDayKey: "2026-09-15")
        let snapshot = AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: 2, locationName: "X",
                                  lastUpdated: evening, pollenFetchedAt: evening, pollenTypes: reading)
        // Keyed by Google's date: tomorrow (Sep 15) is day 0. The entry shows it as the flagged
        // headline instead of a separate "tomorrow" line.
        #expect(TimelineScheduler.pollenTomorrow(snapshot, after: evening, calendar: pacific) == 2)
        let entry = TimelineScheduler.makeEntries(from: snapshot, currentDate: evening, calendar: pacific).first
        #expect(entry?.pollenIndex == 2 && entry?.pollenIsTomorrowsForecast == true)
        #expect(reading.dayKeys == ["2026-09-15", "2026-09-16"])
        #expect(reading.overallIndex(forDayKey: "2026-09-16") == 4)
        #expect(reading.overallIndex(forDayKey: "2026-09-14") == nil)
        #expect(DayKey.date("2026-02-30") == nil)
        #expect(PollenReading(grassIndex: 1, treeIndex: nil, weedIndex: nil, firstDayKey: "bad").dayKeys == nil)
    }

    @Test("Without Google's dates, tomorrow's pollen counts outlook days from the fetch day")
    func pollenTomorrow() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let fetched = Date(timeIntervalSince1970: 1_790_582_400)  // 2026-09-28 15:00 UTC
        let reading = PollenReading(grassIndex: 1, treeIndex: nil, weedIndex: nil,
                                    outlook: [.init(grassIndex: 2, treeIndex: nil, weedIndex: nil),
                                              .init(grassIndex: 4, treeIndex: 1, weedIndex: nil)])
        let snapshot = AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: 1, locationName: "X",
                                  lastUpdated: fetched, pollenFetchedAt: fetched, pollenTypes: reading)
        func entry(_ offset: TimeInterval) -> Int? {
            TimelineScheduler.makeEntries(from: snapshot, currentDate: fetched.addingTimeInterval(offset),
                                          calendar: utc).first?.pollenTomorrow
        }
        #expect(entry(0) == 2)
        #expect(entry(86_400) == 4)       // a day later, "tomorrow" is outlook day 2
        #expect(entry(2 * 86_400) == nil) // beyond the outlook
        #expect(entry(-86_400) == nil)    // clock earlier than the fetch
    }

    @Test("Tomorrow is the next local day's forecast, and absent when the forecast skips it")
    func tomorrowForecast() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 1_790_582_400)  // 2026-09-28 15:00 UTC
        func day(_ key: String) -> AirQualityForecastDay { .init(day: key, pollutants: [:], uvIndex: nil) }
        func snapshot(_ days: [String]?) -> AQSnapshot {
            AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: nil, locationName: "X", lastUpdated: now,
                       forecast: days?.map(day))
        }
        let tomorrow = TimelineScheduler.makeEntries(
            from: snapshot(["2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30"]), currentDate: now, calendar: utc)
        #expect(tomorrow.first?.tomorrow?.day == "2026-09-29")
        let gap = TimelineScheduler.makeEntries(from: snapshot(["2026-09-28", "2026-09-30"]), currentDate: now, calendar: utc)
        #expect(gap.first?.tomorrow == nil)
        #expect(TimelineScheduler.makeEntries(from: snapshot(nil), currentDate: now, calendar: utc).first?.tomorrow == nil)
    }

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

        #expect(entries.count >= 1)
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

    @Test("The outlook merges WAQI and pollen by local day from today, skipping days with neither")
    func outlookMerge() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 1_790_582_400)  // 2026-09-28 15:00 UTC
        let range = AirQualityForecastDay.Range.init(min:average:max:)
        let snapshot = AQSnapshot(
            aqi: 1, dominantPollutant: nil, pollenIndex: 2, locationName: "X", lastUpdated: now,
            pollenTypes: PollenReading(grassIndex: 2, treeIndex: nil, weedIndex: nil,
                                       outlook: [.init(grassIndex: 3, treeIndex: nil, weedIndex: nil)],
                                       firstDayKey: "2026-09-28"),
            forecast: [.init(day: "2026-09-27", pollutants: ["pm25": range(1, 2, 90)], uvIndex: nil),
                       .init(day: "2026-09-28", pollutants: ["pm25": range(1, 2, 51)], uvIndex: nil),
                       .init(day: "2026-09-30", pollutants: ["pm10": range(1, 2, 20)], uvIndex: nil)])
        let outlook = TimelineScheduler.makeEntries(from: snapshot, currentDate: now, calendar: utc).first?.outlook
        #expect(outlook == [OutlookDay(dayKey: "2026-09-28", aqiPeak: 51, pollenIndex: 2),
                            OutlookDay(dayKey: "2026-09-29", aqiPeak: nil, pollenIndex: 3),
                            OutlookDay(dayKey: "2026-09-30", aqiPeak: 20, pollenIndex: nil)])
    }

    @Test("Tomorrow for the dashboard: the next local day's forecast peak and dated pollen, or nil when neither")
    func tomorrowForDashboard() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 1_790_582_400)  // 2026-09-28 15:00 UTC
        let range = AirQualityForecastDay.Range.init(min:average:max:)
        let dated = PollenReading(grassIndex: 2, treeIndex: nil, weedIndex: nil,
                                  outlook: [.init(grassIndex: 3, treeIndex: 1, weedIndex: nil)], firstDayKey: "2026-09-28")
        let snapshot = AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: 2, locationName: "X", lastUpdated: now,
                                  pollenTypes: dated,
                                  forecast: [.init(day: "2026-09-29", pollutants: ["pm25": range(10, 30, 68),
                                                                                   "o3": range(5, 9, 40)], uvIndex: nil)])
        #expect(TimelineScheduler.tomorrow(for: snapshot, now: now, calendar: utc)
                == OutlookDay(dayKey: "2026-09-29", aqiPeak: 68, pollenIndex: 3))
        // A day later the same snapshot has nothing for the new "tomorrow".
        #expect(TimelineScheduler.tomorrow(for: snapshot, now: now.addingTimeInterval(86_400), calendar: utc) == nil)
        // Undated pollen (older snapshots) is never guessed from the fetch day here.
        let undated = AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: 2, locationName: "X", lastUpdated: now,
                                 pollenTypes: PollenReading(grassIndex: 2, treeIndex: nil, weedIndex: nil,
                                                            outlook: [.init(grassIndex: 3, treeIndex: nil, weedIndex: nil)]))
        #expect(TimelineScheduler.tomorrow(for: undated, now: now, calendar: utc) == nil)
    }

    @Test("Entries are precomputed at the stale moment and at local midnight, each for its own date")
    func boundaryEntries() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 1_790_582_400)  // 2026-09-28 15:00 UTC
        let reading = PollenReading(grassIndex: 2, treeIndex: nil, weedIndex: nil,
                                    outlook: [.init(grassIndex: 4, treeIndex: nil, weedIndex: nil)],
                                    firstDayKey: "2026-09-28")
        let snapshot = AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: 2, locationName: "X",
                                  lastUpdated: now.addingTimeInterval(-3_600), pollenFetchedAt: now, pollenTypes: reading)
        let entries = TimelineScheduler.makeEntries(from: snapshot, currentDate: now, calendar: utc)
        #expect(entries.map(\.date) == [now, now.addingTimeInterval(2 * 3_600), Date(timeIntervalSince1970: 1_790_640_000)])
        #expect(entries.map(\.isStale) == [false, true, true])
        // Before midnight: today 2, tomorrow 4. After: today is the old tomorrow (4), tomorrow unknown.
        #expect(entries[0].pollenIndex == 2 && entries[0].pollenTomorrow == 4)
        #expect(entries[2].pollenIndex == 4 && entries[2].pollenTomorrow == nil)
    }

    @Test("Headline pollen: an evening fetch whose first day is already tomorrow is shown as tomorrow's")
    func headlinePollenEvening() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let evening = Date(timeIntervalSince1970: 1_789_434_000)  // 2026-09-14 18:00 PDT
        let reading = PollenReading(grassIndex: 3, treeIndex: nil, weedIndex: nil, firstDayKey: "2026-09-15")
        let snapshot = AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: 3, locationName: "X",
                                  lastUpdated: evening, pollenFetchedAt: evening, pollenTypes: reading)
        let first = TimelineScheduler.makeEntries(from: snapshot, currentDate: evening, calendar: pacific).first
        // Shown as tomorrow's forecast (flagged), with no duplicate "tomorrow" line.
        #expect(first?.pollenIndex == 3 && first?.pollenIsTomorrowsForecast == true && first?.pollenTomorrow == nil)
        // Legacy snapshot (no Google dates): a previous day's forecast isn't today's.
        let legacy = AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: 3, locationName: "X", lastUpdated: evening,
                                pollenFetchedAt: evening.addingTimeInterval(-86_400))
        #expect(TimelineScheduler.makeEntries(from: legacy, currentDate: evening, calendar: pacific).first?.pollenIndex == nil)
    }

    @Test("Refresh comes early for the stale boundary and for local midnight; an entry knows it's stale")
    func refreshBoundaries() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let now = Date(timeIntervalSince1970: 1_790_582_400)  // 2026-09-28 15:00 UTC
        func snapshot(updatedAgo: TimeInterval) -> AQSnapshot {
            AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: nil, locationName: "X",
                       lastUpdated: now.addingTimeInterval(-updatedAgo))
        }
        // Turns stale in 20 minutes: refresh then, not in an hour.
        #expect(TimelineScheduler.nextRefreshDate(after: now, snapshot: snapshot(updatedAgo: 160 * 60), calendar: utc)
                == now.addingTimeInterval(20 * 60))
        // Already stale: the regular hour.
        #expect(TimelineScheduler.nextRefreshDate(after: now, snapshot: snapshot(updatedAgo: 5 * 3_600), calendar: utc)
                == now.addingTimeInterval(3_600))
        // 23:30: midnight comes first.
        let lateEvening = Date(timeIntervalSince1970: 1_790_638_200)  // 2026-09-28 23:30 UTC
        #expect(TimelineScheduler.nextRefreshDate(after: lateEvening, snapshot: nil, calendar: utc)
                == Date(timeIntervalSince1970: 1_790_640_000))
        let entries = TimelineScheduler.makeEntries(from: snapshot(updatedAgo: 3 * 3_600), currentDate: now, calendar: utc)
        #expect(entries.first?.isStale == true)
        #expect(TimelineScheduler.makeEntries(from: snapshot(updatedAgo: 60), currentDate: now).first?.isStale == false)
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

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private func snapshot(updated: Date) -> AQSnapshot {
        AQSnapshot(aqi: 1, dominantPollutant: nil, pollenIndex: nil, locationName: "X", lastUpdated: updated)
    }

    @Test("Local midnight is a real wall-clock midnight across DST and half-hour zones",
          arguments: [
              ("America/Los_Angeles", 1_804_060_200.0),  // 2027-03-14 00:30 PST, the 23-hour spring-forward day
              ("Asia/Kolkata", 1_790_582_400.0),         // UTC+5:30
              ("Pacific/Auckland", 1_790_582_400.0),     // UTC+13 in NZ summer time
          ])
    func midnightIsWallClock(zone: String, start: Double) throws {
        let calendar = calendar(zone)
        let now = Date(timeIntervalSince1970: start)
        let entries = TimelineScheduler.makeEntries(from: snapshot(updated: now), currentDate: now, calendar: calendar)
        let midnight = try #require(entries.map(\.date).first { $0 > now && calendar.component(.hour, from: $0) == 0 })
        #expect(calendar.component(.minute, from: midnight) == 0)
        #expect(calendar.startOfDay(for: midnight) == midnight)
        #expect(TimelineScheduler.nextRefreshDate(after: now, snapshot: nil, calendar: calendar) <= midnight)
    }

    @Test("On the 25-hour fall-back day the next midnight is past the 24 h horizon, so the plain refresh covers it")
    func fallBackDay() {
        let calendar = calendar("America/Los_Angeles")
        let now = Date(timeIntervalSince1970: 1_793_518_200)  // 2026-11-01 00:30 PDT
        let entries = TimelineScheduler.makeEntries(from: snapshot(updated: now), currentDate: now, calendar: calendar)
        #expect(entries.map(\.date).allSatisfy { $0 < now.addingTimeInterval(24 * 3_600) })
        #expect(TimelineScheduler.nextRefreshDate(after: now, snapshot: nil, calendar: calendar) == now.addingTimeInterval(3_600))
    }
}
