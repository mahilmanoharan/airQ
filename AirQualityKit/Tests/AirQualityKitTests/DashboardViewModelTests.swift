import Foundation
import Testing
@testable import AirQualityKit

@Suite("Dashboard loading")
@MainActor
struct DashboardViewModelTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let here = GeoCoordinate(latitude: 40, longitude: -74)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func cached(at coordinate: GeoCoordinate?, pollen: Int? = 2, age: TimeInterval = 0) -> AQSnapshot {
        AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: pollen,
                   locationName: "Cached", lastUpdated: now.addingTimeInterval(-age), coordinate: coordinate)
    }

    private func summary(_ attempts: [ProviderAttempt]) -> Set<String> {
        Set(attempts.map { "\($0.provider.rawValue):\($0.status.rawValue)" })
    }

    @Test("Fresh same-location cache avoids network work")
    func reusesCache() async {
        let client = StubAirQualityClient()
        let vm = DashboardViewModel(location: StubLocation(here), client: client,
                                    cache: MemorySnapshotCache(cached(at: here)), now: { now })
        await vm.load()
        #expect(vm.snapshot?.aqi == 42)
        #expect(await client.requestCount == 0)
        #expect(!vm.isLoading)
    }

    @Test("A different location and legacy coordinates cannot satisfy a fresh load")
    func rejectsWrongLocation() async {
        for coordinate in [GeoCoordinate(latitude: 10, longitude: 10), nil] {
            let cache = MemorySnapshotCache(cached(at: coordinate))
            let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(),
                                        cache: cache, now: { now })
            await vm.load()
            #expect(vm.snapshot?.aqi == 75)
            #expect(cache.snapshot?.coordinate == here)
        }
    }

    @Test("A refresh at the cached place fetches without locating and keeps the place name")
    func cachedPlaceRefresh() async {
        let old = AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: 2, locationName: "Cached",
                             lastUpdated: now.addingTimeInterval(-4 * 3_600), coordinate: here)
        let cache = MemorySnapshotCache(old)
        let client = StubAirQualityClient()
        let vm = DashboardViewModel(location: CachedPlaceLocation(cache: cache), client: client,
                                    cache: cache, now: { now })
        await vm.load()
        #expect(await client.requestCount == 1)
        #expect(cache.snapshot?.aqi == 75)
        #expect(cache.snapshot?.locationName == "Cached")
        #expect(cache.snapshot?.coordinate == here)
    }

    @Test("Revoked permission keeps the dated cache visible without using its coordinate")
    func revokedCachedPlacePermission() async {
        let old = cached(at: here, age: 4 * 3_600)
        let cache = MemorySnapshotCache(old)
        let client = StubAirQualityClient()
        var authorized = false
        let vm = DashboardViewModel(location: CachedPlaceLocation(cache: cache), client: client,
                                    cache: cache, now: { now }, maySendLocation: { authorized })
        await vm.load()
        #expect(vm.snapshot == old)
        #expect(await client.requestCount == 0)
        #expect(await client.pollenRequestCount == 0)
        authorized = true
        await vm.load()
        #expect(await client.requestCount == 1)
        #expect(cache.snapshot?.aqi == 75)
    }

    @Test("A paused load records the finished attempt but cannot republish a pre-erase place")
    func drainingPreEraseLoad() async {
        let cache = MemorySnapshotCache()
        let client = StubAirQualityClient()
        await client.suspendAirQuality()
        var attempts: [ProviderAttempt] = []
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache,
                                    now: { now }, onProviderAttempt: { attempts.append($0) })
        let load = Task { await vm.load() }
        await client.waitForAirQuality()
        vm.pauseLoads()
        await vm.load()
        await client.resumeAirQuality()
        await vm.drainLoads()
        await load.value
        vm.forgetReading()
        vm.resumeLoads()
        #expect(await client.requestCount == 1)
        #expect(await client.pollenRequestCount == 0)
        #expect(attempts.map(\.provider) == [.waqi])
        #expect(cache.snapshot == nil)
        #expect(vm.snapshot == nil)
        await vm.load()
        #expect(cache.snapshot?.aqi == 75)
    }

    @Test("Without a cached place the refresh fails with a clear reason and sends nothing")
    func cachedPlaceMissing() async {
        let cache = MemorySnapshotCache()
        let client = StubAirQualityClient()
        var attempts: [ProviderAttempt] = []
        let vm = DashboardViewModel(location: CachedPlaceLocation(cache: cache), client: client, cache: cache,
                                    now: { now }, onProviderAttempt: { attempts.append($0) })
        await vm.load()
        #expect(await client.requestCount == 0)
        #expect(vm.errorMessage == CachedPlaceLocation.Failure.noKnownPlace.errorDescription)
        #expect(attempts.allSatisfy { $0.status == .locationUnavailable })
    }

    @Test("With location unavailable the last known reading is still shown beside the error")
    func lastKnownReadingWithoutLocation() async {
        let cache = MemorySnapshotCache(cached(at: here, age: 5 * 3_600))
        let vm = DashboardViewModel(location: StubLocation(here, fails: URLError(.cannotFindHost)), client: StubAirQualityClient(),
                                    cache: cache, now: { now })
        await vm.load()
        #expect(vm.snapshot?.locationName == "Cached")
        #expect(vm.errorMessage != nil)
    }

    @Test("A weak fix when returning to the app doesn't warn over a still-fresh reading, unless the person asked to refresh")
    func freshReadingWithoutLocationIsQuiet() async {
        let cache = MemorySnapshotCache(cached(at: here, age: 600))
        let vm = DashboardViewModel(location: StubLocation(here, fails: URLError(.cannotFindHost)), client: StubAirQualityClient(),
                                    cache: cache, now: { now })
        await vm.load()
        #expect(vm.snapshot?.locationName == "Cached")
        #expect(vm.errorMessage == nil)
        await vm.load(forceRefresh: true)
        #expect(vm.errorMessage != nil)
    }

    @Test("Retry after a failed save really retries, even within the refresh throttle")
    func retryAfterFailureIsNotThrottled() async {
        let cache = MemorySnapshotCache()
        cache.fails = true
        let client = StubAirQualityClient()
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache, now: { now })
        await vm.load()
        #expect(vm.widgetSaveError != nil)
        cache.fails = false
        await vm.load(forceRefresh: true)
        #expect(await client.requestCount == 2)
        #expect(vm.widgetSaveError == nil && vm.errorMessage == nil && cache.snapshot?.aqi == 75)
    }

    @Test("Two models sharing a cache and a gate make one request between them")
    func sharedGateSingleFetch() async {
        let cache = MemorySnapshotCache()
        let client = StubAirQualityClient()
        let gate = LoadGate()
        let first = DashboardViewModel(location: StubLocation(here), client: client, cache: cache, gate: gate, now: { now })
        let second = DashboardViewModel(location: StubLocation(here), client: client, cache: cache, gate: gate, now: { now })
        async let a: Void = first.load()
        async let b: Void = second.load()
        _ = await (a, b)
        #expect(await client.requestCount == 1)
        #expect(first.snapshot?.aqi == 75 && second.snapshot?.aqi == 75)
    }

    @Test("Pollen failure displays unknown while preserving successful AQI")
    func missingPollen() async {
        let cache = MemorySnapshotCache()
        let client = StubAirQualityClient(pollenFails: true)
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache, now: { now })
        await vm.load()
        #expect(vm.snapshot?.aqi == 75)
        #expect(vm.snapshot?.pollenIndex == nil)
        #expect(vm.snapshot?.pollenFetchedAt == nil)
        #expect(cache.snapshot?.pollenIndex == nil)
    }

    @Test("Explicit refresh bypasses a fresh cache and publishes widgets once")
    func forcedRefresh() async {
        var publications = 0
        let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(),
                                    cache: MemorySnapshotCache(cached(at: here, age: 5 * 60)), now: { now },
                                    didSave: { publications += 1 })
        await vm.load(forceRefresh: true)
        #expect(vm.snapshot?.aqi == 75)
        #expect(publications == 1)
    }

    @Test("An explicit refresh within a minute of the last fetch reuses it instead of asking the provider again")
    func forcedRefreshIsThrottled() async {
        let client = StubAirQualityClient()
        let vm = DashboardViewModel(location: StubLocation(here), client: client,
                                    cache: MemorySnapshotCache(cached(at: here, age: 30)), now: { now })
        await vm.load(forceRefresh: true)
        #expect(vm.snapshot?.aqi == 42)
        #expect(await client.requestCount == 0)
    }

    @Test("Cancellation publishes neither an error nor a new cached snapshot")
    func cancellation() async {
        let cache = MemorySnapshotCache()
        var attempts: [ProviderAttempt] = []
        let vm = DashboardViewModel(location: StubLocation(here, fails: CancellationError()),
                                    client: StubAirQualityClient(), cache: cache, now: { now },
                                    onProviderAttempt: { attempts.append($0) })
        await vm.load()
        #expect(vm.snapshot == nil)
        #expect(cache.snapshot == nil)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
        #expect(attempts.isEmpty)
    }

    @Test("Refresh failure retains same-location stale data with a visible error")
    func staleFallback() async {
        let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(aqFails: true),
                                    cache: MemorySnapshotCache(cached(at: here)), now: { now.addingTimeInterval(4_000) })
        await vm.load()
        #expect(vm.snapshot?.aqi == 42)
        #expect(vm.errorMessage != nil)
    }

    @Test("A failed air quality request never spends a (billed) pollen request")
    func pollenWaitsForAirQuality() async {
        let client = StubAirQualityClient(aqFails: true)
        let vm = DashboardViewModel(location: StubLocation(here), client: client,
                                    cache: MemorySnapshotCache(), now: { now })
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(await client.pollenRequestCount == 0)
    }

    @Test("Concurrent load calls acquire location once")
    func duplicateLoad() async {
        let location = SuspendedLocation()
        let vm = DashboardViewModel(location: location, client: StubAirQualityClient(),
                                    cache: MemorySnapshotCache(), now: { now })
        let first = Task { await vm.load() }
        await location.waitUntilRequested()
        let completion = Task { location.complete(here) }
        await vm.load()
        #expect(location.requests == 1)
        await completion.value
        await first.value
        #expect(vm.snapshot?.aqi == 75)
    }

    @Test("A returning view waits for a cancelled load to unwind, then starts a fresh load")
    func reloadAfterCancelledOwner() async {
        let location = SuspendedLocation()
        let vm = DashboardViewModel(location: location, client: StubAirQualityClient(), cache: MemorySnapshotCache())
        let first = Task { await vm.load() }
        await location.waitUntilRequested()
        first.cancel()
        let completion = Task { location.complete(here) }
        await vm.load()
        await completion.value
        await first.value
        #expect(vm.snapshot?.aqi == 75)
        #expect(location.requests == 2)
    }

    @Test("Cancelling while location is pending prevents a late callback from publishing")
    func lateLocationCancellation() async {
        let location = SuspendedLocation()
        let client = StubAirQualityClient()
        let cache = MemorySnapshotCache()
        let vm = DashboardViewModel(location: location, client: client, cache: cache)
        let task = Task { await vm.load() }
        await location.waitUntilRequested()
        task.cancel()
        location.complete(here)
        await task.value
        #expect(vm.snapshot == nil && vm.errorMessage == nil)
        #expect(cache.snapshot == nil)
        #expect(await client.requestCount == 0)
    }

    @Test("A cache write failure keeps the fresh reading, says only widgets are behind, and publishes no reload")
    func cacheWriteFailure() async {
        let cache = MemorySnapshotCache()
        cache.fails = true
        var publications = 0
        let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(), cache: cache,
                                    didSave: { publications += 1 })
        await vm.load()
        #expect(vm.snapshot?.aqi == 75)
        // The reading is current: this must not read as "showing your last reading".
        #expect(vm.errorMessage == nil)
        #expect(vm.widgetSaveError != nil)
        #expect(publications == 0)
        vm.forgetReading()
        #expect(vm.widgetSaveError == nil)
    }

    @Test("An unavailable cache does not erase already displayed same-location readings")
    func retainsMemoryReading() async {
        let cache = MemorySnapshotCache()
        let client = StubAirQualityClient()
        let clock = StepClock(now)
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache, now: { clock.date })
        await vm.load()
        cache.fails = true
        await client.failAQ()
        clock.advance(120)
        await vm.load(forceRefresh: true)
        #expect(vm.snapshot?.aqi == 75)
        #expect(vm.errorMessage != nil)
    }

    @Test("Every provider attempt is reported, including a failed pollen request")
    func reportsAttempts() async {
        var attempts: [ProviderAttempt] = []
        let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(pollenFails: true),
                                    cache: MemorySnapshotCache(), now: { now },
                                    onProviderAttempt: { attempts.append($0) })
        await vm.load()
        #expect(summary(attempts) == ["waqi:success", "googlePollen:networkError"])
    }

    @Test("Pollen is fetched at most once per local day, even on explicit refresh")
    func pollenOncePerDay() async {
        let client = StubAirQualityClient()
        let earlierToday = now.addingTimeInterval(-7_200)
        let cache = MemorySnapshotCache(AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: 4, locationName: "Cached",
                                                   lastUpdated: earlierToday, coordinate: here,
                                                   pollenFetchedAt: earlierToday))
        let clock = StepClock(now)
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache,
                                    now: { clock.date }, calendar: utc)
        await vm.load()
        clock.advance(120)
        await vm.load(forceRefresh: true)
        #expect(await client.requestCount == 2)
        #expect(await client.pollenRequestCount == 0)
        #expect(vm.snapshot?.pollenIndex == 4)
        #expect(vm.snapshot?.pollenFetchedAt == earlierToday)
    }

    @Test("A live load stores per-type pollen and station conditions; a same-day reuse keeps the types")
    func storesBreakdowns() async {
        let client = StubAirQualityClient()
        let cache = MemorySnapshotCache()
        let clock = StepClock(now)
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache,
                                    now: { clock.date }, calendar: utc)
        await vm.load()
        #expect(cache.snapshot?.pollenTypes == PollenReading(grassIndex: 1, treeIndex: 3, weedIndex: 2))
        #expect(cache.snapshot?.conditions?.pollutants.map(\.code) == ["pm25", "o3"])
        #expect(cache.snapshot?.conditions?.temperatureCelsius == 21)

        clock.advance(120)
        await vm.load(forceRefresh: true)
        #expect(await client.pollenRequestCount == 1)
        #expect(vm.snapshot?.pollenTypes?.treeIndex == 3)
    }

    @Test("A pollen answer with no data is also reused for the rest of the day")
    func pollenNoDataOncePerDay() async {
        let client = StubAirQualityClient()
        await client.setPollenMissingData()
        let cache = MemorySnapshotCache()
        let clock = StepClock(now)
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache,
                                    now: { clock.date }, calendar: utc)
        await vm.load()
        clock.advance(120)
        await vm.load(forceRefresh: true)
        #expect(await client.pollenRequestCount == 1)
        #expect(vm.snapshot?.pollenIndex == nil)
        #expect(vm.snapshot?.pollenFetchedAt == now)
    }

    @Test("Transient pollen errors (429, 5xx) are retried on a later load; other HTTP answers settle the day")
    func pollenTransientErrors() async {
        for (status, retried) in [(503, true), (429, true), (408, true), (403, false), (200, false)] {
            let client = StubAirQualityClient()
            await client.setPollenHTTPFailure(status)
            let clock = StepClock(now)
            let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: MemorySnapshotCache(),
                                        now: { clock.date }, calendar: utc)
            await vm.load()
            clock.advance(120)
            await vm.load(forceRefresh: true)
            #expect(await client.pollenRequestCount == (retried ? 2 : 1), "HTTP \(status)")
            #expect((vm.snapshot?.pollenFetchedAt == nil) == retried, "HTTP \(status)")
        }
        #expect(!DashboardViewModel.isSettledForToday(httpStatus: nil))
    }

    @Test("Pollen is fetched again once the local day changes")
    func pollenRefetchedNextDay() async {
        let client = StubAirQualityClient()
        let yesterday = now.addingTimeInterval(-86_400)
        let cache = MemorySnapshotCache(AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: 4, locationName: "Cached",
                                                   lastUpdated: yesterday, coordinate: here, pollenFetchedAt: yesterday))
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache,
                                    now: { now }, calendar: utc)
        await vm.load()
        #expect(await client.pollenRequestCount == 1)
        #expect(vm.snapshot?.pollenIndex == 3)
        #expect(vm.snapshot?.pollenFetchedAt == now)
    }

    @Test("An exhausted budget skips Google Pollen, records the skip, and still shows AQI")
    func budgetSkipsPollen() async {
        let client = StubAirQualityClient()
        var attempts: [ProviderAttempt] = []
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: MemorySnapshotCache(),
                                    budget: StubBudget(allowed: false), now: { now },
                                    onProviderAttempt: { attempts.append($0) })
        await vm.load()
        #expect(await client.pollenRequestCount == 0)
        #expect(vm.snapshot?.aqi == 75)
        #expect(vm.snapshot?.pollenIndex == nil)
        #expect(summary(attempts) == ["waqi:success", "googlePollen:skippedBudget"])
    }

    @Test("A denied-permission error is flagged as fixable in Settings; a later success clears it")
    func settingsRecoverable() async {
        let location = StubLocation(here, fails: DeniedError())
        let vm = DashboardViewModel(location: location, client: StubAirQualityClient(),
                                    cache: MemorySnapshotCache(), now: { now })
        await vm.load()
        #expect(vm.errorIsRecoverableInSettings)
        location.failure = nil
        await vm.load()
        #expect(!vm.errorIsRecoverableInSettings && vm.errorMessage == nil)

        let other = DashboardViewModel(location: StubLocation(here, fails: URLError(.timedOut)),
                                       client: StubAirQualityClient(), cache: MemorySnapshotCache(), now: { now })
        await other.load()
        #expect(other.errorMessage != nil && !other.errorIsRecoverableInSettings)
    }

    @Test("A location failure is recorded as an unsent request for each provider")
    func locationFailureRecorded() async {
        var attempts: [ProviderAttempt] = []
        let vm = DashboardViewModel(location: StubLocation(here, fails: URLError(.cannotFindHost)),
                                    client: StubAirQualityClient(), cache: MemorySnapshotCache(), now: { now },
                                    onProviderAttempt: { attempts.append($0) })
        await vm.load()
        #expect(summary(attempts) == ["waqi:locationUnavailable", "googlePollen:locationUnavailable"])
        #expect(vm.errorMessage != nil)
    }
}

private struct DeniedError: SettingsRecoverableError {
    var isRecoverableInSettings: Bool { true }
}

@MainActor
private final class StubLocation: LocationProviding {
    let coordinate: GeoCoordinate
    var failure: (any Error)?
    init(_ coordinate: GeoCoordinate, fails: (any Error)? = nil) { self.coordinate = coordinate; failure = fails }
    func currentCoordinate() async throws -> GeoCoordinate {
        if let failure { throw failure }
        return coordinate
    }
    func cityName(for coordinate: GeoCoordinate) async -> String? { "Test City" }
}

@MainActor
private final class SuspendedLocation: LocationProviding {
    var requests = 0
    private var nextCoordinate: GeoCoordinate?
    var continuation: CheckedContinuation<GeoCoordinate, Never>?
    var started: CheckedContinuation<Void, Never>?
    func currentCoordinate() async throws -> GeoCoordinate {
        requests += 1
        if let nextCoordinate { return nextCoordinate }
        return await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete(_ value: GeoCoordinate) {
        nextCoordinate = value
        continuation?.resume(returning: value)
        continuation = nil
    }
    func cityName(for coordinate: GeoCoordinate) async -> String? { nil }
}

private struct StubBudget: RequestBudgeting {
    let allowed: Bool
    func permits(_ provider: EnvironmentalProvider, at date: Date) async -> Bool { allowed }
}

private actor StubAirQualityClient: AirQualityFetching {
    var requestCount = 0
    var pollenRequestCount = 0
    let pollenFails: Bool
    var pollenMissingData = false
    var aqFails: Bool
    private var shouldPause = false
    private var paused: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func failAQ() { aqFails = true }
    init(pollenFails: Bool = false, aqFails: Bool = false) { self.pollenFails = pollenFails; self.aqFails = aqFails }

    func airQuality(at coordinate: GeoCoordinate) async throws -> Fetched<AirQualityReading> {
        requestCount += 1
        if shouldPause {
            await withCheckedContinuation { continuation in
                paused = continuation
                started?.resume()
                started = nil
            }
        }
        if aqFails {
            throw ProviderFailure(attempt: Self.attempt(.waqi, .networkError), underlying: URLError(.notConnectedToInternet))
        }
        return Fetched(value: AirQualityReading(aqi: 75, dominantPollutant: "pm25", stationName: "Station, Country",
                                                subIndices: ["o3": 12, "pm25": 75, "t": 21]),
                       attempt: Self.attempt(.waqi, .success))
    }

    func suspendAirQuality() { shouldPause = true }

    func waitForAirQuality() async {
        if paused == nil { await withCheckedContinuation { started = $0 } }
    }

    func resumeAirQuality() {
        shouldPause = false
        paused?.resume()
        paused = nil
    }

    func pollen(at coordinate: GeoCoordinate) async throws -> Fetched<PollenReading> {
        pollenRequestCount += 1
        if let status = pollenHTTPFailure {
            var attempt = Self.attempt(.googlePollen, status == 200 ? .missingData : .httpError)
            attempt.httpStatus = status
            throw ProviderFailure(attempt: attempt, underlying: AirQualityServiceError.httpStatus(status))
        }
        if pollenMissingData {
            var attempt = Self.attempt(.googlePollen, .missingData)
            attempt.httpStatus = 200
            throw ProviderFailure(attempt: attempt, underlying: AirQualityServiceError.httpStatus(200))
        }
        if pollenFails {
            throw ProviderFailure(attempt: Self.attempt(.googlePollen, .networkError),
                                  underlying: URLError(.notConnectedToInternet))
        }
        return Fetched(value: PollenReading(grassIndex: 1, treeIndex: 3, weedIndex: 2),
                       attempt: Self.attempt(.googlePollen, .success))
    }

    func setPollenMissingData() { pollenMissingData = true }

    var pollenHTTPFailure: Int?
    func setPollenHTTPFailure(_ status: Int) { pollenHTTPFailure = status }

    private static func attempt(_ provider: EnvironmentalProvider, _ status: ProviderAttempt.Status) -> ProviderAttempt {
        ProviderAttempt(provider: provider, requestKind: "test", requestedAt: .distantPast, status: status, parserVersion: 1)
    }
}

@MainActor
private final class MemorySnapshotCache: SnapshotCaching {
    var snapshot: AQSnapshot?
    var fails = false
    init(_ snapshot: AQSnapshot? = nil) { self.snapshot = snapshot }
    func load() throws -> AQSnapshot? {
        if fails { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }
    func save(_ snapshot: AQSnapshot) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        self.snapshot = snapshot
    }
}

/// A clock a test can move forward between loads.
@MainActor
private final class StepClock {
    private(set) var date: Date
    init(_ date: Date) { self.date = date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}
