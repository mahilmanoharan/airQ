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
                setupStatus
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                Toggle("Background updates", isOn: $refreshEnabled)
                    .accessibilityIdentifier("backgroundWidgetRefresh")
                Text("Allow widgets and alerts to update when airQ is closed. Updates send the last saved area, rounded to about 1 km, while location access is granted.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !refreshEnabled && alerts.permission == .denied {
                Section { notificationStatus }
            }
            AlertSection(kind: .air, alerts: alerts, title: "Unhealthy air",
                         toggleLabel: "Alert me about unhealthy air", thresholds: AirQualityAlertSettings.airThresholds) {
                "AQI \($0)+ · \(AirQualityPresentation.category(for: $0))"
            }
            AlertSection(kind: .pollen, alerts: alerts, title: "High pollen",
                         toggleLabel: "Alert me about high pollen", thresholds: AirQualityAlertSettings.pollenThresholds) {
                "\(PollenPresentation.category(for: $0)) or higher"
            }
            Section {
                AlertDeliveryDetails()
            }
        }
        .scrollContentBackground(.hidden)
        .background { AirQStyle.background }
        .navigationTitle("Air quality alerts")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: refreshEnabled) { BackgroundRefresh.schedule() }
        .task { await alerts.refreshPermission() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
            Task { await alerts.refreshPermission() }
        }
    }

    @ViewBuilder private var setupStatus: some View {
        if !refreshEnabled {
            statusCard("Background updates are off", symbol: "bell.slash",
                       detail: "Turn on Background updates below so airQ can check conditions while it’s closed.")
        } else if backgroundRefresh == .denied {
            statusCard("Background App Refresh is off", symbol: "arrow.clockwise",
                       detail: "Turn it on in Settings › General › Background App Refresh.", showsSettings: true)
        } else if backgroundRefresh == .restricted {
            statusCard("Background App Refresh is restricted", symbol: "lock",
                       detail: "Screen Time or a device policy can restrict background widget updates and alerts.")
        } else if alerts.permission == .denied {
            notificationStatus
        } else if alerts.settings.isAnyEnabled {
            statusCard("Alerts selected", symbol: "bell",
                       detail: "Background checks need location access and use your last saved place.")
        } else {
            statusCard("Choose your alerts", symbol: "bell",
                       detail: "Turn on unhealthy air, high pollen, or both. iOS may ask for notification permission.")
        }
    }

    private var notificationStatus: some View {
        statusCard("Notifications are off", symbol: "bell.slash",
                   detail: "Allow notifications for airQ in Settings to receive alerts.", showsSettings: true)
    }

    private func statusCard(_ title: String, symbol: String, detail: String, showsSettings: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AirQStyle.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
            if showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AirQStyle.surface, in: RoundedRectangle(cornerRadius: AirQStyle.cardRadius))
    }
}

private struct AlertDeliveryDetails: View {
    var body: some View {
        DisclosureGroup("How alerts work") {
            VStack(alignment: .leading, spacing: 12) {
                Text("iOS decides when airQ can check in the background. An alert can arrive late or not at all.")
                Text("Quiet hours are between 10 pm and 7 am. An alert can arrive after 7 am if conditions still meet your alert level.")
                Text("Each alert type can arrive once a day for your last saved place. Open airQ to update that place. Pollen alerts use today’s forecast.")
            }
            .padding(.vertical, 8)
        }
        .tint(.primary)
        .frame(minHeight: 44)
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
