import Foundation
import SwiftData

public enum RecordStoreError: LocalizedError, Sendable, Equatable {
    case unknownTimeZone(String)
    case eraseInProgress

    public var errorDescription: String? {
        switch self {
        case .unknownTimeZone(let identifier): "Unknown time zone \(identifier); the record was not saved."
        case .eraseInProgress: "An erase is in progress. Try again when it finishes."
        }
    }
}

/// Owns the daily record and environmental history. As the only writer of `DailyRecord`, it is what
/// guarantees one row per local day without a unique constraint.
@ModelActor
public actor RecordStore {
    private var writesPaused = false

    public func setWritesPaused(_ paused: Bool) { writesPaused = paused }

    func requireWritesAvailable() throws {
        guard !writesPaused else { throw RecordStoreError.eraseInProgress }
    }

    @concurrent
    public static func open(container: ModelContainer) async -> RecordStore {
        RecordStore(modelContainer: container)
    }

    /// Marks `date`'s local day as a collection opportunity. Idempotent: the first sighting wins.
    @discardableResult
    public func ensureDay(containing date: Date, in timeZone: TimeZone, appVersion: String) throws -> String {
        try requireWritesAvailable()
        let key = try insertDayIfNeeded(containing: date, in: timeZone, appVersion: appVersion)
        try save()
        return key
    }

    public func record(_ attempt: EnvironmentalAttemptRecord) throws {
        try requireWritesAvailable()
        guard let timeZone = TimeZone(identifier: attempt.timeZoneID) else {
            throw RecordStoreError.unknownTimeZone(attempt.timeZoneID)
        }
        try insertDayIfNeeded(containing: attempt.requestedAt, in: timeZone, appVersion: attempt.appVersion)

        let observation = EnvironmentalObservation(
            id: attempt.id, provider: attempt.provider, requestKind: attempt.requestKind,
            requestedAt: attempt.requestedAt, requestTimeZoneID: attempt.timeZoneID,
            status: attempt.status.rawValue, parserVersion: attempt.parserVersion, appVersion: attempt.appVersion)
        observation.receivedAt = attempt.receivedAt
        observation.failureDetail = attempt.failureDetail
        observation.httpStatus = attempt.httpStatus
        observation.requestLatitude = attempt.latitude
        observation.requestLongitude = attempt.longitude
        observation.coordinateDecimals = attempt.coordinateDecimals
        observation.requestParameters = attempt.requestParameters
        observation.pageIndex = attempt.pageIndex
        observation.rawResponse = attempt.rawResponse
        observation.aqi = attempt.aqi
        observation.dominantPollutant = attempt.dominantPollutant
        observation.stationName = attempt.stationName
        observation.stationIdx = attempt.stationIdx
        observation.stationLatitude = attempt.stationLatitude
        observation.stationLongitude = attempt.stationLongitude
        observation.observedAtISO = attempt.observedAtISO
        observation.observedTimeZone = attempt.observedTimeZone
        observation.subIndices = attempt.subIndices
        observation.forecastDate = attempt.forecastDate
        observation.pollenTypes = attempt.pollenTypes
        observation.plants = attempt.plants
        modelContext.insert(observation)

        for hour in attempt.hours {
            modelContext.insert(HourlyAirQuality(observationID: attempt.id, provider: attempt.provider,
                                                 hourStart: hour.hourStart, indexes: hour.indexes,
                                                 pollutants: hour.pollutants))
        }
        try save()
    }

    /// Attempts for `provider` since `date` that may have reached it: the usage-budget numerator.
    /// Includes requests remembered by `RequestLedger` from before an erase.
    public func providerRequestCount(provider: String, since date: Date) throws -> Int {
        let counted = EnvironmentalAttemptRecord.Status.allCases.filter(\.mayHaveReachedProvider).map(\.rawValue)
        return try modelContext.fetchCount(FetchDescriptor<EnvironmentalObservation>(predicate: #Predicate {
            $0.provider == provider && $0.requestedAt >= date && counted.contains($0.status)
        })) + RequestLedger.count(provider: provider, since: date)
    }

    /// The most recent attempt for `provider` that may have reached it (including ones remembered by
    /// `RequestLedger`), for rate-limiting collection.
    public func latestRequestAt(provider: String) throws -> Date? {
        let counted = EnvironmentalAttemptRecord.Status.allCases.filter(\.mayHaveReachedProvider).map(\.rawValue)
        var descriptor = FetchDescriptor<EnvironmentalObservation>(
            predicate: #Predicate { $0.provider == provider && counted.contains($0.status) },
            sortBy: [SortDescriptor(\.requestedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let stored = try modelContext.fetch(descriptor).first?.requestedAt
        return [stored, RequestLedger.latest(provider: provider)].compactMap { $0 }.max()
    }

    /// Hours in `interval` that need no further request at `place`: stored from a page requested
    /// there, or inside the span such a page already answered (a missing hour there is a provider
    /// gap, and re-requesting it would re-download whole pages every day). A request's final page
    /// (no nextPageToken) also settles everything back to the start of its requested range. Pages
    /// requested elsewhere don't count: hourly history is per location.
    public func settledHourStarts(provider: String, in interval: DateInterval, at place: RecordPlace) throws -> Set<Date> {
        let lower = interval.start, upper = interval.end
        let success = EnvironmentalAttemptRecord.Status.success.rawValue
        let pages = try modelContext.fetch(FetchDescriptor<EnvironmentalObservation>(predicate: #Predicate {
            $0.provider == provider && $0.requestKind == "history" && $0.status == success && $0.requestedAt >= lower
        })).filter { place.contains(latitude: $0.requestLatitude, longitude: $0.requestLongitude) }
        guard !pages.isEmpty else { return [] }

        // One fetch of (page, hour) pairs for the window instead of one query per page.
        var rows = FetchDescriptor<HourlyAirQuality>(predicate: #Predicate {
            $0.provider == provider && $0.hourStart >= lower && $0.hourStart < upper
        })
        rows.propertiesToFetch = [\.observationID, \.hourStart]
        let hoursByPage = Dictionary(grouping: try modelContext.fetch(rows), by: \.observationID)
            .mapValues { Set($0.map(\.hourStart)) }

        var settled: Set<Date> = []
        /// One request's consecutive successful pages: pages tile its range newest-first, so a
        /// provider gap between two pages (or inside one) lies within the run's span.
        struct Run { var hours: Int?; var lastIndex: Int; var lastAt: Date; var start: Date?; var end: Date? }
        var runs: [Run] = []
        for page in pages.sorted(by: { ($0.requestedAt, $0.pageIndex ?? 0) < ($1.requestedAt, $1.pageIndex ?? 0) }) {
            let hours = hoursByPage[page.id] ?? []
            settled.formUnion(hours)
            let parameters = page.requestParameters.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
                as? [String: Any]
            let requestedHours = parameters?["hours"] as? Int
            let pageSize = parameters?["pageSize"] as? Int
            let requestHour = Date(timeIntervalSince1970: (page.requestedAt.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
            var start = hours.min()
            var end = hours.max().map { $0.addingTimeInterval(3_600) }
            // Only a short page can be a request's last one, so only those raw bodies are read.
            // Final = no nextPageToken (a short page could also just contain a gap).
            if let requestedHours, let pageSize, hours.count < pageSize {
                let body = page.rawResponse.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                let isFinalPage = body.map { (($0["nextPageToken"] as? String) ?? "").isEmpty } ?? false
                if isFinalPage {
                    start = requestHour.addingTimeInterval(-Double(requestedHours) * 3_600)
                    end = end ?? requestHour  // An empty final page answered its whole range with "no data".
                }
            }
            let index = page.pageIndex ?? 0
            if var run = runs.last, index == run.lastIndex + 1, run.hours == requestedHours,
               page.requestedAt.timeIntervalSince(run.lastAt) < 300 {
                run.lastIndex = index
                run.lastAt = page.requestedAt
                run.start = [run.start, start].compactMap(\.self).min()
                run.end = [run.end, end].compactMap(\.self).max()
                runs[runs.count - 1] = run
            } else {
                runs.append(Run(hours: requestedHours, lastIndex: index, lastAt: page.requestedAt, start: start, end: end))
            }
        }
        for run in runs {
            guard let start = run.start, let end = run.end else { continue }
            var hour = max(start, interval.start)
            let last = min(end, interval.end)
            while hour < last {
                settled.insert(hour)
                hour = hour.addingTimeInterval(3_600)
            }
        }
        return settled
    }

    public func latestHourStart(provider: String) throws -> Date? {
        var descriptor = FetchDescriptor<HourlyAirQuality>(
            predicate: #Predicate { $0.provider == provider },
            sortBy: [SortDescriptor(\.hourStart, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.hourStart
    }

    public func dailyRecords() throws -> [DailyRecordSnapshot] {
        try modelContext.fetch(FetchDescriptor<DailyRecord>(sortBy: [SortDescriptor(\.dayStart)])).map {
            DailyRecordSnapshot(dayKey: $0.dayKey, dayStart: $0.dayStart, dayEnd: $0.dayEnd,
                                timeZoneID: $0.timeZoneID, firstSeenAt: $0.firstSeenAt)
        }
    }

    public func observations(since date: Date) throws -> [EnvironmentalAttemptRecord] {
        let rows = try modelContext.fetch(FetchDescriptor<EnvironmentalObservation>(
            predicate: #Predicate { $0.requestedAt >= date }, sortBy: [SortDescriptor(\.requestedAt)]))
        let ids = rows.map(\.id)
        let hours = try modelContext.fetch(FetchDescriptor<HourlyAirQuality>(
            predicate: #Predicate { ids.contains($0.observationID) }, sortBy: [SortDescriptor(\.hourStart)]))
        let hoursByObservation = Dictionary(grouping: hours, by: \.observationID)
        return rows.map { row in
            var record = EnvironmentalAttemptRecord(
                id: row.id, provider: row.provider, requestKind: row.requestKind, requestedAt: row.requestedAt,
                timeZoneID: row.requestTimeZoneID, status: EnvironmentalAttemptRecord.Status(rawValue: row.status) ?? .networkError,
                parserVersion: row.parserVersion, appVersion: row.appVersion)
            record.receivedAt = row.receivedAt
            record.failureDetail = row.failureDetail
            record.httpStatus = row.httpStatus
            record.latitude = row.requestLatitude
            record.longitude = row.requestLongitude
            record.coordinateDecimals = row.coordinateDecimals
            record.requestParameters = row.requestParameters
            record.pageIndex = row.pageIndex
            record.rawResponse = row.rawResponse
            record.aqi = row.aqi
            record.dominantPollutant = row.dominantPollutant
            record.stationName = row.stationName
            record.stationIdx = row.stationIdx
            record.stationLatitude = row.stationLatitude
            record.stationLongitude = row.stationLongitude
            record.observedAtISO = row.observedAtISO
            record.observedTimeZone = row.observedTimeZone
            record.subIndices = row.subIndices
            record.forecastDate = row.forecastDate
            record.pollenTypes = row.pollenTypes
            record.plants = row.plants
            record.hours = (hoursByObservation[row.id] ?? []).map {
                .init(hourStart: $0.hourStart, indexes: $0.indexes, pollutants: $0.pollutants)
            }
            return record
        }
    }

    @discardableResult
    private func insertDayIfNeeded(containing date: Date, in timeZone: TimeZone, appVersion: String) throws -> String {
        let day = LocalDay(containing: date, in: timeZone)
        let key = day.key
        let existing = FetchDescriptor<DailyRecord>(predicate: #Predicate { $0.dayKey == key })
        guard try modelContext.fetchCount(existing) == 0 else { return key }
        modelContext.insert(DailyRecord(dayKey: key, dayStart: day.interval.start, dayEnd: day.interval.end,
                                        timeZoneID: timeZone.identifier,
                                        utcOffsetAtStartSeconds: day.utcOffsetAtStartSeconds,
                                        firstSeenAt: date, appVersion: appVersion))
        return key
    }

    private func save() throws {
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
    }
}
