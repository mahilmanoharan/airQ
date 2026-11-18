import SwiftUI
import AirQualityKit
import RespiratoryKit

struct DashboardMetricDetailView: View {
    let metric: DashboardMetric
    let snapshot: AQSnapshot

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch metric {
                    case .airQuality:
                        AirQualityDetailContent(snapshot: snapshot)
                    case .pollen:
                        if let pollen = snapshot.pollenTypes {
                            PollenBreakdownView(pollen: pollen, fetchedAt: snapshot.pollenFetchedAt)
                        } else {
                            Text("Pollen breakdown and outlook are unavailable for this reading.")
                                .foregroundStyle(.secondary)
                                .airQCard()
                        }
                    }
                    ReadingScaleView(metric: metric, snapshot: snapshot)
                        .id("scale")
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            #if DEBUG
            .task {
                let defaults = UserDefaults.standard
                if let anchor = defaults.string(forKey: "dashboardScrollTo") {
                    await Task.yield()
                    proxy.scrollTo(anchor, anchor: .top)
                } else if defaults.bool(forKey: "explainScale") {
                    await Task.yield()
                    proxy.scrollTo("scale", anchor: .top)
                }
            }
            #endif
        }
        .background(AirQStyle.page)
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AirQualityDetailContent: View {
    let snapshot: AQSnapshot
    @Environment(\.recordStore) private var records
    @Environment(\.environmentRecorder) private var recorder

    private var place: RecordPlace? {
        snapshot.coordinate.map { RecordPlace(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        if let records, let place {
            RecentAirQualityCard(records: records, place: place, refreshKey: recorder?.revision ?? 0)
                .id("recentAirQuality")
        }
        let upcoming = AirQualityForecastDay.upcoming(snapshot.forecast ?? [], asOf: .now)
        if !upcoming.isEmpty {
            AirQualityForecastCard(days: upcoming)
        }
        if let conditions = snapshot.conditions, !conditions.isEmpty {
            StationConditionsView(conditions: conditions, dominantPollutant: snapshot.dominantPollutant)
        }
        if let pollutant = snapshot.dominantPollutant,
           snapshot.conditions?.pollutants.contains(where: { $0.code == pollutant }) != true {
            LabeledContent("Main pollutant", value: StationConditions.displayName(for: pollutant))
                .airQCard()
        }
        if let station = snapshot.station {
            StationProvenanceView(station: station, deviceCoordinate: snapshot.coordinate, fetchedAt: snapshot.lastUpdated)
        }
        if let records, let place {
            MonthAirQualityCard(records: records, place: place, refreshKey: recorder?.revision ?? 0)
                .id("monthSummary")
        }
        DataSourcesFooter(attributions: snapshot.attributions ?? [])
            .id("dataSources")
    }
}
