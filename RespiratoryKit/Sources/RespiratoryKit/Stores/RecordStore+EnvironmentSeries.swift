import Foundation
import SwiftData

extension RecordStore {
    /// Hourly index code charted from hourly history.
    public static let chartHourlyIndex = "usa_epa"

    /// Series for `interval`. With a `place`, only records requested within
    /// `RecordPlace.sameAreaKilometres` of it (the dashboard's "here"); without one, every place,
    /// with hourly values kept once per hour per place (history is per location).
    public func environmentSeries(in interval: DateInterval, near place: RecordPlace? = nil) throws -> EnvironmentSeries {
        let lower = interval.start, upper = interval.end
        // A provider calendar date may belong to this domain even when requested outside it.
        // Expand the UTC day keys by one day to cover every possible display time zone; the
        // chart applies the exact local-domain filter after interpreting the date label.
        let forecastLower = LocalDay(containing: lower, in: .gmt).previous.key
        let forecastUpper = LocalDay(containing: upper, in: .gmt).next.key
        let success = EnvironmentalAttemptRecord.Status.success.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<EnvironmentalObservation>(
            predicate: #Predicate {
                $0.status == success && (($0.requestedAt >= lower && $0.requestedAt < upper)
                    || (($0.forecastDate ?? "") >= forecastLower && ($0.forecastDate ?? "") < forecastUpper))
            },
            sortBy: [SortDescriptor(\.requestedAt)]))
            .filter { row in place.map { $0.contains(latitude: row.requestLatitude, longitude: row.requestLongitude) } ?? true }
        var waqi: [EnvironmentSeries.AQIPoint] = []
        var pollen: [EnvironmentSeries.PollenReading] = []
        var days: Set<String> = []
        for row in rows {
            let requestedInDomain = row.requestedAt >= lower && row.requestedAt < upper
            if requestedInDomain, let zone = TimeZone(identifier: row.requestTimeZoneID) {
                days.insert(LocalDay(containing: row.requestedAt, in: zone).key)
            }
            if requestedInDomain, let aqi = row.aqi {
                // The station's own observation time when it parses; otherwise when we asked.
                let observed = row.observedAtISO.flatMap { try? Date($0, strategy: .iso8601) } ?? row.requestedAt
                waqi.append(.init(date: observed, value: aqi, source: "waqi"))
            }
            for type in row.pollenTypes ?? [] {
                if let upi = type.upi {
                    pollen.append(.init(requestedAt: row.requestedAt, code: type.code, upi: upi,
                                        forecastDate: row.forecastDate))
                }
            }
        }
        // Where each history page was requested. A page answers hours before its request time, so
        // look from the interval start with no upper bound.
        let historyKind = "history"
        let pages = try modelContext.fetch(FetchDescriptor<EnvironmentalObservation>(predicate: #Predicate {
            $0.requestKind == historyKind && $0.status == success && $0.requestedAt >= lower
        }))
        let pagePlace = Dictionary(pages.map { ($0.id, ($0.requestLatitude, $0.requestLongitude)) },
                                   uniquingKeysWith: { first, _ in first })
        let hours = try modelContext.fetch(FetchDescriptor<HourlyAirQuality>(
            predicate: #Predicate { $0.hourStart >= lower && $0.hourStart < upper }, sortBy: [SortDescriptor(\.hourStart)]))
        // Overlapping pages repeat hours: keep one value per hour per place. With a `place`, every
        // kept row is from that area, so one per hour; without one, request coordinates are grouped
        // with the same 10 km rule used everywhere else (`RecordPlace.sameAreaKilometres`).
        var areas: [RecordPlace] = []
        func area(of coordinate: (Double?, Double?)?) -> Int {
            guard place == nil, let latitude = coordinate?.0, let longitude = coordinate?.1 else { return -1 }
            let point = RecordPlace(latitude: latitude, longitude: longitude)
            if let index = areas.firstIndex(where: { $0.kilometres(to: point) <= RecordPlace.sameAreaKilometres }) {
                return index
            }
            areas.append(point)
            return areas.count - 1
        }
        struct HourKey: Hashable { let hour: Date; let area: Int }
        var seen: Set<HourKey> = []
        var hourly: [EnvironmentSeries.AQIPoint] = []
        for hour in hours {
            let coordinate = pagePlace[hour.observationID]
            if let place, !place.contains(latitude: coordinate?.0 ?? nil, longitude: coordinate?.1 ?? nil) { continue }
            guard let value = hour.indexes?.first(where: { $0.code == Self.chartHourlyIndex })?.aqi else { continue }
            guard seen.insert(HourKey(hour: hour.hourStart, area: area(of: coordinate))).inserted else { continue }
            let origin: RecordPlace?
            if let latitude = coordinate?.0, let longitude = coordinate?.1 {
                origin = RecordPlace(latitude: latitude, longitude: longitude)
            } else { origin = nil }
            hourly.append(.init(date: hour.hourStart, value: value, source: Self.chartHourlyIndex, place: origin))
        }
        return EnvironmentSeries(waqi: waqi, hourly: hourly, pollen: pollen, successDayKeys: days)
    }
}
