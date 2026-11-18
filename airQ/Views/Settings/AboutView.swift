import SwiftUI
import AirQualityKit
import RespiratoryKit

/// What airQ records, what leaves the device, and the versions that define the data, so an export
/// can be read correctly later (by you, a clinician or a statistician).
struct AboutView: View {
    var body: some View {
        List {
            Section("Versions") {
                LabeledContent("App", value: AppVersion.current)
                LabeledContent("Record schema", value: "\(RespiratoryStore.schemaVersion)")
                LabeledContent("Check-in questions", value: "Set \(CheckInQuestionSet.version)")
                LabeledContent("Listening capture", value: "Semantics \(CaptureLabels.captureSemanticsVersion)")
            }
            Section {
                AboutRow(systemImage: "waveform.slash", title: "Audio is never stored",
                         detail: "Listening keeps only the classifier's per-window scores and loudness. Old sessions can't be re-analysed by a future model.")
                AboutRow(systemImage: "location", title: "Location is rounded before it's sent",
                         detail: "Air data providers and Apple Maps city lookup receive coordinates rounded to two decimals (about 1 km). The location fix is saved on this device to identify your current area. airQ asks for a new fix while it's open.")
                AboutRow(systemImage: "iphone", title: "Everything stays on this iPhone",
                         detail: "Records live in airQ's app group storage and are included in device backups. There's no account and no sync. Export regularly if the data matters to you.")
                AboutRow(systemImage: "bell", title: "Alerts are local and optional",
                         detail: "If you enable Background updates, airQ can send the last saved area to refresh widgets and check alerts while location access is granted. Alerts are generated on this device.")
                AboutRow(systemImage: "trash", title: "You can erase everything",
                         detail: "More › Erase all data deletes every check-in, event, listening record and air quality record from this iPhone, after a confirmation. Export a copy first if you want one.")
                AboutRow(systemImage: "lock.doc", title: "Nothing is overwritten",
                         detail: "Check-ins, labels and context events are append-only: editing adds a new version, and exports include every version.")
            } header: {
                Text("Your data")
            }
            Section {
                AboutRow(systemImage: "aqi.medium", title: "Air quality: World Air Quality Index Project",
                         detail: "The nearest station's current reading and daily forecast. Pollutant values are AQI sub-indices, not concentrations.")
                AboutRow(systemImage: "leaf", title: "Pollen: Google Pollen API",
                         detail: "A daily forecast (not a measurement), requested at most once per local day.")
                AboutRow(systemImage: "clock.arrow.circlepath", title: "Hourly history: Google Air Quality API",
                         detail: "Up to 29 days of hourly index values, gap-filled at most once a day.")
                Text("Google requests are capped by airQ well inside Google's free monthly usage; Records shows the current count.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sources")
            }
            Section("Not medical advice") {
                Text("airQ shows readings and your own records side by side. It doesn't diagnose, score symptoms or draw conclusions; discuss patterns with your clinician.")
                    .font(.footnote)
            }
        }
        .navigationTitle("About & data")
    }
}

private struct AboutRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
