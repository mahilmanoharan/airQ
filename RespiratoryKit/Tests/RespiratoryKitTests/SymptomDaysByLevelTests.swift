import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Symptom days by air and pollen level")
struct SymptomDaysByLevelTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private func day(_ key: String) -> LocalDay { LocalDay(key: key, in: zone)! }  // fixed valid keys below

    /// A whole day of hourly points at `peak` (18+ hours, so it counts).
    private func hours(_ key: String, peak: Int) -> [EnvironmentSeries.AQIPoint] {
        (0..<20).map { EnvironmentSeries.AQIPoint(date: day(key).interval.start.addingTimeInterval(Double($0) * 3_600),
                                                  value: $0 == 10 ? peak : 20, source: "googleAirQuality") }
    }

    private func checkIn(_ key: String, symptoms: Bool?) -> ChartData.CheckInPoint {
        ChartData.CheckInPoint(day: day(key).interval.start, severity: nil, daytimeSymptoms: symptoms, nightWaking: nil,
                               rescueInhalerUses: nil, controllerAdherence: nil)
    }

    private func data(hourly: [EnvironmentSeries.AQIPoint], pollen: [ChartData.PollenBar],
                      checkIns: [ChartData.CheckInPoint]) -> ChartData {
        ChartData(domain: DateInterval(start: day("2026-09-01").interval.start, end: day("2026-09-10").interval.end),
                  days: [], waqi: [], hourly: hourly, pollen: pollen, detections: [], checkIns: checkIns, context: [],
                  detectionLabel: "cough", hourOfDay: [])
    }

    @Test("Answered days are counted in their day's air band and pollen level, with the yes answers")
    func counts() {
        let table = SymptomDaysByLevel.make(from: data(
            hourly: hours("2026-09-01", peak: 40) + hours("2026-09-02", peak: 45) + hours("2026-09-03", peak: 130),
            pollen: [.init(day: day("2026-09-01").interval.start, code: "TREE", upi: 1),
                     .init(day: day("2026-09-01").interval.start, code: "GRASS", upi: 4),
                     .init(day: day("2026-09-02").interval.start, code: "GRASS", upi: 1)],
            checkIns: [checkIn("2026-09-01", symptoms: true), checkIn("2026-09-02", symptoms: false),
                       checkIn("2026-09-03", symptoms: true)]), timeZone: zone)
        #expect(table.air == [.init(level: .good, days: 2, symptomDays: 1), .init(level: .sensitive, days: 1, symptomDays: 1)])
        // A day's pollen level is its highest type.
        #expect(table.pollen == [.init(level: 1, days: 1, symptomDays: 0), .init(level: 4, days: 1, symptomDays: 1)])
    }

    @Test("Unanswered days, days with too few air hours and days without a level are left out, not guessed")
    func leavesOut() {
        let partial = Array(hours("2026-09-04", peak: 160).prefix(10))
        let table = SymptomDaysByLevel.make(from: data(
            hourly: hours("2026-09-01", peak: 40) + partial,
            pollen: [],
            checkIns: [checkIn("2026-09-01", symptoms: nil), checkIn("2026-09-04", symptoms: true),
                       checkIn("2026-09-05", symptoms: true)]), timeZone: zone)
        #expect(table.air.isEmpty && table.pollen.isEmpty && table.isEmpty)
    }

    @Test("The shareable summary lists the same counts, and says what they can't show")
    func inSummary() {
        let chart = data(hourly: hours("2026-09-01", peak: 40) + hours("2026-09-03", peak: 130),
                         pollen: [.init(day: day("2026-09-03").interval.start, code: "GRASS", upi: 4)],
                         checkIns: [checkIn("2026-09-01", symptoms: false), checkIn("2026-09-03", symptoms: true)])
        let text = ClinicianSummary.make(from: chart, timeZone: zone, tuning: DetectionTuningParameters()).text
        #expect(text.contains("- Air good: symptoms on 0 of 1 day."))
        #expect(text.contains("- Air unhealthy for sensitive groups: symptoms on 1 of 1 day."))
        #expect(text.contains("- Pollen index 4: symptoms on 1 of 1 day."))
        #expect(text.contains("don't show that the air or pollen caused the symptoms"))
    }
}
