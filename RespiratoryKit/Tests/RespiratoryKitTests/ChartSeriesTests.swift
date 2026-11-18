import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Chart series")
struct ChartSeriesTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private func utc(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }
    private func day(_ key: String) throws -> LocalDay { try #require(LocalDay(key: key, in: zone)) }

    private func record(_ key: String) throws -> DailyRecordSnapshot {
        let day = try day(key)
        return DailyRecordSnapshot(dayKey: key, dayStart: day.interval.start, dayEnd: day.interval.end,
                                   timeZoneID: zone.identifier, firstSeenAt: day.interval.start)
    }

    private func build(records: [DailyRecordSnapshot] = [], environment: EnvironmentSeries = .init(waqi: [], hourly: [], pollen: [], successDayKeys: []),
                       detections: [DetectionSnapshot] = [], sessions: [ListeningSessionSnapshot] = [],
                       checkIns: [CheckInRow] = []) throws -> ChartData {
        let domain = DateInterval(start: try day("2026-09-10").interval.start, end: try day("2026-09-12").interval.end)
        return ChartSeries.make(domain: domain, timeZone: zone, records: records, environment: environment,
                                detections: detections, sessions: sessions, checkIns: checkIns,
                                tuning: DetectionTuningParameters(confidenceThreshold: 0.5, minInterEventGap: 1),
                                detectionLabel: "cough")
    }

    @Test("Days distinguish not collected from collected-without-data")
    func dayStatus() throws {
        let data = try build(records: [try record("2026-09-10"), try record("2026-09-11")],
                             environment: .init(waqi: [], hourly: [], pollen: [], successDayKeys: ["2026-09-11"]))
        #expect(data.days.map(\.status) == [.collectedNoData, .collected, .notCollected])
    }

    @Test("Detection counts use the tuning, and listening time splits across midnight")
    func detectionsAndListening() throws {
        let base = try utc("2026-09-11T06:59:00Z")  // 23:59 PDT on Sep 10
        let detections = [0.0, 0.5, 30, 90].map {
            DetectionSnapshot(id: UUID(), timestamp: base.addingTimeInterval($0), label: "cough", confidence: 0.8,
                              isFalsePositive: false)
        } + [DetectionSnapshot(id: UUID(), timestamp: base.addingTimeInterval(100), label: "cough", confidence: 0.2,
                               isFalsePositive: false)]
        let session = ListeningSessionSnapshot(id: UUID(), startedAt: base, endedAt: base.addingTimeInterval(120),
                                               endReason: "userStopped", windowCount: 200, lastWindowEnd: nil,
                                               captureSemanticsVersion: 2, inputPortType: nil)
        let data = try build(detections: detections, sessions: [session])
        #expect(data.detections.map(\.count) == [2, 1])  // 23:59:00 (+0.5 merged), 23:59:30 | 00:00:30
        #expect(data.detections.map(\.listeningSeconds) == [60, 60])
        #expect(data.detections.map(\.count).reduce(0, +) == 3)
        // The hour-of-day bins see the same debounced events and the same listening time.
        #expect(data.hourOfDay.map(\.count).reduce(0, +) == 3)
        #expect(data.hourOfDay[23].count == 2 && data.hourOfDay[0].count == 1)
        #expect(data.hourOfDay.map(\.listeningSeconds).reduce(0, +) == 120)
        #expect(data.hasHourOfDayData)
    }

    @Test("Pollen uses the latest forecast requested each local day; check-ins chart components")
    func pollenAndCheckIns() throws {
        let early = try utc("2026-09-11T16:00:00Z"), late = try utc("2026-09-11T22:00:00Z")
        let environment = EnvironmentSeries(waqi: [], hourly: [], pollen: [
            .init(requestedAt: early, code: "GRASS", upi: 1), .init(requestedAt: late, code: "GRASS", upi: 3),
            .init(requestedAt: late, code: "TREE", upi: 2)], successDayKeys: [])
        let checkIn = CheckInRow(id: UUID(), draft: CheckInDraft(dayKey: "2026-09-12", daytimeSymptoms: false,
                                                                   controllerAdherence: "no"),
                                 recordedAt: late, recordedTimeZoneID: zone.identifier, questionSetVersion: 1,
                                 symptomsPresented: [], completionSeconds: nil)
        let data = try build(environment: environment, checkIns: [checkIn])
        #expect(data.pollen.map(\.upi) == [3, 2])
        #expect(data.checkIns.first?.severity == 0)
        #expect(data.checkIns.first?.controllerAdherence == "no")
    }

    @Test("The store charts successful observations and one value per hour")
    func environmentFromStore() async throws {
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let at = try utc("2026-09-11T18:00:00Z")
        var waqi = EnvironmentalAttemptRecord(provider: "waqi", requestKind: "current", requestedAt: at,
                                              timeZoneID: zone.identifier, status: .success, parserVersion: 1, appVersion: "t")
        waqi.aqi = 42
        waqi.observedAtISO = "2026-09-11T10:00:00-07:00"
        try await store.record(waqi)
        var failed = waqi
        failed.id = UUID()
        failed.status = .httpError
        try await store.record(failed)
        for _ in 0..<2 {
            var history = EnvironmentalAttemptRecord(provider: "googleAirQuality", requestKind: "history", requestedAt: at,
                                                     timeZoneID: zone.identifier, status: .success, parserVersion: 1, appVersion: "t")
            history.hours = [.init(hourStart: at, indexes: [.init(code: "usa_epa", aqi: 50, category: nil, dominantPollutant: nil)],
                                   pollutants: nil)]
            try await store.record(history)
        }
        let series = try await store.environmentSeries(in: DateInterval(start: at.addingTimeInterval(-86_400), duration: 172_800))
        #expect(series.waqi.map(\.value) == [42])
        #expect(series.waqi.first?.date == (try utc("2026-09-11T17:00:00Z")))
        #expect(series.hourly.count == 1)
        #expect(series.successDayKeys == ["2026-09-11"])
    }
}
