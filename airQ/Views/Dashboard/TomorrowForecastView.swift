import SwiftUI
import AirQualityKit

struct TomorrowForecastView: View {
    let snapshot: AQSnapshot
    let dayKey: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.locationName)
                        .font(.title2.bold()).fontDesign(.rounded)
                        .accessibilityAddTraits(.isHeader)
                    Text(dateLabel)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                airForecast
                pollenForecast
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background { AirQStyle.atmosphere }
        .navigationTitle("Tomorrow’s forecast")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dateLabel: String {
        let format = Date.FormatStyle(timeZone: .gmt).weekday(.wide).month(.wide).day()
        return DayKey.date(dayKey)?.formatted(format) ?? dayKey
    }

    private var airForecast: some View {
        let forecast = snapshot.forecast?.first { $0.day == dayKey }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Air quality").font(.headline).accessibilityAddTraits(.isHeader)
            if let peak = forecast?.peak {
                let category = AirQualityPresentation.category(for: peak.subIndex)
                let pollutant = PollutantInfo.info(for: peak.code)?.name ?? StationConditions.displayName(for: peak.code)
                Text("\(category) · \(peak.subIndex) on the AQI scale")
                    .font(.title3.bold())
                Text("The station forecasts its highest level for \(pollutant).")
                    .foregroundStyle(.secondary)
            } else {
                Text("Air quality forecast unavailable")
                    .foregroundStyle(.secondary)
            }
            if let uv = forecast?.uvIndex {
                Label("UV index up to \(uv.max)", systemImage: "sun.max")
            }
        }
        .dashboardCard()
    }

    private var pollenForecast: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pollen").font(.headline).accessibilityAddTraits(.isHeader)
            if let pollen = pollenForDay, pollen.overallIndex != nil {
                PollenForecastRow(title: "Tree pollen", index: pollen.treeIndex)
                    .accessibilityIdentifier("pollenType-tree")
                PollenForecastRow(title: "Grass pollen", index: pollen.grassIndex)
                    .accessibilityIdentifier("pollenType-grass")
                PollenForecastRow(title: "Weed pollen", index: pollen.weedIndex)
                    .accessibilityIdentifier("pollenType-weed")
            } else {
                Text("Pollen forecast unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }

    private var pollenForDay: PollenOutlookDay? {
        guard let pollen = snapshot.pollenTypes,
              let offset = pollen.dayKeys?.firstIndex(of: dayKey) else { return nil }
        if offset == 0 {
            return PollenOutlookDay(grassIndex: pollen.grassIndex, treeIndex: pollen.treeIndex,
                                    weedIndex: pollen.weedIndex)
        }
        return pollen.outlook?[offset - 1]
    }
}
