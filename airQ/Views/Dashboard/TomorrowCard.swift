import SwiftUI
import AirQualityKit

/// Tomorrow's air and pollen from the saved forecast, for planning a run, a trip or open windows. It shows
/// nothing when the saved reading carries no forecast for tomorrow (no request is made for it).
struct TomorrowCard: View {
    let snapshot: AQSnapshot

    var body: some View {
        if let day = TimelineScheduler.tomorrow(for: snapshot) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Tomorrow", systemImage: "calendar")
                    .font(.headline)
                if let aqi = day.aqiPeak {
                    Text("Air quality up to \(aqi) · \(AirQualityPresentation.category(for: aqi))")
                }
                if let pollen = day.pollenIndex {
                    Text("Pollen \(pollen) of 5 · \(PollenPresentation.category(for: pollen))")
                }
                Text("A forecast, not a measurement.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .dashboardCard()
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    TomorrowCard(snapshot: AQSnapshot(
        aqi: 42, dominantPollutant: "pm25", pollenIndex: 2, locationName: "San Francisco", lastUpdated: .now,
        forecast: [.init(day: DayKey.local(.now.addingTimeInterval(86_400)),
                         pollutants: ["pm25": .init(min: 20, average: 40, max: 68)], uvIndex: nil)]))
    .padding()
}
