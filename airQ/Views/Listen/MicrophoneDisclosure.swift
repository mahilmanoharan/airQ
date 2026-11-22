import SwiftUI

/// First-run explanation of what listening does. Bump `version` when the wording or capture
/// behaviour changes so the sheet is shown again; the acknowledged version and time are kept.
enum MicrophoneDisclosure {
    static let version = 1
    static let acknowledgedVersionKey = "microphoneDisclosureAcknowledgedVersion"
    static let acknowledgedAtKey = "microphoneDisclosureAcknowledgedAt"
}

struct MicrophoneDisclosureSheet: View {
    var acknowledgeTitle = "Continue"
    let acknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DisclosurePoint(symbol: "iphone", title: "Analysed on this iPhone",
                                    text: "Apple's built-in sound classifier listens for coughs, sneezes and similar sounds while Listen is open.")
                    DisclosurePoint(symbol: "waveform.slash", title: "No audio is kept",
                                    text: "Audio is never recorded, stored or sent anywhere. Only sound labels, their scores, input level and times are saved.")
                    DisclosurePoint(symbol: "person.2.wave.2", title: "It can't tell who made a sound",
                                    text: "Other people, TV and music can be scored as coughs. Review lets you mark false positives.")
                    DisclosurePoint(symbol: "stop.circle", title: "Only while you're watching",
                                    text: "Listening stops when you tap Stop, leave the screen, or switch apps.")
                    DisclosurePoint(symbol: "stethoscope", title: "Not a medical device",
                                    text: "Counts are estimates for your own records and discussion with a clinician, not a diagnosis.")
                }
                .padding()
            }
            .navigationTitle("About listening")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(acknowledgeTitle, action: acknowledge)
                    .buttonStyle(AirQPrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .airQActionBar()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
    }
}

private struct DisclosurePoint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview { MicrophoneDisclosureSheet {} }
