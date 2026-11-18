import AirQualityKit
import Foundation
import Observation
import UserNotifications

/// Opt-in "air quality is unhealthy" and "pollen is high" notifications, sent from background
/// refresh. The decision is `AirQualityAlertPolicy` (tested in AirQualityKit); this type holds the
/// settings, asks for permission and posts local notifications. Nothing leaves the device.
@MainActor @Observable
final class AirQualityAlerts {
    static let shared = AirQualityAlerts()

    enum Permission { case unknown, allowed, denied }

    private static let settingsKey = "airQAlertSettings"
    private static let lastAlertsKey = "airQLastAlerts"

    private(set) var settings: AirQualityAlertSettings
    private(set) var permission = Permission.unknown

    init() {
        settings = UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(AirQualityAlertSettings.self, from: $0) } ?? AirQualityAlertSettings()
    }

    func refreshPermission() async {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: permission = .allowed
        case .denied: permission = .denied
        default: permission = .unknown
        }
    }

    /// Turning an alert on asks for notification permission; if it's refused, the alert stays off.
    func setEnabled(_ kind: AirQualityAlertKind, _ enabled: Bool) async {
        guard enabled else { update(kind, threshold: nil); return }
        // Alerts are silent banners (no sound is set), so only banner permission is asked for.
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
        await refreshPermission()
        guard granted else { return }
        update(kind, threshold: threshold(of: kind) ?? Self.defaultThreshold(kind))
    }

    func setThreshold(_ kind: AirQualityAlertKind, _ threshold: Int) { update(kind, threshold: threshold) }

    func threshold(of kind: AirQualityAlertKind) -> Int? {
        switch kind {
        case .air: settings.airThreshold
        case .pollen: settings.pollenThreshold
        }
    }

    static func defaultThreshold(_ kind: AirQualityAlertKind) -> Int {
        switch kind {
        case .air: AirQualityAlertSettings.defaultAirThreshold
        case .pollen: AirQualityAlertSettings.defaultPollenThreshold
        }
    }

    /// Posts whichever alerts the policy allows. Each kind's day is saved right after its post
    /// succeeds, so an interrupted run can't repeat an alert that already went out.
    func deliverIfNeeded(for snapshot: AQSnapshot?, whileAllowed: () -> Bool) async {
        guard settings.isAnyEnabled else { return }
        let due = AirQualityAlertPolicy.alerts(for: snapshot, settings: settings, lastAlertAt: lastAlertDates())
        guard !due.isEmpty else { return }
        await refreshPermission()
        guard permission == .allowed else { return }
        for alert in due {
            guard whileAllowed(), !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            do {
                try await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: AlertTapRouter.identifierPrefix + alert.kind.rawValue, content: content, trigger: nil))
                if whileAllowed() { recordAlert(alert.kind) }
            } catch {
                // Not recorded as sent, so the next refresh may try again.
            }
        }
    }

    private func recordAlert(_ kind: AirQualityAlertKind) {
        var stored = UserDefaults.standard.dictionary(forKey: Self.lastAlertsKey) as? [String: Date] ?? [:]
        stored[kind.rawValue] = Date()
        UserDefaults.standard.set(stored, forKey: Self.lastAlertsKey)
    }

    private func lastAlertDates() -> [AirQualityAlertKind: Date] {
        let stored = UserDefaults.standard.dictionary(forKey: Self.lastAlertsKey) as? [String: Date] ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            if let kind = AirQualityAlertKind(rawValue: entry.key) { result[kind] = entry.value }
        }
    }

    private func update(_ kind: AirQualityAlertKind, threshold: Int?) {
        var updated = settings
        switch kind {
        case .air: updated.airThreshold = threshold
        case .pollen: updated.pollenThreshold = threshold
        }
        settings = updated
        if let data = try? JSONEncoder().encode(updated) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
    }
}

/// Tapping an alert opens the dashboard, where the reading it describes is, whatever screen airQ was left on.
/// Set as the notification centre's delegate at launch (`airQApp.init`), before any tap can be delivered.
final class AlertTapRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertTapRouter()
    nonisolated static let identifierPrefix = "airq.alert."

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier.hasPrefix(Self.identifierPrefix) else { return }
        await MainActor.run { NavigationRouter.shared.pendingPath = [] }
    }
}
