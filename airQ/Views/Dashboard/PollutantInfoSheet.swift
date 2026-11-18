import SwiftUI
import AirQualityKit

/// Plain-language background on one pollutant: what it is, where it comes from, and why it matters
/// for breathing. Descriptive only; it doesn't interpret the user's own readings.
struct PollutantInfo {
    let name: String
    let what: String
    let sources: String
    let breathing: String

    static func info(for code: String) -> PollutantInfo? {
        switch code {
        case "pm25":
            PollutantInfo(name: "Fine particles (PM2.5)",
                          what: "Particles 2.5 micrometres across or smaller, about 30 times thinner than a hair.",
                          sources: "Vehicle exhaust, wood burning, wildfire smoke, industry, and reactions between other pollutants.",
                          breathing: "Small enough to reach deep into the lungs; linked to airway irritation and asthma flare-ups.")
        case "pm10":
            PollutantInfo(name: "Coarse particles (PM10)",
                          what: "Particles 10 micrometres across or smaller, including the fine PM2.5 fraction.",
                          sources: "Road and construction dust, pollen fragments, sea salt and agriculture.",
                          breathing: "Mostly caught in the nose and upper airways; can irritate them and trigger coughing.")
        case "o3":
            PollutantInfo(name: "Ground-level ozone (O₃)",
                          what: "A gas formed when nitrogen oxides and other pollutants react in sunlight.",
                          sources: "Not emitted directly; levels usually peak on warm, sunny afternoons downwind of traffic.",
                          breathing: "Irritates the airways and can reduce lung function during exertion.")
        case "no2":
            PollutantInfo(name: "Nitrogen dioxide (NO₂)",
                          what: "A reddish-brown gas and one of the nitrogen oxides.",
                          sources: "Mainly road traffic and burning fuel; higher near busy roads.",
                          breathing: "Irritates the airways; also helps form ozone and fine particles.")
        case "so2":
            PollutantInfo(name: "Sulphur dioxide (SO₂)",
                          what: "A gas with a sharp smell.",
                          sources: "Burning sulphur-containing fuels: power plants, industry, ships and volcanoes.",
                          breathing: "Can tighten the airways within minutes, especially in people with asthma.")
        case "co":
            PollutantInfo(name: "Carbon monoxide (CO)",
                          what: "An odourless gas from incomplete burning.",
                          sources: "Vehicles and fuel-burning appliances; outdoor levels are usually low.",
                          breathing: "Reduces how much oxygen the blood carries rather than irritating the airways.")
        default:
            nil
        }
    }
}

struct PollutantInfoSheet: View {
    let pollutant: StationConditions.Pollutant
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let info = PollutantInfo.info(for: pollutant.code) {
                    Section("What it is") { Text(info.what) }
                    Section("Common sources") { Text(info.sources) }
                    Section("Why it matters for breathing") { Text(info.breathing) }
                }
                Section("This reading") {
                    LabeledContent("Station sub-index", value: "\(pollutant.subIndex)")
                    LabeledContent("AQI category", value: AirQualityPresentation.category(for: pollutant.subIndex))
                    Text("The sub-index puts this pollutant on the same scale as the AQI (up to 500; the bars on the dashboard stop at 300); it isn't a concentration. The overall AQI is the highest sub-index.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(PollutantInfo.info(for: pollutant.code)?.name ?? pollutant.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    // One literal pollutant, so the list always has an element.
    PollutantInfoSheet(pollutant: StationConditions(subIndices: ["pm25": 42]).pollutants[0])
}
