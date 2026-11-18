import Foundation
import Observation

/// Owns a single end-to-end load. Views render state and forward user actions. Every provider
/// request attempt, including failures and skipped requests, is reported through `onProviderAttempt`.
@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var snapshot: AQSnapshot?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// The reading is current but couldn't be saved for widgets (and Siri), which keep showing an older one.
    /// Kept apart from `errorMessage`, which means the reading itself couldn't be refreshed.
    public private(set) var widgetSaveError: String?
    /// The current error is fixed in Settings (e.g. location denied), not by retrying.
    public private(set) var errorIsRecoverableInSettings = false

    /// The shortest gap between two provider fetches, even for an explicit refresh.
    static let minimumRefreshInterval: TimeInterval = 60

    private let location: any LocationProviding
    private let client: any AirQualityFetching
    private let cache: any SnapshotCaching
    private let budget: (any RequestBudgeting)?
    private let gate: LoadGate?
    private let now: () -> Date
    private let calendar: Calendar
    private let didSave: () -> Void
    private let onProviderAttempt: (ProviderAttempt) -> Void
    private let maySendLocation: () -> Bool
    @ObservationIgnored private var loadWaiters: [CheckedContinuation<Bool, Never>] = []
    @ObservationIgnored private var activeLoad: Task<Void, Never>?
    @ObservationIgnored private var loadsPaused = false
    @ObservationIgnored private var loadEpoch = 0

    public init(location: any LocationProviding, client: any AirQualityFetching,
                cache: any SnapshotCaching, budget: (any RequestBudgeting)? = nil, gate: LoadGate? = nil,
                now: @escaping () -> Date = Date.init, calendar: Calendar = .current,
                didSave: @escaping () -> Void = {},
                onProviderAttempt: @escaping (ProviderAttempt) -> Void = { _ in },
                maySendLocation: @escaping () -> Bool = { true }) {
        self.location = location
        self.client = client
        self.cache = cache
        self.budget = budget
        self.gate = gate
        self.now = now
        self.calendar = calendar
        self.didSave = didSave
        self.onProviderAttempt = onProviderAttempt
        self.maySendLocation = maySendLocation
    }

    /// Drops the reading held in memory (after the person erased their data): otherwise the next load
    /// would take it for a fresh same-place cache hit and never refetch or re-save it.
    public func forgetReading() {
        snapshot = nil
        errorMessage = nil
        widgetSaveError = nil
    }

    public func load(forceRefresh: Bool = false) async {
        guard !loadsPaused, !Task.isCancelled else { return }
        if isLoading {
            // Coalesce callers, but let a newly visible view retry after the old
            // view's cancelled task has released its location/network resources.
            let epoch = loadEpoch
            let previousWasCancelled = await withCheckedContinuation { loadWaiters.append($0) }
            if previousWasCancelled, epoch == loadEpoch { await load(forceRefresh: forceRefresh) }
            return
        }
        isLoading = true
        let task = Task { await performLoad(forceRefresh: forceRefresh) }
        activeLoad = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Stop admitting loads and cancel the owner. Keep the pause in force until pending attempt
    /// callbacks have been persisted and the shared cache has been cleared.
    public func pauseLoads() {
        loadsPaused = true
        loadEpoch += 1
        activeLoad?.cancel()
    }

    public func drainLoads() async { await activeLoad?.value }

    public func resumeLoads() { loadsPaused = false }

    private func performLoad(forceRefresh: Bool) async {
        // A retry after a failure (even a failed save) must really retry, not be throttled.
        let previousLoadFailed = errorMessage != nil || widgetSaveError != nil
        errorMessage = nil
        errorIsRecoverableInSettings = false
        var wasCancelled = false
        defer {
            activeLoad = nil
            isLoading = false
            let waiting = loadWaiters
            loadWaiters.removeAll(keepingCapacity: true)
            for waiter in waiting { waiter.resume(returning: wasCancelled || Task.isCancelled) }
        }

        do {
            try Task.checkCancellation()
            let coordinate: GeoCoordinate
            do {
                coordinate = try await currentCoordinate()
            } catch {
                // Without a location, the last known reading (its age is shown) beats an empty screen.
                if snapshot == nil, !Task.isCancelled, !(error is CancellationError) { snapshot = try? cache.load() }
                // Coming back to the app indoors, a weak fix must not put a warning over a reading that is
                // still fresh and needed no request anyway. An explicit refresh still reports it, and so does a
                // lasting problem the person can fix (permission denied).
                if !forceRefresh, !(error is CancellationError),
                   (error as? any SettingsRecoverableError)?.isRecoverableInSettings != true,
                   snapshot?.isFresh(asOf: now(), within: AQSnapshot.freshFor) == true { return }
                throw error
            }
            try Task.checkCancellation()
            // A corrupt/unavailable widget cache must not prevent a live fetch.
            let cached = (try? cache.load()) ?? snapshot
            let matching = cached.flatMap { value in
                value.coordinate?.isNear(coordinate) == true ? value : nil
            }
            snapshot = matching
            try checkMaySendLocation()
            // An explicit refresh still skips a reading fetched moments ago: repeated pulls would only
            // spend the provider's daily request allowance on identical data.
            let reuseWindow = forceRefresh ? (previousLoadFailed ? 0 : Self.minimumRefreshInterval) : AQSnapshot.freshFor
            if let matching, matching.isFresh(asOf: now(), within: reuseWindow) { return }

            // Fetch one model at a time when models share a cache; whoever waited re-checks it,
            // since the other may have just refreshed it.
            var holdsGate = false
            if let gate {
                await gate.acquire()
                holdsGate = true
            }
            defer { if holdsGate { gate?.release() } }
            try checkMaySendLocation()
            if holdsGate, let latest = try? cache.load(), latest.coordinate?.isNear(coordinate) == true,
               latest.isFresh(asOf: now(), within: reuseWindow) {
                snapshot = latest
                return
            }

            // Google's pollen data is a daily forecast: reuse today's answer instead of refetching,
            // including "no data here today", so pollen is requested at most once per local day.
            let todaysPollen = matching.flatMap { value in
                value.pollenFetchedAt.map { calendar.isDate($0, inSameDayAs: now()) } == true ? value : nil
            }
            // Pollen is metered, so it is only requested once the air quality reading has succeeded: run
            // concurrently, a failing WAQI request would cancel an in-flight billed pollen request and
            // discard its answer, doubling pollen spend on every flaky-WAQI load.
            async let city = location.cityName(for: coordinate)
            let reading = try await fetchAirQuality(at: coordinate)
            try checkMaySendLocation()
            let pollenValue = try await pollenForSnapshot(at: coordinate, reusing: todaysPollen)
            let cityName = await city
            try checkMaySendLocation()

            let updated = AQSnapshot(
                aqi: reading.aqi, dominantPollutant: reading.dominantPollutant,
                pollenIndex: pollenValue.index,
                locationName: cityName ?? Self.fallbackName(reading.stationName),
                lastUpdated: now(), coordinate: coordinate, pollenFetchedAt: pollenValue.fetchedAt,
                pollenTypes: pollenValue.types, conditions: StationConditions(subIndices: reading.subIndices),
                forecast: reading.forecast, attributions: reading.attributions, station: reading.station
            )
            snapshot = updated
            do {
                try cache.save(updated)
                widgetSaveError = nil
                didSave()
            } catch {
                widgetSaveError = "This reading couldn't be saved for widgets and Siri, so they may show an older one."
            }
        } catch is CancellationError {
            // SwiftUI cancels its task when the owning view leaves the hierarchy.
            wasCancelled = true
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            errorIsRecoverableInSettings = (error as? any SettingsRecoverableError)?.isRecoverableInSettings == true
        }
    }

    private func checkMaySendLocation() throws {
        try Task.checkCancellation()
        guard maySendLocation() else { throw CancellationError() }
    }

    private func currentCoordinate() async throws -> GeoCoordinate {
        do {
            return try await location.currentCoordinate()
        } catch {
            if !(error is CancellationError), !Task.isCancelled {
                for (provider, kind) in [(EnvironmentalProvider.waqi, "current"), (.googlePollen, "forecast")] {
                    onProviderAttempt(.notSent(provider, requestKind: kind, at: now(), status: .locationUnavailable,
                                               detail: error.localizedDescription))
                }
            }
            throw error
        }
    }

    private func fetchAirQuality(at coordinate: GeoCoordinate) async throws -> AirQualityReading {
        do {
            let fetched = try await client.airQuality(at: coordinate)
            onProviderAttempt(fetched.attempt)
            return fetched.value
        } catch let failure as ProviderFailure {
            onProviderAttempt(failure.attempt)
            if failure.isCancellation { throw CancellationError() }
            throw failure
        }
    }

    private func pollenForSnapshot(at coordinate: GeoCoordinate,
                                   reusing today: AQSnapshot?) async throws -> (index: Int?, fetchedAt: Date?, types: PollenReading?) {
        if let today { return (today.pollenIndex, today.pollenFetchedAt, today.pollenTypes) }
        let (reading, providerResponded) = try await optionalPollen(at: coordinate)
        // Stamp a settled answer (even "no data"); a network failure, a transient HTTP error or a
        // skipped request leaves it unstamped so a later load can try again.
        return (reading?.overallIndex, providerResponded ? now() : nil, reading)
    }

    private func optionalPollen(at coordinate: GeoCoordinate) async throws -> (PollenReading?, responded: Bool) {
        let withinBudget = await budget?.permits(.googlePollen, at: now()) ?? true
        try checkMaySendLocation()
        if !withinBudget {
            onProviderAttempt(.notSent(.googlePollen, requestKind: "forecast", at: now(), status: .skippedBudget,
                                       detail: "The app's monthly Google Pollen request budget has been reached."))
            return (nil, false)
        }
        do {
            let fetched = try await client.pollen(at: coordinate)
            onProviderAttempt(fetched.attempt)
            return (fetched.value, true)
        } catch let failure as ProviderFailure {
            onProviderAttempt(failure.attempt)
            if failure.isCancellation { throw CancellationError() }
            try Task.checkCancellation()
            return (nil, Self.isSettledForToday(httpStatus: failure.attempt.httpStatus))
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            return (nil, false)
        }
    }

    /// Whether a failed pollen answer stands for the rest of the day. 2xx (no data) and other 4xx
    /// are deterministic, so retrying today can't help; 408 (timeout), 429 and 5xx are transient and
    /// should be retried on a later load (Google doesn't bill unsuccessful requests; the app budget
    /// still caps them).
    static func isSettledForToday(httpStatus: Int?) -> Bool {
        guard let status = httpStatus else { return false }
        return (200..<500).contains(status) && status != 429 && status != 408
    }

    private static func fallbackName(_ station: String) -> String {
        let first = station.split(separator: ",", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return first.flatMap { $0.isEmpty ? nil : $0 } ?? "Current Location"
    }
}
