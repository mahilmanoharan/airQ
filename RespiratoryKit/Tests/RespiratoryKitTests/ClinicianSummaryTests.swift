import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Clinician summary")
struct ClinicianSummaryTests {
    private let zone = TimeZone(identifier: "UTC") ?? .gmt
    private let start = Date(timeIntervalSince1970: 1_789_948_800)  // a UTC midnight (20,717 days since the epoch)

    private func day(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset) * 86_400) }

    private func data(days: Int = 4, hourly: [EnvironmentSeries.AQIPoint] = [], pollen: [ChartData.PollenBar] = [],
                      detections: [ChartData.DetectionBar] = [], checkIns: [ChartData.CheckInPoint] = []) -> ChartData {
        let localDays = (0..<days).map { offset -> ChartData.Day in
            let local = LocalDay(containing: day(offset), in: zone)
            return ChartData.Day(dayKey: local.key, interval: local.interval, status: .collected)
        }
        return ChartData(domain: DateInterval(start: day(0), end: day(days)), days: localDays, waqi: [], hourly: hourly,
                         pollen: pollen, detections: detections, checkIns: checkIns, context: [], detectionLabel: "cough",
                         hourOfDay: [])
    }

    private func hours(on offset: Int, value: Int, count: Int = 24) -> [EnvironmentSeries.AQIPoint] {
        (0..<count).map { .init(date: day(offset).addingTimeInterval(Double($0) * 3_600), value: value, source: "usa_epa") }
    }

    private func checkIn(_ offset: Int, symptoms: Bool?, severity: Int? = nil, night: Bool? = nil, rescue: Int? = nil,
                         controller: String? = nil, peakFlow: Int? = nil) -> ChartData.CheckInPoint {
        .init(day: day(offset), severity: severity, daytimeSymptoms: symptoms, nightWaking: night, rescueInhalerUses: rescue,
              controllerAdherence: controller, peakFlowLPM: peakFlow)
    }

    @Test("Counts what was recorded, leaving unanswered questions out of every denominator")
    func checkInCounts() {
        let summary = ClinicianSummary.make(from: data(checkIns: [
            checkIn(0, symptoms: true, severity: 2, night: true, rescue: 3, controller: "yes", peakFlow: 380),
            checkIn(1, symptoms: false, severity: 0, night: false, rescue: 0, controller: "partly", peakFlow: 450),
            checkIn(2, symptoms: nil, rescue: nil),
        ]), timeZone: zone, tuning: DetectionTuningParameters())
        #expect(summary.dayCount == 4 && summary.checkInDays == 3)
        #expect(summary.symptomAnswered == 2 && summary.symptomDays == 1 && summary.moderateDays == 1)
        #expect(summary.nightWakingAnswered == 2 && summary.nightWakingDays == 1)
        #expect(summary.rescueAnswered == 2 && summary.rescueUses == 3 && summary.rescueDays == 1)
        #expect(summary.adherence == ["yes": 1, "partly": 1])
        #expect(summary.text.contains("Peak flow (own meter): 2 readings, lowest 380, highest 450 L/min."))
        #expect(summary.text.contains("Check-ins: 3 of 4 days."))
        #expect(summary.text.contains("Daytime symptoms: 1 of 2 answered days (mild 0, moderate 1, severe 0)."))
    }

    @Test("Air days use each day's highest hour, skip thin days, and pollen counts index 3 and above")
    func environment() {
        let hourly = hours(on: 0, value: 40) + hours(on: 1, value: 120) + hours(on: 2, value: 210) + hours(on: 3, value: 90, count: 5)
        let pollen: [ChartData.PollenBar] = [.init(day: day(0), code: "GRASS", upi: 1), .init(day: day(0), code: "TREE", upi: 4),
                                             .init(day: day(1), code: "GRASS", upi: 2)]
        let summary = ClinicianSummary.make(from: data(hourly: hourly, pollen: pollen), timeZone: zone, tuning: DetectionTuningParameters())
        #expect(summary.air.good == 1 && summary.air.sensitive == 1 && summary.air.unhealthy == 1 && summary.air.moderate == 0)
        #expect(summary.airPartialDays == 1)
        #expect(summary.worstAirDay?.peak == 210)
        #expect(summary.pollenDays == 2 && summary.pollenHighDays == 1)
    }

    @Test("Sounds are reported with their listening time, and an unlistened period says so")
    func sounds() {
        let heard = ClinicianSummary.make(from: data(detections: [.init(day: day(0), count: 5, listeningSeconds: 3_600),
                                                                   .init(day: day(1), count: 1, listeningSeconds: 7_200)]),
                                          timeZone: zone, tuning: DetectionTuningParameters())
        #expect(heard.coughEvents == 6)
        #expect(heard.text.contains("6 cough sounds in 3.0 hours of listening."))
        let silent = ClinicianSummary.make(from: data(), timeZone: zone, tuning: DetectionTuningParameters())
        #expect(silent.text.contains("The phone was not listening in this period."))
    }

    @Test("An empty period still explains itself and makes no claim about days without data")
    func empty() {
        let text = ClinicianSummary.make(from: data(), timeZone: zone, tuning: DetectionTuningParameters()).text
        #expect(text.contains("Check-ins: 0 of 4 days."))
        #expect(text.contains("No day has enough stored hours to report."))
        #expect(text.contains("not a diagnosis"))
    }
}

@Suite("Clinician summary loading") @MainActor
struct ClinicianSummaryLoadingTests {
    @Test("The report follows the selected period and archive loads clear it")
    func selectedReportPeriod() async throws {
        let zone = TimeZone.gmt
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let today = try #require(LocalDay(key: "2026-11-02", in: zone))
        var draft = CheckInDraft(dayKey: "2026-10-13")
        draft.answerNoSymptoms()
        try await store.appendCheckIn(draft, recordedAt: today.interval.start, timeZone: zone,
                                      completionSeconds: nil, appVersion: "t")
        let model = ClinicianSummaryViewModel(records: store, detections: nil, tuning: { .init() },
                                               timeZone: zone, now: { today.interval.start })
        await model.loadReport(period: .month)
        #expect(model.report?.summary.checkInDays == 1)
        #expect(model.report?.weeks.count == 5)
        await model.loadReport(period: .week)
        #expect(model.report?.summary.checkInDays == 0)
        #expect(model.report?.weeks.map(\.firstDayKey) == ["2026-10-27"])
        await model.load(period: .last30)
        #expect(model.report == nil)
        #expect(model.summary?.checkInDays == 1)
    }

    @Test("A limited archive summary includes only life-event versions saved within its CSV bounds")
    func archiveLifeEvents() async throws {
        let zone = TimeZone.gmt
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let bounds = try #require(ExportPeriod.last7.range(now: now, calendar: calendar))
        let firstDay = LocalDay(containing: bounds.start, in: zone).key
        let included = ContextEventDraft(category: "medicationStarted", note: "included note", startDayKey: firstDay,
                                         endDayKey: nil)
        try await store.appendContextEvent(included, supersedes: nil, isRetraction: false,
                                           recordedAt: bounds.start, timeZone: zone, appVersion: "t")
        let includedID = try #require(try await store.contextEventRows().first?.id)
        try await store.appendContextEvent(.init(category: "medicationStarted", note: "later private note",
                                                 startDayKey: firstDay, endDayKey: nil),
                                           supersedes: includedID, isRetraction: false, recordedAt: bounds.end,
                                           timeZone: zone, appVersion: "t")
        try await store.appendContextEvent(.init(category: "medicationStarted", note: "earlier private note",
                                                 startDayKey: firstDay, endDayKey: nil),
                                           supersedes: nil, isRetraction: false, recordedAt: bounds.start.addingTimeInterval(-1),
                                           timeZone: zone, appVersion: "t")
        var draft = CheckInDraft(dayKey: firstDay)
        draft.answerNoSymptoms()
        try await store.appendCheckIn(draft, recordedAt: bounds.start.addingTimeInterval(-1), timeZone: zone,
                                      completionSeconds: nil, appVersion: "t")
        let model = ClinicianSummaryViewModel(records: store, detections: nil, tuning: { .init() },
                                              timeZone: zone, now: { now })
        await model.load(period: .last7, recordedIn: bounds)
        let text = try #require(model.summary?.text)
        #expect(text.contains("included note"))
        #expect(!text.contains("earlier private note"))
        #expect(!text.contains("later private note"))
        #expect(model.summary?.checkInDays == 0)

        await model.load(period: .last7)
        #expect(model.summary?.text.contains("earlier private note") == true)
        #expect(model.summary?.text.contains("later private note") == true)
        #expect(model.summary?.checkInDays == 1)
    }

    @Test("Everything starts at the first recorded day; a period is whole local days ending today")
    func loads() async throws {
        let zone = TimeZone(identifier: "UTC") ?? .gmt
        let store = RecordStore(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let now = Date(timeIntervalSince1970: 1_790_000_000 + 10 * 86_400)
        var draft = CheckInDraft(dayKey: LocalDay(containing: Date(timeIntervalSince1970: 1_790_000_000), in: zone).key)
        draft.answerNoSymptoms()
        try await store.appendCheckIn(draft, recordedAt: Date(timeIntervalSince1970: 1_790_000_100), timeZone: zone,
                                      completionSeconds: nil, appVersion: "t")
        let model = ClinicianSummaryViewModel(records: store, detections: nil, tuning: { DetectionTuningParameters() },
                                              timeZone: zone, now: { now })
        await model.load(period: .everything)
        #expect(model.summary?.dayCount == 11 && model.summary?.checkInDays == 1)
        await model.load(period: .last30)
        #expect(model.summary?.dayCount == 30 && model.summary?.checkInDays == 1)
        #expect(model.errorMessage == nil)
    }
}

@Suite("Clinician summary life events")
struct ClinicianSummaryLifeEventTests {
    @Test("Life events noted in the period are listed with their dates, notes and ongoing state")
    func listsEvents() {
        let zone = TimeZone(identifier: "UTC") ?? .gmt
        let start = Date(timeIntervalSince1970: 1_789_948_800)
        let days = (0..<5).map { offset -> ChartData.Day in
            let local = LocalDay(containing: start.addingTimeInterval(Double(offset) * 86_400), in: zone)
            return ChartData.Day(dayKey: local.key, interval: local.interval, status: .collected)
        }
        let spans: [ChartData.ContextSpan] = [
            .init(id: UUID(), category: "medicationStarted", note: "Fluticasone 50 mcg", start: start,
                  end: start.addingTimeInterval(86_400), isOngoing: false),
            .init(id: UUID(), category: "illness", note: "", start: start.addingTimeInterval(2 * 86_400),
                  end: start.addingTimeInterval(5 * 86_400), isOngoing: true),
        ]
        let data = ChartData(domain: DateInterval(start: start, end: start.addingTimeInterval(5 * 86_400)), days: days, waqi: [],
                             hourly: [], pollen: [], detections: [], checkIns: [], context: spans, detectionLabel: "cough", hourOfDay: [])
        let text = ClinicianSummary.make(from: data, timeZone: zone, tuning: DetectionTuningParameters()).text
        let first = days[0].dayKey, third = days[2].dayKey
        #expect(text.contains("Life events the person noted"))
        #expect(text.contains("- \(first): Started medication (Fluticasone 50 mcg)"))
        #expect(text.contains("- \(third), ongoing: Illness"))
    }
}
