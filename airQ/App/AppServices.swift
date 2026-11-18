import AirQualityKit
import Observation
import RespiratoryKit
import SwiftData
import UIKit
import WidgetKit

/// Composes the app's long-lived services once, for the UI and for background refresh. Both need
/// the same record container: opening it twice in one process would give two writers on one store.
@MainActor
@Observable
final class AppServices {
    static let shared = AppServices()

    struct Prepared {
        let dashboard: DashboardViewModel
        /// Refreshes the cached place without asking for a location (background refresh).
        let backgroundModel: DashboardViewModel
        /// The place background refresh would use; nil-throwing when the app has never located.
        let backgroundPlace: CachedPlaceLocation
        let isLocationAuthorized: () -> Bool
        let clearSnapshot: () -> Void
        let services: RecordServices?
        let store: DetectionStore?
        let container: ModelContainer?
        let storeError: String?
    }

    /// DEBUG `-uiTestMode YES` (set by the UI tests): an in-memory record store and no network.
    static var isUITesting: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "uiTestMode")
        #else
        false
        #endif
    }

    private var preparation: Task<Prepared, Never>?
    enum Activity: Hashable { case listening, backgroundRefresh }
    private var activeTasks: [Activity: Task<Void, Never>] = [:]
    private var exports: [WeakExport] = []
    private(set) var isErasing = false
    private(set) var eraseRevision = 0

    private final class WeakExport {
        weak var model: ExportViewModel?
        init(_ model: ExportViewModel) { self.model = model }
    }

    func prepare() async -> Prepared {
        if let preparation { return await preparation.value }
        let task = Task { await Self.build() }
        preparation = task
        return await task.value
    }

    func run(_ activity: Activity, work: @escaping @MainActor () async -> Void) async {
        guard !isErasing, activeTasks[activity] == nil, !Task.isCancelled else { return }
        let task = Task { await work() }
        activeTasks[activity] = task
        defer { activeTasks[activity] = nil }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func registerExport(_ model: ExportViewModel) -> Bool {
        guard !isErasing else { return false }
        exports.removeAll { $0.model == nil }
        if !exports.contains(where: { $0.model === model }) { exports.append(WeakExport(model)) }
        return true
    }

    /// Drain producers before the wipe, so their last observations are included in the deletion
    /// and the provider ledger. Reject new writes throughout the deletion.
    func eraseRecords(_ wipe: () async throws -> Void) async throws {
        guard !isErasing else { throw RecordStoreError.eraseInProgress }
        isErasing = true
        defer { isErasing = false }
        let prepared = await prepare()
        let records = prepared.services?.recordStore
        prepared.dashboard.pauseLoads()
        prepared.backgroundModel.pauseLoads()
        prepared.services?.cancelCollection()
        let running = Array(activeTasks.values)
        for task in running { task.cancel() }
        defer {
            prepared.dashboard.resumeLoads()
            prepared.backgroundModel.resumeLoads()
        }
        for task in running { await task.value }
        for model in exports.compactMap(\.model) { await model.cancelAndWait() }
        await prepared.dashboard.drainLoads()
        await prepared.backgroundModel.drainLoads()
        await prepared.services?.drainCollection()
        await prepared.services?.recorder.flush()
        await records?.setWritesPaused(true)
        await prepared.store?.setWritesPaused(true)
        do {
            try await wipe()
        } catch {
            await records?.setWritesPaused(false)
            await prepared.store?.setWritesPaused(false)
            throw error
        }
        prepared.clearSnapshot()
        prepared.dashboard.forgetReading()
        prepared.backgroundModel.forgetReading()
        eraseRevision += 1
        await records?.setWritesPaused(false)
        await prepared.store?.setWritesPaused(false)
        await prepared.services?.recorder.markToday()
    }

    /// The real location, or UI-test fixtures (fixed place, fresh reading).
    private static func location() -> any LocationProviding {
        #if DEBUG
        if isUITesting { return UITestLocation() }
        #endif
        return LocationManager()
    }

    private static func snapshotCache() -> (cache: any SnapshotCaching, clear: () -> Void) {
        #if DEBUG
        if isUITesting {
            let cache = UITestSnapshotCache()
            return (cache, cache.clear)
        }
        #endif
        let cache = AppGroupSnapshotCache()
        return (cache, cache.clear)
    }

    /// Opens the shared record container before the dashboard so no provider attempt goes unrecorded.
    /// A storage failure leaves air quality usable (with Google requests refused, since their usage
    /// can't be counted) and disables the respiratory screens with an explanation.
    private static func build() async -> Prepared {
        #if DEBUG
        // Seed a writable preference, rather than a launch-argument override that would pin the picker.
        if isUITesting, let requested = UserDefaults.standard.string(forKey: "uiTestHistoryPeriod"),
           let days = Int(requested), HistoryPeriod(rawValue: days) != nil {
            UserDefaults.standard.set(days, forKey: "historyPeriodDays")
        }
        #endif
        // A crash or termination can bypass ExportView.onDisappear. Remove only our disposable copies.
        try? ExportRecovery.removeAbandonedArchives(in: FileManager.default.temporaryDirectory.appending(path: "Exports"))
        let client = isUITesting
            // No credentials: any request fails as missingCredentials before reaching a provider.
            ? HTTPAirQualityClient(waqiToken: "", pollenAPIKey: "", bundleIdentifier: nil)
            : makeAirQualityClient()
        let foregroundLocation = location()
        let isLocationAuthorized: @MainActor @Sendable () -> Bool = {
            #if DEBUG
            if isUITesting { return !UserDefaults.standard.bool(forKey: "uiTestLocationDenied") }
            #endif
            return (foregroundLocation as? LocationManager)?.isAuthorized == true
        }
        var opened: RecordServices?
        var store: DetectionStore?
        var container: ModelContainer?
        var storeError: String?
        do {
            // UI tests write to a throwaway store: saved rows are append-only and permanent.
            let opening = isUITesting
                ? try RespiratoryStore.makeInMemoryContainer()
                : try await RespiratoryStore.openContainer()
            let recordServices = RecordServices(recordStore: await RecordStore.open(container: opening), client: client,
                                                maySendLocation: {
                isLocationAuthorized() && UIApplication.shared.applicationState == .active && !shared.isErasing
            })
            store = await DetectionStore.open(container: opening)
            container = opening
            opened = recordServices
            #if DEBUG
            if isUITesting && UserDefaults.standard.bool(forKey: "uiTestHistory") {
                try await UITestHistoryFixtures.seed(records: recordServices.recordStore)
            }
            #endif
        } catch {
            storeError = "Health records could not be opened: \(error.localizedDescription)"
        }
        let recorder = opened?.recorder
        let budget = opened?.budget ?? RecordServices.unavailableBudget
        // One gate for both models: a foreground load and a background refresh never fetch together.
        let gate = LoadGate()
        func model(location: any LocationProviding, cache: any SnapshotCaching,
                   maySendLocation: @escaping () -> Bool) -> DashboardViewModel {
            DashboardViewModel(
                location: location, client: client, cache: cache, budget: budget, gate: gate,
                didSave: {
                    WidgetCenter.shared.reloadAllTimelines()
                    ControlCenter.shared.reloadAllControls()
                },
                onProviderAttempt: { attempt in recorder?.enqueue(attempt) },
                maySendLocation: maySendLocation)
        }
        let (cache, clear) = snapshotCache()
        let place = CachedPlaceLocation(cache: cache)
        return Prepared(dashboard: model(location: foregroundLocation, cache: cache,
                                         maySendLocation: isLocationAuthorized),
                        backgroundModel: model(location: place, cache: cache, maySendLocation: {
                            BackgroundRefresh.isEnabled && isLocationAuthorized() && !shared.isErasing
                        }), backgroundPlace: place, isLocationAuthorized: isLocationAuthorized, clearSnapshot: clear,
                        services: opened, store: store, container: container, storeError: storeError)
    }
}
