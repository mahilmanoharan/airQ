import SwiftUI
import AirQualityKit

/// What most people need at a glance: where, the two numbers with their words, what they mean in
/// plain language, and how fresh they are. Everything technical lives in `DashboardDetailsView`.
struct DashboardEssentialsView: View {
    let snapshot: AQSnapshot

    var body: some View {
        VStack(spacing: 14) {
            Text(snapshot.locationName).font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { cards }
                VStack(spacing: 14) { cards }
            }
            Text("Updated \(snapshot.lastUpdated, style: .relative) ago")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var cards: some View {
        ReadingCardView.aqi(snapshot.aqi)
        ReadingCardView.pollen(snapshot.pollenIndex)
    }
}

struct DashboardMeaningView: View {
    let snapshot: AQSnapshot
    @State private var isExplainingScale = false

    var body: some View {
        VStack(spacing: 16) {
            Button("What do these numbers mean?", systemImage: "questionmark.circle") { isExplainingScale = true }
                .buttonStyle(.bordered).controlSize(.large).tint(.primary)
            DisclosureGroup("What today's air means") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AirQualityPresentation.guidance(for: snapshot.aqi))
                    Text(PollenPresentation.guidance(for: snapshot.pollenIndex))
                }
                .font(.subheadline).padding(.top, 12)
            }
            .airQCard()
        }
        .sheet(isPresented: $isExplainingScale) {
            ScaleExplainerSheet(aqi: snapshot.aqi, pollenIndex: snapshot.pollenIndex)
        }
        #if DEBUG
        .task {
            guard UserDefaults.standard.bool(forKey: "explainScale") else { return }
            try? await Task.sleep(for: .seconds(1))
            isExplainingScale = true
        }
        #endif
    }
}

/// The technical detail behind the two numbers, shown on request: which station, the pollutants,
/// the weather there, the forecast and pollen by type.
struct DashboardDetailsView: View {
    let snapshot: AQSnapshot

    var body: some View {
        VStack(spacing: 24) {
            if let station = snapshot.station {
                StationProvenanceView(station: station, deviceCoordinate: snapshot.coordinate,
                                      fetchedAt: snapshot.lastUpdated)
            }
            if let pollutant = snapshot.dominantPollutant {
                Text("Main pollutant: \(StationConditions.displayName(for: pollutant))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let conditions = snapshot.conditions, !conditions.isEmpty {
                StationConditionsView(conditions: conditions, dominantPollutant: snapshot.dominantPollutant)
            }
            let upcoming = AirQualityForecastDay.upcoming(snapshot.forecast ?? [], asOf: .now)
            if !upcoming.isEmpty {
                AirQualityForecastCard(days: upcoming)
            }
            if let pollen = snapshot.pollenTypes, pollen.overallIndex != nil {
                PollenBreakdownView(pollen: pollen, fetchedAt: snapshot.pollenFetchedAt)
            }
        }
    }
}
