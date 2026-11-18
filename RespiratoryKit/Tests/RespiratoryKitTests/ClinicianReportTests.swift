import Foundation
import PDFKit
import Testing
@testable import RespiratoryKit

@Suite("Clinician report")
struct ClinicianReportTests {
    private let zone = TimeZone(identifier: "America/New_York") ?? .gmt

    @Test("Weekly totals keep separate response denominators and use qualified air and dated forecasts")
    func weeklyTotals() throws {
        let first = try #require(LocalDay(key: "2026-10-25", in: zone))
        let second = first.next
        let third = second.next
        let last = try #require(LocalDay(key: "2026-11-02", in: zone))
        let previousPlace = RecordPlace(latitude: 40.7, longitude: -74)
        let otherPlace = RecordPlace(latitude: 42.4, longitude: -71)
        let hourly = hours(first, count: 18, index: 48, place: previousPlace)
            + hours(third, count: 17, index: 180, place: previousPlace)
            + hours(last, count: 18, index: 70, place: otherPlace)
            + hours(last, count: 1, index: 212, place: previousPlace)
        let environment = EnvironmentSeries(waqi: [], hourly: hourly, pollen: [
            .init(requestedAt: first.interval.start, code: "TREE", upi: 2, forecastDate: first.key),
            .init(requestedAt: first.interval.start, code: "TREE", upi: 4, forecastDate: third.key),
            .init(requestedAt: second.interval.start, code: "TREE", upi: 0, forecastDate: third.key),
            .init(requestedAt: last.interval.start, code: "GRASS", upi: 3),
        ], successDayKeys: [])
        let data = ChartSeries.make(domain: DateInterval(start: first.interval.start, end: last.interval.end),
                                    timeZone: zone, records: [], environment: environment, detections: [], sessions: [],
                                    checkIns: [checkIn(first, symptoms: true, night: nil, rescue: 2, peakFlow: 370),
                                               checkIn(second, symptoms: false, night: true, rescue: nil),
                                               checkIn(third, symptoms: nil, night: false, rescue: 0, peakFlow: 458)],
                                    tuning: .init(), detectionLabel: "cough")
        let report = ClinicianReport.make(from: data, timeZone: zone, tuning: .init())
        #expect(report.weeks.map(\.dayCount) == [2, 7])
        let oldest = try #require(report.weeks.first)
        #expect(oldest.firstDayKey == "2026-10-25" && oldest.lastDayKey == "2026-10-26")
        #expect(oldest.checkInDays == 2)
        #expect(oldest.symptoms == .init(positive: 1, answered: 2))
        #expect(oldest.nightWaking == .init(positive: 1, answered: 1))
        #expect(oldest.rescueInhaler == .init(positive: 1, answered: 1))
        #expect(oldest.peakFlow == 370...370)
        #expect(oldest.airDays == 1 && oldest.highestAQI == 48)
        #expect(oldest.pollenDays == 1 && oldest.pollenAtLeastModerateDays == 0)
        let latest = try #require(report.weeks.last)
        #expect(latest.firstDayKey == "2026-10-27" && latest.lastDayKey == "2026-11-02")
        #expect(latest.symptoms == .init(positive: 0, answered: 0))
        #expect(latest.nightWaking == .init(positive: 0, answered: 1))
        #expect(latest.rescueInhaler == .init(positive: 0, answered: 1))
        #expect(latest.peakFlow == 458...458)
        #expect(latest.airDays == 0 && latest.highestAQI == nil)
        #expect(latest.pollenDays == 2 && latest.pollenAtLeastModerateDays == 1)
        #expect(report.summary.airCoverage.ambiguousHours == 1)
    }

    @Test("A 90-day PDF has one printable page and includes the newest week without exposing private life-event notes")
    func printableReport() async throws {
        let first = try #require(LocalDay(key: "2026-08-05", in: zone))
        let last = try #require(LocalDay(key: "2026-11-02", in: zone))
        let environment = EnvironmentSeries(waqi: [], hourly: [], pollen: [], successDayKeys: [])
        let id = UUID()
        let event = ContextEventSnapshot(id: id, originalID: id,
                                         draft: .init(category: "illness", note: "private note", startDayKey: first.key,
                                                      endDayKey: nil), firstRecordedAt: first.interval.start,
                                         lastRecordedAt: first.interval.start, revisionCount: 1, isRetracted: false)
        let data = ChartSeries.make(domain: DateInterval(start: first.interval.start, end: last.interval.end),
                                    timeZone: zone, records: [], environment: environment, detections: [], sessions: [],
                                    checkIns: [checkIn(last, symptoms: false, night: true, rescue: 0, peakFlow: 410)],
                                    tuning: .init(), detectionLabel: "cough", contextEvents: [event])
        let report = ClinicianReport.make(from: data, timeZone: zone, tuning: .init())
        #expect(report.weeks.count == 13)
        let pdf = try await report.pdfData()
        let document = try #require(PDFDocument(data: pdf))
        #expect(document.pageCount == 1)
        let page = try #require(document.page(at: 0))
        #expect(page.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        let text = try #require(page.string)
        #expect(text.contains("Daytime symptoms") && text.contains("Night waking"))
        #expect(text.contains("Weekly timeline") && text.contains("410"))
        #expect(text.contains("2026-10-27") && text.contains("2026-11-02"))
        #expect(text.contains("0/1"))
        #expect(!text.contains("private note"))
    }

    private func hours(_ day: LocalDay, count: Int, index: Int, place: RecordPlace) -> [EnvironmentSeries.AQIPoint] {
        (0..<count).map { offset in
            .init(date: day.interval.start.addingTimeInterval(Double(offset) * 3_600), value: index,
                  source: "usa_epa", place: place)
        }
    }

    private func checkIn(_ day: LocalDay, symptoms: Bool?, night: Bool?, rescue: Int?, peakFlow: Int? = nil) -> CheckInRow {
        var draft = CheckInDraft(dayKey: day.key)
        draft.daytimeSymptoms = symptoms
        draft.nightWaking = night
        draft.rescueInhalerUses = rescue
        draft.peakFlowLPM = peakFlow
        return CheckInRow(id: UUID(), draft: draft, recordedAt: day.interval.start, recordedTimeZoneID: zone.identifier,
                          questionSetVersion: 2, symptomsPresented: [], completionSeconds: nil)
    }
}
