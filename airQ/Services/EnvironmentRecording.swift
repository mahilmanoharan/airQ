import Foundation
import Observation
import Synchronization
import AirQualityKit
import RespiratoryKit

enum AppVersion {
    static var current: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }
}

/// Set once any provider attempt fails to save. Google usage is counted from saved attempts, so
/// after that it can't be verified and metered requests are refused until relaunch (fail closed).
nonisolated final class RecordingHealth: Sendable {
    private let failed = Mutex(false)
    var hasUnrecordedAttempts: Bool { failed.withLock { $0 } }
    func markUnrecordedAttempt() { failed.withLock { $0 = true } }
}

/// Persists every environmental provider attempt and each day's collection opportunity. A save
/// failure stays visible, because that observation is lost.
@Observable
final class EnvironmentRecorder {
    /// Set when an attempt couldn't be saved: permanent until restart (that observation is lost, and
    /// Google requests are paused because their usage can't be counted).
    private(set) var saveError: String?
    /// Set when today couldn't be marked; cleared as soon as a later attempt succeeds.
    private(set) var dayError: String?
    var lastError: String? { saveError ?? dayError }
    /// Bumped after every saved attempt (including history pages), for views that read the record.
    private(set) var revision = 0
    let health = RecordingHealth()
    private let store: RecordStore
    private let appVersion: String

    init(store: RecordStore, appVersion: String) {
        self.store = store
        self.appVersion = appVersion
    }

    @ObservationIgnored private let queue = OrderedTaskQueue()

    /// Saves attempts in the order they were reported. `flush()` waits for every queued save, so a
    /// background run can finish without leaving an observation unwritten.
    func enqueue(_ attempt: ProviderAttempt) {
        queue.enqueue { [self] in await record(attempt) }
    }

    func flush() async { await queue.flush() }

    func record(_ attempt: ProviderAttempt) async {
        do {
            try await store.record(EnvironmentalAttemptRecord(attempt, timeZone: .current, appVersion: appVersion))
            revision += 1
        } catch {
            health.markUnrecordedAttempt()
            saveError = "An air-quality observation could not be saved, so Google requests are paused until airQ restarts: \(error.localizedDescription)"
        }
    }

    func markToday() async {
        do {
            try await store.ensureDay(containing: .now, in: .current, appVersion: appVersion)
            dayError = nil
        } catch {
            dayError = "Today could not be recorded: \(error.localizedDescription)"
        }
    }
}

/// The record-backed services the app composes: attempt recording, the Google request budget, and
/// hourly air-quality history collection.
final class RecordServices {
    enum Unavailable: Error { case recordStore }

    /// Without a record store, usage can't be counted, so metered providers are refused.
    static let unavailableBudget = RollingRequestBudget { _, _ in throw Unavailable.recordStore }

    let recordStore: RecordStore
    let recorder: EnvironmentRecorder
    let budget: RollingRequestBudget
    let collector: AirQualityHistoryCollector
    private var collection: Task<Void, Never>?

    init(recordStore: RecordStore, client: HTTPAirQualityClient,
         maySendLocation: @escaping @MainActor @Sendable () -> Bool) {
        let recorder = EnvironmentRecorder(store: recordStore, appVersion: AppVersion.current)
        let health = recorder.health
        let budget = RollingRequestBudget { provider, since in
            if health.hasUnrecordedAttempts { throw Unavailable.recordStore }
            return try await recordStore.providerRequestCount(provider: provider.rawValue, since: since)
        }
        let historyProvider = EnvironmentalProvider.googleAirQuality.rawValue
        self.recordStore = recordStore
        self.recorder = recorder
        self.budget = budget
        self.collector = AirQualityHistoryCollector(
            client: client, budget: budget,
            settledHours: { interval, coordinate in
                try await recordStore.settledHourStarts(
                    provider: historyProvider, in: interval,
                    at: RecordPlace(latitude: coordinate.latitude, longitude: coordinate.longitude))
            },
            lastRequestAt: {
                if health.hasUnrecordedAttempts { throw Unavailable.recordStore }
                return try await recordStore.latestRequestAt(provider: historyProvider)
            },
            record: { attempt in await recorder.record(attempt) },
            maySendLocation: { await maySendLocation() })
    }

    /// Starts a history run unless one is in progress. The run is owned here, not by a view task,
    /// so a view update can't cancel a request mid-flight (a cancelled request still counts as sent
    /// and would block the next run for a day).
    func collectHistory(at coordinate: GeoCoordinate) {
        guard collection == nil else { return }
        let collector = collector
        collection = Task {
            await collector.collect(at: coordinate)
            collection = nil
        }
    }

    func cancelCollection() { collection?.cancel() }

    func drainCollection() async { await collection?.value }
}

extension EnvironmentalAttemptRecord {
    init(_ attempt: ProviderAttempt, timeZone: TimeZone, appVersion: String) {
        self.init(provider: attempt.provider.rawValue, requestKind: attempt.requestKind,
                  requestedAt: attempt.requestedAt, timeZoneID: timeZone.identifier,
                  status: Self.status(attempt.status), parserVersion: attempt.parserVersion, appVersion: appVersion)
        receivedAt = attempt.receivedAt
        failureDetail = attempt.failureDetail
        httpStatus = attempt.httpStatus
        latitude = attempt.coordinate?.latitude
        longitude = attempt.coordinate?.longitude
        coordinateDecimals = attempt.coordinateDecimals
        requestParameters = attempt.requestParameters
        pageIndex = attempt.pageIndex
        rawResponse = attempt.rawResponse

        switch attempt.parsed {
        case .waqi(let observation):
            aqi = observation.aqi
            dominantPollutant = observation.dominantPollutant
            stationName = observation.stationName
            stationIdx = observation.stationIdx
            stationLatitude = observation.stationCoordinate?.latitude
            stationLongitude = observation.stationCoordinate?.longitude
            observedAtISO = observation.observedAtISO
            observedTimeZone = observation.observedTimeZone
            subIndices = observation.subIndices
        case .pollen(let forecast):
            forecastDate = forecast.date
            pollenTypes = forecast.types.map(Self.reading)
            plants = forecast.plants.map(Self.reading)
        case .hourly(let hourly):
            hours = hourly.map { hour in
                Hour(hourStart: hour.hourStart,
                     indexes: hour.indexes.map {
                         .init(code: $0.code, aqi: $0.aqi, category: $0.category, dominantPollutant: $0.dominantPollutant)
                     },
                     pollutants: hour.pollutants.map { .init(code: $0.code, value: $0.value, units: $0.units) })
            }
        case nil:
            break
        }
    }

    private static func reading(_ value: PollenIndexValue) -> SchemaV2.PollenIndexReading {
        .init(code: value.code, displayName: value.displayName, upi: value.upi, category: value.category,
              inSeason: value.inSeason)
    }

    private static func status(_ status: ProviderAttempt.Status) -> Status {
        switch status {
        case .success: .success
        case .httpError: .httpError
        case .decodeError: .decodeError
        case .missingData: .missingData
        case .networkError: .networkError
        case .missingCredentials: .missingCredentials
        case .cancelled: .cancelled
        case .locationUnavailable: .locationUnavailable
        case .skippedBudget: .skippedBudget
        case .notSent: .notSent
        }
    }
}
