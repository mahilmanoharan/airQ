import Foundation
import Observation

/// Owns a single end-to-end load. Views render state and forward user actions.
@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var snapshot: AQSnapshot?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let location: any LocationProviding
    private let client: any AirQualityFetching
    private let cache: any SnapshotCaching
    private let now: () -> Date
    private let didSave: () -> Void
    @ObservationIgnored private var loadWaiters: [CheckedContinuation<Bool, Never>] = []

    public init(location: any LocationProviding, client: any AirQualityFetching,
                cache: any SnapshotCaching, now: @escaping () -> Date = Date.init,
                didSave: @escaping () -> Void = {}) {
        self.location = location
        self.client = client
        self.cache = cache
        self.now = now
        self.didSave = didSave
    }

    public func load(forceRefresh: Bool = false) async {
        if isLoading {
            // Coalesce callers, but let a newly visible view retry after the old
            // view's cancelled task has released its location/network resources.
            let previousWasCancelled = await withCheckedContinuation { loadWaiters.append($0) }
            if previousWasCancelled, !Task.isCancelled { await load(forceRefresh: forceRefresh) }
            return
        }
        guard !Task.isCancelled else { return }
        isLoading = true
        errorMessage = nil
        var wasCancelled = false
        defer {
            isLoading = false
            let waiting = loadWaiters
            loadWaiters.removeAll(keepingCapacity: true)
            for waiter in waiting { waiter.resume(returning: wasCancelled || Task.isCancelled) }
        }

        do {
            let coordinate = try await location.currentCoordinate()
            try Task.checkCancellation()
            // A corrupt/unavailable widget cache must not prevent a live fetch.
            let cached = (try? cache.load()) ?? snapshot
            let matching = cached.flatMap { value in
                value.coordinate?.isNear(coordinate) == true ? value : nil
            }
            snapshot = matching
            if !forceRefresh, let matching, matching.isFresh(asOf: now()) { return }

            async let airQuality = client.airQuality(at: coordinate)
            async let pollen = optionalPollen(at: coordinate)
            async let city = location.cityName(for: coordinate)
            let (reading, pollenReading, cityName) = try await (airQuality, pollen, city)
            try Task.checkCancellation()

            let updated = AQSnapshot(
                aqi: reading.aqi, dominantPollutant: reading.dominantPollutant,
                pollenIndex: pollenReading?.overallIndex,
                locationName: cityName ?? Self.fallbackName(reading.stationName),
                lastUpdated: now(), coordinate: coordinate
            )
            snapshot = updated
            do {
                try cache.save(updated)
                didSave()
            } catch {
                errorMessage = "Updated readings could not be saved for widgets."
            }
        } catch is CancellationError {
            // SwiftUI cancels its task when the owning view leaves the hierarchy.
            wasCancelled = true
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func optionalPollen(at coordinate: GeoCoordinate) async throws -> PollenReading? {
        do { return try await client.pollen(at: coordinate) }
        catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            return nil
        }
    }

    private static func fallbackName(_ station: String) -> String {
        let first = station.split(separator: ",", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return first.flatMap { $0.isEmpty ? nil : $0 } ?? "Current Location"
    }
}
