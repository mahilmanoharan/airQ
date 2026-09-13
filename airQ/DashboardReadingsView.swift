import SwiftUI
import AirQualityKit

struct DashboardReadingsView: View {
    let snapshot: AQSnapshot

    var body: some View {
        VStack(spacing: 24) {
            Text(snapshot.locationName)
                .font(.title2.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { cards }
                VStack(spacing: 16) { cards }
            }
            if let pollutant = snapshot.dominantPollutant {
                Text("Primary pollutant: \(pollutant.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            AnalysisCardView(title: "AQI analysis",
                             message: AirQualityPresentation.guidance(for: snapshot.aqi),
                             tintColor: AirQualityPresentation.color(for: snapshot.aqi))
            AnalysisCardView(title: "Pollen analysis",
                             message: PollenPresentation.guidance(for: snapshot.pollenIndex),
                             tintColor: PollenPresentation.color(for: snapshot.pollenIndex))
            Text("Updated \(snapshot.lastUpdated, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var cards: some View {
        AQICardView(aqi: snapshot.aqi)
        PollenCardView(index: snapshot.pollenIndex)
    }
}
