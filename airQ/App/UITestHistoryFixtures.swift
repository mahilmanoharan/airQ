#if DEBUG
import Foundation
import RespiratoryKit

/// Representative data for screenshots and critical UI tests. Used only with an in-memory store.
@MainActor
enum UITestHistoryFixtures {
    static func seed(records: RecordStore, now: Date = .now) async throws {
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        for offset in 1...18 {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let key = LocalDay(containing: start, in: zone).key
            let level = [0, 0, 1, 2, 1, 0, 0, 3, 2][offset % 9]
            if offset != 7 && offset != 13 {
                let draft = CheckInDraft(dayKey: key, daytimeSymptoms: level > 0,
                    daytimeSeverity: level > 0 ? level : nil, nightWaking: level == 3,
                    rescueInhalerUses: level > 1 ? 2 : 0, activityLimited: level == 3,
                    symptomsSelected: level > 0 ? ["cough"] : [], windowsOpen: offset % 2 == 0 ? "yes" : "no",
                    peakFlowLPM: 430 - level * 35, peakFlowMeasuredAt: start.addingTimeInterval(28_800),
                    controllerAdherence: "yes")
                try await records.appendCheckIn(draft, recordedAt: start.addingTimeInterval(64_800),
                    timeZone: zone, completionSeconds: 24, appVersion: "UI fixture")
            }
            var air = EnvironmentalAttemptRecord(provider: "googleAirQuality", requestKind: "history",
                requestedAt: end.addingTimeInterval(60), timeZoneID: zone.identifier,
                status: .success, parserVersion: 1, appVersion: "UI fixture")
            air.latitude = 37.79; air.longitude = -122.41
            let base = 28 + (offset % 6) * 19
            air.hours = stride(from: start, to: end, by: 3_600).enumerated().map { index, hour in
                .init(hourStart: hour, indexes: [.init(code: "usa_epa", aqi: base + index % 5 * 3,
                    category: nil, dominantPollutant: nil)], pollutants: nil)
            }
            try await records.record(air)
            var station = EnvironmentalAttemptRecord(provider: "waqi", requestKind: "current",
                requestedAt: start.addingTimeInterval(43_200), timeZoneID: zone.identifier,
                status: .success, parserVersion: 1, appVersion: "UI fixture")
            station.aqi = base + 5; station.latitude = 37.79; station.longitude = -122.41
            try await records.record(station)
            var pollen = EnvironmentalAttemptRecord(provider: "googlePollen", requestKind: "forecast",
                requestedAt: start.addingTimeInterval(43_200), timeZoneID: zone.identifier,
                status: .success, parserVersion: 1, appVersion: "UI fixture")
            pollen.forecastDate = key
            pollen.pollenTypes = [.init(code: "TREE", upi: offset % 5, category: nil, inSeason: nil),
                .init(code: "GRASS", upi: offset % 3, category: nil, inSeason: nil)]
            try await records.record(pollen)
        }
    }
}
#endif
