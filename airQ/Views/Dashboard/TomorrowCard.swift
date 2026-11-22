import SwiftUI
import AirQualityKit

/// Tomorrow's air and pollen from the saved forecast, for planning a run, a trip or open windows. It shows
/// nothing when the saved reading carries no forecast for tomorrow (no request is made for it).
struct TomorrowCard: View {
    let snapshot: AQSnapshot
    let open: (String) -> Void

    var body: some View {
        if let day = TimelineScheduler.tomorrow(for: snapshot) {
            let title = "Tomorrow’s forecast"
            let readings = summary(for: day)
            Button { open(day.dayKey) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.headline)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(readings, id: \.self) { reading in
                        Text(reading).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .dashboardCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(([title] + readings).joined(separator: ", "))
            .accessibilityHint("Opens forecast details")
            .accessibilityIdentifier("tomorrowForecast")
        }
    }

    private func summary(for day: OutlookDay) -> [String] {
        [
            day.aqiPeak.map { "Air quality up to \($0) · \(AirQualityPresentation.category(for: $0))" },
            day.pollenIndex.map { "Pollen \($0) of 5 · \(PollenPresentation.category(for: $0))" }
        ].compactMap { $0 }
    }
}

#Preview {
    TomorrowCard(snapshot: AQSnapshot(
        aqi: 42, dominantPollutant: "pm25", pollenIndex: 2, locationName: "San Francisco", lastUpdated: .now,
        forecast: [.init(day: DayKey.local(.now.addingTimeInterval(86_400)),
                         pollutants: ["pm25": .init(min: 20, average: 40, max: 68)], uvIndex: nil)])) { _ in }
    .padding()
}
