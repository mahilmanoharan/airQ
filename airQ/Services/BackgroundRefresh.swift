import AirQualityKit
import BackgroundTasks
import Foundation

/// Keeps the widgets current between launches. iOS decides when (and whether) a refresh runs, so
/// this only asks; the widgets still work from the last cached reading when it doesn't.
///
/// A run refreshes the *cached place* (no location request), through the same load as the
/// dashboard: a fresh cache means no request, and pollen is still requested at most once per local
/// day. Google history is not collected in the background.
enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in InfoPlistAdditions.plist.
    static let identifier = "mahilmanoharan.airQ.refresh"
    static let preferenceKey = "backgroundWidgetRefresh"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: preferenceKey) }
    /// Just past the cache's freshness window: a run that starts sooner would find the reading still
    /// fresh and do nothing, and the next one would be a further interval away.
    static let minimumInterval: TimeInterval = AQSnapshot.freshFor + 5 * 60

    /// Asks for the next run. Replaces any pending request, so calling it often is harmless.
    static func schedule(now: Date = .now) {
        guard !AppServices.isUITesting else { return }
        guard isEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(minimumInterval)
        try? BGTaskScheduler.shared.submit(request)  // Fails on the simulator and when disabled; nothing to recover.
    }

    /// The `.backgroundTask` handler body: queue the next run first, so a failure here can't end the chain.
    static func run() async {
        guard isEnabled else { return }
        await AppServices.shared.run(.backgroundRefresh) { await refresh() }
    }

    private static func refresh() async {
        schedule()
        let prepared = await AppServices.shared.prepare()
        let eraseRevision = AppServices.shared.eraseRevision
        func refreshAllowed() -> Bool {
            isEnabled && prepared.isLocationAuthorized()
                && !AppServices.shared.isErasing && AppServices.shared.eraseRevision == eraseRevision
        }
        // Never located: nothing to refresh, and a failed attempt would only be recorded as noise.
        guard !Task.isCancelled, refreshAllowed(),
              (try? await prepared.backgroundPlace.currentCoordinate()) != nil else { return }
        await prepared.backgroundModel.load()
        if refreshAllowed() && !Task.isCancelled {
            await AirQualityAlerts.shared.deliverIfNeeded(for: prepared.backgroundModel.snapshot, whileAllowed: refreshAllowed)
        }
        // The process may be suspended once this returns; make sure every attempt is written first.
        await prepared.services?.recorder.flush()
    }
}
