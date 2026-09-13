import Foundation
import Testing
@testable import AirQualityKit

@Suite("Dashboard loading")
@MainActor
struct DashboardViewModelTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let here = GeoCoordinate(latitude: 40, longitude: -74)

    private func cached(at coordinate: GeoCoordinate?, pollen: Int? = 2) -> AQSnapshot {
        AQSnapshot(aqi: 42, dominantPollutant: nil, pollenIndex: pollen,
                   locationName: "Cached", lastUpdated: now, coordinate: coordinate)
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

    @Test("Pollen failure displays unknown while preserving successful AQI")
    func missingPollen() async {
        let cache = MemorySnapshotCache()
        let client = StubAirQualityClient(pollenFails: true)
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache, now: { now })
        await vm.load()
        #expect(vm.snapshot?.aqi == 75)
        #expect(vm.snapshot?.pollenIndex == nil)
        #expect(cache.snapshot?.pollenIndex == nil)
    }

    @Test("Explicit refresh bypasses a fresh cache and publishes widgets once")
    func forcedRefresh() async {
        var publications = 0
        let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(),
                                    cache: MemorySnapshotCache(cached(at: here)), now: { now },
                                    didSave: { publications += 1 })
        await vm.load(forceRefresh: true)
        #expect(vm.snapshot?.aqi == 75)
        #expect(publications == 1)
    }

    @Test("Cancellation publishes neither an error nor a new cached snapshot")
    func cancellation() async {
        let cache = MemorySnapshotCache()
        let vm = DashboardViewModel(location: StubLocation(here, fails: CancellationError()),
                                    client: StubAirQualityClient(), cache: cache, now: { now })
        await vm.load()
        #expect(vm.snapshot == nil)
        #expect(cache.snapshot == nil)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
    }

    @Test("Refresh failure retains same-location stale data with a visible error")
    func staleFallback() async {
        let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(aqFails: true),
                                    cache: MemorySnapshotCache(cached(at: here)), now: { now.addingTimeInterval(4_000) })
        await vm.load()
        #expect(vm.snapshot?.aqi == 42)
        #expect(vm.errorMessage != nil)
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

    @Test("A cache write failure keeps live readings but does not publish a widget reload")
    func cacheWriteFailure() async {
        let cache = MemorySnapshotCache()
        cache.fails = true
        var publications = 0
        let vm = DashboardViewModel(location: StubLocation(here), client: StubAirQualityClient(), cache: cache,
                                    didSave: { publications += 1 })
        await vm.load()
        #expect(vm.snapshot?.aqi == 75)
        #expect(vm.errorMessage != nil)
        #expect(publications == 0)
    }

    @Test("An unavailable cache does not erase already displayed same-location readings")
    func retainsMemoryReading() async {
        let cache = MemorySnapshotCache()
        let client = StubAirQualityClient()
        let vm = DashboardViewModel(location: StubLocation(here), client: client, cache: cache)
        await vm.load()
        cache.fails = true
        await client.failAQ()
        await vm.load(forceRefresh: true)
        #expect(vm.snapshot?.aqi == 75)
        #expect(vm.errorMessage != nil)
    }
}

@MainActor
private final class StubLocation: LocationProviding {
    let coordinate: GeoCoordinate
    let failure: (any Error)?
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

private actor StubAirQualityClient: AirQualityFetching {
    var requestCount = 0
    let pollenFails: Bool
    var aqFails: Bool
    func failAQ() { aqFails = true }
    init(pollenFails: Bool = false, aqFails: Bool = false) { self.pollenFails = pollenFails; self.aqFails = aqFails }
    func airQuality(at coordinate: GeoCoordinate) async throws -> AirQualityReading {
        requestCount += 1
        if aqFails { throw URLError(.notConnectedToInternet) }
        return AirQualityReading(aqi: 75, dominantPollutant: "pm25", stationName: "Station, Country")
    }
    func pollen(at coordinate: GeoCoordinate) async throws -> PollenReading {
        if pollenFails { throw URLError(.notConnectedToInternet) }
        return PollenReading(grassIndex: 1, treeIndex: 3, weedIndex: 2)
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
