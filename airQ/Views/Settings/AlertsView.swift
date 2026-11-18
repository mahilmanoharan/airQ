import SwiftUI
import AirQualityKit

/// Opt-in notifications for unhealthy air and high pollen. Explains its limits plainly: iOS decides
/// when the background check runs, so an alert is best-effort, never a guarantee.
struct AlertsView: View {
    @State private var alerts = AirQualityAlerts.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BackgroundRefresh.preferenceKey) private var refreshEnabled = false
    /// Not observable, so it is re-read whenever the screen appears or the app becomes active again
    /// (for example on return from Settings).
    @State private var backgroundRefresh = UIApplication.shared.backgroundRefreshStatus

    var body: some View {
        List {
            Section {
                Toggle("Background updates", isOn: $refreshEnabled)
                    .accessibilityIdentifier("backgroundWidgetRefresh")
            } footer: {
                Text("Allow widgets and alerts to update when airQ is closed. Updates send the last saved area, rounded to about 1 km, while location access is granted.")
            }
            AlertSection(kind: .air, alerts: alerts, title: "Unhealthy air",
                         toggleLabel: "Alert me about unhealthy air", thresholds: AirQualityAlertSettings.airThresholds) {
                "AQI \($0)+ · \(AirQualityPresentation.category(for: $0))"
            }
            AlertSection(kind: .pollen, alerts: alerts, title: "High pollen",
                         toggleLabel: "Alert me about high pollen", thresholds: AirQualityAlertSettings.pollenThresholds) {
                "\(PollenPresentation.category(for: $0)) or higher"
            }
            switch backgroundRefresh {
            case .denied:
                Section {
                    Text("Background App Refresh is off for airQ, so alerts (and background widget updates) can't run. Turn it on in Settings › General › Background App Refresh.")
                        .font(.footnote)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .restricted:
                Section {
                    Text("Background App Refresh is restricted on this device (for example by Screen Time or a device policy), so alerts and background widget updates can't run.")
                        .font(.footnote)
                }
            default:
                EmptyView()
            }
            if alerts.permission == .denied {
                Section {
                    Text("Notifications are turned off for airQ in Settings.").font(.footnote)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            Section {
                Text("airQ checks in the background when iOS allows it, so an alert can arrive late or not at all. Each kind is sent at most once a day, for your last known place; open airQ to update the place. Nothing is sent between 10 pm and 7 am: an alert held overnight comes with the first check after 7 am, if the air is still that bad. Pollen alerts use today's forecast. Alerts are generated on this iPhone and share nothing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Air quality alerts")
        .onChange(of: refreshEnabled) { BackgroundRefresh.schedule() }
        .task { await alerts.refreshPermission() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
            Task { await alerts.refreshPermission() }
        }
    }
}

private struct AlertSection: View {
    let kind: AirQualityAlertKind
    let alerts: AirQualityAlerts
    let title: String
    let toggleLabel: String
    let thresholds: [Int]
    let label: (Int) -> String

    var body: some View {
        Section(title) {
            Toggle(toggleLabel, isOn: Binding(
                get: { alerts.threshold(of: kind) != nil },
                set: { on in Task { await alerts.setEnabled(kind, on) } }))
            if let current = alerts.threshold(of: kind) {
                Picker("Alert at", selection: Binding(get: { current }, set: { alerts.setThreshold(kind, $0) })) {
                    ForEach(thresholds, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }
}
