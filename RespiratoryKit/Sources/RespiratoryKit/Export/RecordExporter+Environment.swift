import CryptoKit
import Foundation
import SwiftData

/// Days, provider requests (with raw bodies) and Google hourly history.
extension RecordExporter {
    func exportDailyRecords(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end
        let writer = try CSVFileWriter(directory: folder, fileName: "daily_records.csv", columns: [
            CSVColumn("id", "text", "Row UUID."),
            CSVColumn("day_key", "text", unit: "yyyy-MM-dd", "Local calendar day on which airQ was opened (a collection opportunity)."),
        ] + CSVColumn.timestamp("day_start", "Start of the local day.")
          + CSVColumn.timestamp("day_end", "Exclusive end; days are 23 or 25 hours at DST changes.") + [
            CSVColumn("time_zone_id", "text", "Time zone the day was first seen in."),
            CSVColumn("utc_offset_at_start_seconds", "integer", unit: "seconds", "UTC offset at day_start."),
        ] + CSVColumn.timestamp("first_seen_at", "First time airQ was opened that day.") + [
            CSVColumn("app_version", "text", "App version (build)."),
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ])
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<DailyRecord>(predicate: #Predicate<DailyRecord> { $0.dayStart >= lo && $0.dayStart < hi }, sortBy: [SortDescriptor(\.dayStart), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                try writer.write([row.id.uuidString, row.dayKey] + f.timestamp(row.dayStart) + f.timestamp(row.dayEnd)
                                 + [row.timeZoneID, f.int(row.utcOffsetAtStartSeconds)] + f.timestamp(row.firstSeenAt)
                                 + [row.appVersion, f.int(row.schemaVersion)])
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<DailyRecord>(predicate: #Predicate<DailyRecord> { $0.dayStart >= lo && $0.dayStart < hi })))
        return writer
    }

    func exportObservations(_ folder: URL, _ rawFolder: URL, _ f: CSVFormat, _ range: DateInterval)
        throws -> (CSVFileWriter, CSVFileWriter, [ExportManifest.File]) {
        let lo = range.start, hi = range.end
        // First pass over parsed columns only, to find the union of dynamic keys.
        var iaqiKeys: Set<String> = []
        var pollenCodes: Set<String> = []
        try forEachBatch(FetchDescriptor<EnvironmentalObservation>(predicate: #Predicate<EnvironmentalObservation> { $0.requestedAt >= lo && $0.requestedAt < hi }, sortBy: [SortDescriptor(\.requestedAt), SortDescriptor(\.id)])) { rows in
            for row in rows {
                iaqiKeys.formUnion(row.subIndices.map { Array($0.keys) } ?? [])
                pollenCodes.formUnion((row.pollenTypes ?? []).map(\.code))
            }
        }
        let iaqi = iaqiKeys.sorted()
        let pollen = pollenCodes.sorted()
        let writer = try CSVFileWriter(directory: folder, fileName: "environmental_observations.csv", columns: [
            CSVColumn("id", "text", "Attempt UUID; joins hourly_air_quality.observation_id and pollen_plants.observation_id."),
            CSVColumn("provider", "text", "waqi, googlePollen or googleAirQuality."),
            CSVColumn("request_kind", "text", "What was requested (e.g. current, forecast, history)."),
        ] + CSVColumn.timestamp("requested_at", "When the request started.")
          + CSVColumn.timestamp("received_at", null: "no response (network failure, skipped or not sent)", "When the response arrived.") + [
            CSVColumn("request_time_zone_id", "text", "Device time zone at request."),
            CSVColumn("status", "text", "success, httpError, decodeError, missingData, networkError, missingCredentials, cancelled, locationUnavailable, skippedBudget or notSent (never left the device; not usage)."),
            CSVColumn("failure_detail", "text", null: "succeeded", "Provider or client error message."),
            CSVColumn("http_status", "integer", null: "no HTTP response", "HTTP status code."),
            CSVColumn("request_latitude", "number", unit: "degrees", null: "no location (locationUnavailable)", "Latitude sent to the provider (rounded)."),
            CSVColumn("request_longitude", "number", unit: "degrees", null: "no location (locationUnavailable)", "Longitude sent to the provider (rounded)."),
            CSVColumn("coordinate_decimals", "integer", null: "no location", "Decimal places the coordinate was rounded to (2 ≈ 1 km)."),
            CSVColumn("request_parameters", "text", null: "none", "Non-secret request parameters as JSON."),
            CSVColumn("page_index", "integer", null: "not paged", "History page, from 0."),
            CSVColumn("raw_response_file", "text", null: "no body received", "Verbatim response body under raw/. The ground truth for re-parsing."),
            CSVColumn("raw_response_bytes", "integer", unit: "bytes", null: "no body received", "Body size."),
            CSVColumn("parser_version", "integer", "Parser that produced the parsed columns; they can be regenerated from the raw body."),
            CSVColumn("aqi", "integer", null: "not a WAQI success", "WAQI station AQI as returned (scale undocumented; appears US-EPA-like)."),
            CSVColumn("dominant_pollutant", "text", null: "not reported", "WAQI dominant pollutant."),
            CSVColumn("station_name", "text", null: "not reported", "WAQI station."),
            CSVColumn("station_idx", "integer", null: "not reported", "WAQI station id."),
            CSVColumn("station_latitude", "number", unit: "degrees", null: "not reported", "Station latitude (distance to request point is derivable)."),
            CSVColumn("station_longitude", "number", unit: "degrees", null: "not reported", "Station longitude."),
            CSVColumn("observed_at_iso", "text", null: "not reported", "WAQI observation time string as returned."),
            CSVColumn("observed_time_zone", "text", null: "not reported", "WAQI observation time zone as returned."),
        ] + iaqi.map {
            CSVColumn("iaqi_\($0)", "number", null: "not reported", "WAQI iaqi.\($0): an AQI sub-index (or weather value for t/h/p/w/dew/wg), NOT a concentration.")
        } + [
            CSVColumn("forecast_date", "text", null: "not a pollen success", "Google Pollen forecast date as returned (UTC-based)."),
        ] + pollen.flatMap { code in [
            CSVColumn("pollen_\(code.lowercased())_upi", "integer", unit: "UPI 0–5", null: "type absent from response (not zero)", "Google Pollen \(code) Universal Pollen Index (forecast)."),
            CSVColumn("pollen_\(code.lowercased())_category", "text", null: "type or index absent", "Category as returned."),
            CSVColumn("pollen_\(code.lowercased())_in_season", "boolean", null: "not reported", "In season, as returned."),
        ] } + [
            CSVColumn("app_version", "text", "App version (build)."),
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ])
        let plants = try CSVFileWriter(directory: folder, fileName: "pollen_plants.csv", columns: [
            CSVColumn("observation_id", "text", "Joins environmental_observations.id."),
            CSVColumn("code", "text", "Plant code as returned."),
            CSVColumn("display_name", "text", null: "not reported", "Plant name as returned."),
            CSVColumn("upi", "integer", unit: "UPI 0–5", null: "index absent (not zero)", "Universal Pollen Index (forecast)."),
            CSVColumn("category", "text", null: "index absent", "Category as returned."),
            CSVColumn("in_season", "boolean", null: "not reported", "In season, as returned."),
        ])
        var rawFiles: [ExportManifest.File] = []
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<EnvironmentalObservation>(predicate: #Predicate<EnvironmentalObservation> { $0.requestedAt >= lo && $0.requestedAt < hi }, sortBy: [SortDescriptor(\.requestedAt), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                var rawName = ""
                if let body = row.rawResponse {
                    try Task.checkCancellation()
                    let isJSON = (try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])) != nil
                    rawName = "raw/\(row.id.uuidString).\(isJSON ? "json" : "txt")"
                    try Task.checkCancellation()
                    try body.write(to: folder.appending(path: rawName))
                    try Task.checkCancellation()
                    rawFiles.append(.init(name: rawName, rows: nil,
                                          sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()))
                }
                let types = Dictionary((row.pollenTypes ?? []).map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
                try writer.write([row.id.uuidString, row.provider, row.requestKind] + f.timestamp(row.requestedAt)
                                 + f.timestamp(row.receivedAt) + [
                    row.requestTimeZoneID, row.status, f.text(row.failureDetail), f.int(row.httpStatus),
                    f.number(row.requestLatitude), f.number(row.requestLongitude), f.int(row.coordinateDecimals),
                    f.text(row.requestParameters), f.int(row.pageIndex), rawName,
                    f.int(row.rawResponse?.count), f.int(row.parserVersion), f.int(row.aqi), f.text(row.dominantPollutant),
                    f.text(row.stationName), f.int(row.stationIdx), f.number(row.stationLatitude),
                    f.number(row.stationLongitude), f.text(row.observedAtISO), f.text(row.observedTimeZone),
                ] + iaqi.map { f.number(row.subIndices?[$0]) } + [f.text(row.forecastDate)]
                  + pollen.flatMap { code in
                    [f.int(types[code]?.upi), f.text(types[code]?.category), f.bool(types[code]?.inSeason)]
                } + [row.appVersion, f.int(row.schemaVersion)])
                for plant in row.plants ?? [] {
                    try plants.write([row.id.uuidString, plant.code, f.text(plant.displayName), f.int(plant.upi),
                                      f.text(plant.category), f.bool(plant.inSeason)])
                }
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<EnvironmentalObservation>(predicate: #Predicate<EnvironmentalObservation> { $0.requestedAt >= lo && $0.requestedAt < hi })))
        return (writer, plants, rawFiles)
    }

    func exportHourly(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end
        var indexCodes: Set<String> = []
        var pollutantCodes: Set<String> = []
        try forEachBatch(FetchDescriptor<HourlyAirQuality>(predicate: #Predicate<HourlyAirQuality> { $0.hourStart >= lo && $0.hourStart < hi }, sortBy: [SortDescriptor(\.hourStart), SortDescriptor(\.id)])) { rows in
            for row in rows {
                indexCodes.formUnion((row.indexes ?? []).map(\.code))
                pollutantCodes.formUnion((row.pollutants ?? []).map(\.code))
            }
        }
        let indexes = indexCodes.sorted()
        let pollutants = pollutantCodes.sorted()
        let writer = try CSVFileWriter(directory: folder, fileName: "hourly_air_quality.csv", columns: [
            CSVColumn("id", "text", "Row UUID."),
            CSVColumn("observation_id", "text", "Joins environmental_observations.id (the request that returned it)."),
            CSVColumn("provider", "text", "Provider (googleAirQuality)."),
        ] + CSVColumn.timestamp("hour_start", "Start of the hour. Overlapping requests repeat hours; de-duplicate by hour_start.") + [
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ] + indexes.flatMap { code in [
            CSVColumn("index_\(code)_aqi", "integer", null: "index absent for this hour", "\(code) index value as returned."),
            CSVColumn("index_\(code)_category", "text", null: "not reported", "\(code) category."),
            CSVColumn("index_\(code)_dominant_pollutant", "text", null: "not reported", "\(code) dominant pollutant."),
        ] } + pollutants.flatMap { code in [
            CSVColumn("pollutant_\(code)_value", "number", null: "not reported", "\(code) concentration as returned."),
            CSVColumn("pollutant_\(code)_units", "text", null: "not reported", "Units string as returned."),
        ] })
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<HourlyAirQuality>(predicate: #Predicate<HourlyAirQuality> { $0.hourStart >= lo && $0.hourStart < hi }, sortBy: [SortDescriptor(\.hourStart), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                let byIndex = Dictionary((row.indexes ?? []).map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
                let byPollutant = Dictionary((row.pollutants ?? []).map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
                try writer.write([row.id.uuidString, row.observationID.uuidString, row.provider]
                                 + f.timestamp(row.hourStart) + [f.int(row.schemaVersion)]
                                 + indexes.flatMap { [f.int(byIndex[$0]?.aqi), f.text(byIndex[$0]?.category),
                                                      f.text(byIndex[$0]?.dominantPollutant)] }
                                 + pollutants.flatMap { [f.number(byPollutant[$0]?.value), f.text(byPollutant[$0]?.units)] })
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<HourlyAirQuality>(predicate: #Predicate<HourlyAirQuality> { $0.hourStart >= lo && $0.hourStart < hi })))
        return writer
    }
}
